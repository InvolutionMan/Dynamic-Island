import SwiftUI

struct ClaudeCodeModuleContentView: View {
    @ObservedObject var model: ClaudeCodeModuleModel
    let presentation: IslandModulePresentationContext

    var body: some View {
        switch presentation {
        case .standard:
            standardContent
        case .activity, .peek:
            statusCard(isCompact: true)
        }
    }

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: CodexExpandedMetrics.contentSpacing) {
            statusCard(isCompact: false)

            if model.sessions.isEmpty {
                detailsCard
            } else {
                sessionListCard
                conversationCard
            }
        }
    }

    private func statusCard(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(model.iconAssetName ?? "claudeIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title)
                        .font(.system(size: CodexExpandedMetrics.titleFontSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(model.statusDetail)
                        .font(.system(size: CodexExpandedMetrics.summaryFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(isCompact ? 1 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(model.statusTitle)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusTint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(statusTint.opacity(0.14), in: Capsule())
            }

            if !isCompact {
                Divider()
                    .overlay(.white.opacity(0.08))

                HStack(spacing: 10) {
                    metricPill(title: "CLI", value: model.cliStatusText)
                    metricPill(title: "Updated", value: model.lastRefreshedAt.formatted(date: .omitted, time: .shortened))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isCompact ? 14 : 16)
        .background(
            RoundedRectangle(cornerRadius: CodexExpandedMetrics.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(CodexExpandedMetrics.cardBackgroundOpacity))
        )
        .overlay {
            RoundedRectangle(cornerRadius: CodexExpandedMetrics.cardCornerRadius, style: .continuous)
                .stroke(statusTint.opacity(model.isClaudeRunning ? 0.28 : 0.12), lineWidth: 1)
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local Configuration")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))

            VStack(alignment: .leading, spacing: 8) {
                detailRow(title: "Command", value: "claude")
                detailRow(title: "Directory", value: model.claudeDirectoryPath)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: CodexExpandedMetrics.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private var sessionListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(model.sessions.prefix(3))) { session in
                CodexIslandSessionRow(
                    session: session,
                    referenceDate: .now,
                    onJump: { model.jumpToSession(session.id) }
                )
            }
        }
    }

    private var conversationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Latest Conversation")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))

            if model.latestConversationMessages.isEmpty {
                Text("Claude Code conversation history will appear here after the CLI writes session records.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.54))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.latestConversationMessages) { message in
                        conversationMessageRow(message)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: CodexExpandedMetrics.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private func conversationMessageRow(_ message: ClaudeCodeConversationMessage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(message.role.rawValue.uppercased())
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(roleTint(for: message.role))

            Text(message.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.38))

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))
                .frame(width: 72, alignment: .leading)

            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var statusTint: Color {
        model.isClaudeRunning
            ? Color(red: 0.31, green: 0.86, blue: 0.48)
            : Color.white.opacity(0.46)
    }

    private func roleTint(for role: ClaudeCodeConversationMessage.Role) -> Color {
        switch role {
        case .user:
            return Color(red: 0.55, green: 0.75, blue: 1.0)
        case .assistant:
            return Color(red: 0.31, green: 0.86, blue: 0.48)
        case .tool:
            return Color.orange.opacity(0.9)
        }
    }
}
