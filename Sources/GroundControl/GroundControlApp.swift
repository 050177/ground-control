import AppKit
import SwiftUI

@main
struct GroundControlApp: App {
    @StateObject private var appState = AppState()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Terminal…") {
                    appState.addTerminalPrompt()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Departures") {
                    appState.toggleBoard()
                }
                .keyboardShortcut("b", modifiers: .command)
            }
            CommandGroup(replacing: .appTermination) {
                Button("Quit Ground Control") {
                    appState.shutdown()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}
