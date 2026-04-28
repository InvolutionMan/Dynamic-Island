import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class ClaudeCodeModuleModel: ObservableObject, IslandModule {
    static let moduleID = "claude-code"

    @Published private(set) var isClaudeRunning = false
    @Published private(set) var cliStatusText = "Checking"
    @Published private(set) var lastRefreshedAt = Date()
    @Published private(set) var sessions: [SessionSnapshot] = []
    @Published private(set) var conversationsBySessionID: [String: [ClaudeCodeConversationMessage]] = [:]

    let id = ClaudeCodeModuleModel.moduleID
    let title = "Claude Code"
    let symbolName = "curlybraces.square"
    let iconAssetName: String? = "claudeIcon"

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 2
    private let sessionDiscovery = ClaudeCodeSessionDiscovery()
    private let terminalJumpService = CodexTerminalJumpService()

    init() {
        refreshModuleStatus()
        startPollingTimer()
    }

    deinit {
        pollTimer?.invalidate()
    }

    var collapsedSummaryItems: [CollapsedSummaryItem] {
        [
            CollapsedSummaryItem(
                id: "\(id).summary.status",
                moduleID: id,
                title: "Status",
                text: compactStatusText,
                isEnabledByDefault: true
            ),
            CollapsedSummaryItem(
                id: "\(id).summary.cli",
                moduleID: id,
                title: "CLI",
                text: compactCLIText,
                isEnabledByDefault: false
            ),
        ]
    }

    var taskActivityContribution: TaskActivityContribution {
        let activeCount = sessions.filter { $0.isLikelyLive(at: .now) }.count
        return TaskActivityContribution(
            activityScore: isClaudeRunning ? max(0.3, Double(activeCount) * 0.8) : Double(activeCount) * 0.5,
            activeTaskCount: max(activeCount, isClaudeRunning ? 1 : 0),
            inProgressTaskCount: max(activeCount, isClaudeRunning ? 1 : 0),
            busyTaskCount: 0,
            lastEventAt: sessions.compactMap(\.lastEventAt).max() ?? (isClaudeRunning ? lastRefreshedAt : nil),
            supportsIdleSpin: isClaudeRunning || activeCount > 0
        )
    }

    var preferredOpenedContentHeight: CGFloat {
        CodexIslandChromeMetrics.moduleChromeHeight + (sessions.isEmpty ? 250 : 390)
    }

    var statusTitle: String {
        isClaudeRunning
            ? NSLocalizedString("Running", comment: "")
            : NSLocalizedString("Idle", comment: "")
    }

    var statusDetail: String {
        isClaudeRunning
            ? NSLocalizedString("A Claude Code process is currently active.", comment: "")
            : NSLocalizedString("Claude Code is not running right now.", comment: "")
    }

    var compactStatusText: String {
        isClaudeRunning ? "CLAUDE ON" : "CLAUDE OFF"
    }

    var compactCLIText: String {
        cliStatusText.uppercased()
    }

    var claudeDirectoryPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .path
    }

    var latestConversationMessages: [ClaudeCodeConversationMessage] {
        guard let sessionID = sessions.first?.id else {
            return []
        }

        return conversationsBySessionID[sessionID] ?? []
    }

    func preferredOpenedContentHeight(for presentation: IslandModulePresentationContext) -> CGFloat {
        switch presentation {
        case .standard, .activity:
            return preferredOpenedContentHeight
        case .peek:
            return CodexIslandPeekMetrics.contentTopPadding + 120 + CodexIslandPeekMetrics.contentBottomPadding
        }
    }

    func makeContentView(presentation: IslandModulePresentationContext) -> AnyView {
        AnyView(ClaudeCodeModuleContentView(model: self, presentation: presentation))
    }

    func refreshModuleStatus() {
        let isProcessRunning = Self.isClaudeProcessRunning()
        isClaudeRunning = isProcessRunning
        cliStatusText = Self.resolveCLIStatusText()
        refreshSessions(isProcessRunning: isProcessRunning)
        lastRefreshedAt = .now
    }

    func openClaudeDirectory() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    func jumpToSession(_ sessionID: String) {
        guard let session = sessions.first(where: { $0.id == sessionID }),
              let jumpTarget = session.jumpTarget,
              jumpTarget.canActivate else {
            return
        }

        try? terminalJumpService.jump(to: jumpTarget)
    }

    private func startPollingTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshModuleStatus()
            }
        }
    }

    private func refreshSessions(isProcessRunning: Bool) {
        let discovered = sessionDiscovery.discoverRecentSessions()
        sessions = discovered.map { snapshot in
            guard !isProcessRunning,
                  snapshot.session.phase == .running || snapshot.session.phase == .busy else {
                return snapshot.session
            }

            var session = snapshot.session
            session.phase = .completed
            session.currentTool = nil
            session.isSessionEnded = true
            return session
        }
        conversationsBySessionID = discovered.reduce(into: [:]) { partialResult, snapshot in
            partialResult[snapshot.session.id] = snapshot.messages
        }
    }

    private static func isClaudeProcessRunning() -> Bool {
        guard let output = runProcess(executablePath: "/bin/ps", arguments: ["-axo", "comm"]) else {
            return false
        }

        return output
            .split(separator: "\n")
            .contains { line in
                let executableName = URL(fileURLWithPath: String(line)).lastPathComponent.lowercased()
                return executableName == "claude"
            }
    }

    private static func resolveCLIStatusText() -> String {
        if resolvedClaudeExecutablePath() != nil {
            return "Installed"
        }

        return "Not found"
    }

    private static func resolvedClaudeExecutablePath() -> String? {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let candidateURLs = [
            homeDirectory.appendingPathComponent(".npm-global/bin/claude"),
            homeDirectory.appendingPathComponent(".local/bin/claude"),
            homeDirectory.appendingPathComponent(".bun/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
            URL(fileURLWithPath: "/usr/bin/claude"),
        ]

        if let candidate = candidateURLs.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return candidate.path
        }

        if let shellResolvedPath = runProcess(executablePath: "/bin/zsh", arguments: ["-lc", "command -v claude"]),
           !shellResolvedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return shellResolvedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private static func runProcess(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
