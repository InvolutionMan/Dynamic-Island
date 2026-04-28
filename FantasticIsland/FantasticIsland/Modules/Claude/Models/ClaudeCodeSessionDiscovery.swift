import Foundation

struct ClaudeCodeConversationMessage: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
        case tool
    }

    let id: String
    let role: Role
    let text: String
    let timestamp: Date?
}

struct ClaudeCodeSessionSnapshot {
    let session: SessionSnapshot
    let messages: [ClaudeCodeConversationMessage]
}

struct ClaudeCodeSessionDiscovery {
    private let fileManager: FileManager
    let rootURL: URL
    let maxFiles: Int
    let maxAge: TimeInterval

    init(
        rootURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true),
        maxFiles: Int = 24,
        maxAge: TimeInterval = 86_400 * 14,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.maxFiles = maxFiles
        self.maxAge = maxAge
        self.fileManager = fileManager
    }

    func discoverRecentSessions(now: Date = .now) -> [ClaudeCodeSessionSnapshot] {
        guard fileManager.fileExists(atPath: rootURL.path),
              let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let cutoff = now.addingTimeInterval(-maxAge)
        var candidates: [(url: URL, modifiedAt: Date)] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }

            let modifiedAt = values.contentModificationDate ?? .distantPast
            guard modifiedAt >= cutoff else {
                continue
            }

            candidates.append((fileURL, modifiedAt))
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.modifiedAt == rhs.modifiedAt {
                    return lhs.url.lastPathComponent > rhs.url.lastPathComponent
                }

                return lhs.modifiedAt > rhs.modifiedAt
            }
            .prefix(maxFiles)
            .compactMap { candidate in
                discoverSession(at: candidate.url, modifiedAt: candidate.modifiedAt, now: now)
            }
    }

    private func discoverSession(at url: URL, modifiedAt: Date, now: Date) -> ClaudeCodeSessionSnapshot? {
        guard let data = try? Data(contentsOf: url),
              !data.isEmpty else {
            return nil
        }

        let lines = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        var sessionID = url.deletingPathExtension().lastPathComponent
        var cwd = inferredCWD(from: url)
        var latestTimestamp: Date?
        var latestUserPrompt: String?
        var latestAssistantMessage: String?
        var latestToolSummary: String?
        var messages: [ClaudeCodeConversationMessage] = []

        for line in lines {
            guard let object = jsonObject(for: line),
                  let type = object["type"] as? String else {
                continue
            }

            if let objectSessionID = object["sessionId"] as? String, !objectSessionID.isEmpty {
                sessionID = objectSessionID
            }
            if let objectCWD = object["cwd"] as? String, !objectCWD.isEmpty {
                cwd = objectCWD
            }

            let timestamp = parseFlexibleDate(object["timestamp"])
            if let timestamp, latestTimestamp == nil || timestamp > (latestTimestamp ?? .distantPast) {
                latestTimestamp = timestamp
            }

            switch type {
            case "user":
                guard let text = messageText(from: object) else {
                    continue
                }
                latestUserPrompt = clipped(text, limit: 320)
                messages.append(ClaudeCodeConversationMessage(
                    id: messageID(from: object, fallback: "\(sessionID)-user-\(messages.count)"),
                    role: .user,
                    text: text,
                    timestamp: timestamp
                ))

            case "assistant":
                guard let text = messageText(from: object) else {
                    continue
                }
                latestAssistantMessage = clipped(text, limit: 640)
                messages.append(ClaudeCodeConversationMessage(
                    id: messageID(from: object, fallback: "\(sessionID)-assistant-\(messages.count)"),
                    role: .assistant,
                    text: text,
                    timestamp: timestamp
                ))

            case "tool_result", "tool_use":
                if let text = messageText(from: object) {
                    latestToolSummary = clipped(text, limit: 160)
                    messages.append(ClaudeCodeConversationMessage(
                        id: messageID(from: object, fallback: "\(sessionID)-tool-\(messages.count)"),
                        role: .tool,
                        text: text,
                        timestamp: timestamp
                    ))
                }

            default:
                continue
            }
        }

        guard latestUserPrompt != nil || latestAssistantMessage != nil || !messages.isEmpty else {
            return nil
        }

        let isFresh = now.timeIntervalSince(modifiedAt) <= SessionSnapshot.liveSessionStalenessWindow
        let phase: SessionPhase = isFresh ? .running : .completed
        let assistantSummary = latestAssistantMessage ?? latestToolSummary ?? "Claude Code session."
        let recentMessages = Array(messages.suffix(8))
        let jumpTarget = CodexTerminalJumpTarget(
            sessionID: sessionID,
            transcriptPath: url.path,
            terminalApp: "Terminal",
            workspaceName: workspaceName(for: cwd),
            paneTitle: "claude",
            workingDirectory: cwd,
            bundleIdentifier: "com.apple.Terminal"
        )

        let session = SessionSnapshot(
            id: sessionID,
            cwd: cwd,
            title: title(for: cwd),
            transcriptPath: url.path,
            phase: phase,
            lastEventAt: latestTimestamp ?? modifiedAt,
            currentTool: isFresh ? "Claude" : nil,
            currentCommandPreview: latestToolSummary,
            latestUserPrompt: latestUserPrompt,
            latestAssistantMessage: latestAssistantMessage,
            completionMessageMarkdown: latestAssistantMessage,
            assistantSummary: assistantSummary,
            jumpTarget: jumpTarget,
            sessionSurface: .terminal,
            sourceFlags: [.rollout],
            isSessionEnded: !isFresh
        )

        return ClaudeCodeSessionSnapshot(session: session, messages: recentMessages)
    }

    private func messageText(from object: [String: Any]) -> String? {
        if let text = joinedTextRaw(from: object["message"]) {
            return clipped(text, limit: 900)
        }

        if let text = joinedTextRaw(from: object["content"]) {
            return clipped(text, limit: 900)
        }

        if let text = joinedTextRaw(from: object["toolUseResult"]) {
            return clipped(text, limit: 900)
        }

        return nil
    }

    private func messageID(from object: [String: Any], fallback: String) -> String {
        for key in ["uuid", "messageId", "id"] {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }

        if let message = object["message"] as? [String: Any],
           let value = message["id"] as? String,
           !value.isEmpty {
            return value
        }

        return fallback
    }

    private func inferredCWD(from url: URL) -> String {
        let projectName = url.deletingLastPathComponent().lastPathComponent
        let raw = projectName
            .replacingOccurrences(of: "--", with: "\u{0}")
            .replacingOccurrences(of: "-", with: "/")
            .replacingOccurrences(of: "\u{0}", with: "-")
        return raw.hasPrefix("/") ? raw : FileManager.default.homeDirectoryForCurrentUser.path
    }

    private func title(for cwd: String) -> String {
        let workspace = workspaceName(for: cwd)
        return workspace.isEmpty ? "Claude Code" : "Claude Code · \(workspace)"
    }

    private func workspaceName(for cwd: String) -> String {
        let workspace = URL(fileURLWithPath: cwd).lastPathComponent
        return workspace.isEmpty ? "Claude Code" : workspace
    }
}
