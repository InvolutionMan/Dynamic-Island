import AppKit
import SwiftUI

enum IslandShellPreviewMocks {
    static let closedHeader = IslandShellClosedHeaderRenderState(
        fanAnimationState: IslandFanAnimationState(
            anchorDate: .now,
            anchorDegrees: 0,
            rotationPeriod: 1.6,
            isSpinning: false
        ),
        computerFanTelemetry: ComputerFanTelemetry(fanRPM: 2380, averageCPUTemperature: 58),
        compactModules: [
            CompactModuleSummary(
                moduleID: "codex",
                title: "Codex",
                symbolName: "terminal",
                iconAssetName: "codexicon",
                content: .singleLine("5H 84%")
            ),
            CompactModuleSummary(
                moduleID: "claude-code",
                title: "Claude Code",
                symbolName: "curlybraces.square",
                iconAssetName: "claudeIcon",
                content: .singleLine("CLAUDE ON")
            ),
        ]
    )

    static let expandedTabs = IslandShellExpandedNavigationRenderState(
        tabs: [
            IslandShellTabRenderState(id: "codex", title: "Codex", symbolName: "terminal", iconAssetName: "codexicon", isSelected: true, showsPendingBadge: true, action: {}),
            IslandShellTabRenderState(id: "claude-code", title: "Claude Code", symbolName: "curlybraces.square", iconAssetName: "claudeIcon", isSelected: false, showsPendingBadge: false, action: {}),
            IslandShellTabRenderState(id: "player", title: "Player", symbolName: "play.square.fill", iconAssetName: nil, isSelected: false, showsPendingBadge: false, action: {}),
        ],
        openSettings: {}
    )

    static let playerOnlyTabs = IslandShellExpandedNavigationRenderState(
        tabs: [
            IslandShellTabRenderState(id: "player", title: "Player", symbolName: "play.square.fill", iconAssetName: nil, isSelected: true, showsPendingBadge: false, action: {}),
        ],
        openSettings: {}
    )

    static let windDrivePanel = IslandWindDrivePanelRenderState(
        animationState: IslandFanAnimationState(
            anchorDate: .now,
            anchorDegrees: 0,
            rotationPeriod: 1.2,
            isSpinning: true
        ),
        logoPreset: .defaultMark,
        customImage: nil
    )
}
