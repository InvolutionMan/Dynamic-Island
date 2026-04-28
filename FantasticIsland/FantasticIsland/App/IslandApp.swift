import SwiftUI

@main
struct IslandApp: App {
    @StateObject private var model = IslandAppModel()

    var body: some Scene {
        MenuBarExtra {
            Button(model.islandExpanded ? "Hide Island" : "Show Island") {
                model.toggleIslandExpansionFromShortcut()
            }

            Divider()

            Button {
                model.openSettings()
            } label: {
                Text("Settings…")
            }

            Button {
                model.quit()
            } label: {
                Text("Quit")
            }
        } label: {
            Image(systemName: "sparkles")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            IslandSettingsView(model: model)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button {
                    model.openSettings()
                } label: {
                    Text("Settings…")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
