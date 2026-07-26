import SwiftUI

/// Root layout: ops toolbar on top, terminal grid filling the window.
/// (Chatter ticker arrives in Phase 2, departures board in Phase 3.)
struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                toolbar
                TerminalGridView()
                if appState.boardVisible {
                    DeparturesView()
                }
                ChatterView()
            }
            .background(Theme.bg)

            if appState.tutorialVisible {
                TutorialView()
                    .environmentObject(appState)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.radar)
                .frame(width: 7, height: 7)
            Text("LIVE")
                .font(Theme.mono(10, weight: .bold))
                .foregroundStyle(Theme.radar)
            Text("Ground Control")
                .font(Theme.header(12))
                .foregroundStyle(Theme.landed)
            Spacer()
            Text("\(appState.panes.count) TERMINAL\(appState.panes.count == 1 ? "" : "S")")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.dim)
            Button(action: { appState.toggleBoard() }) {
                Text("DEPARTURES")
                    .font(Theme.mono(10, weight: .bold))
                    .foregroundStyle(appState.boardVisible ? Theme.landed : Theme.dim)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Theme.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("b", modifiers: .command)
            Button(action: { appState.showTutorial() }) {
                Text("?")
                    .font(Theme.mono(11, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Show tutorial")
            Button(action: { appState.addTerminalPrompt() }) {
                Label("NEW TERMINAL", systemImage: "plus")
                    .font(Theme.mono(10, weight: .bold))
                    .foregroundStyle(Theme.radar)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Theme.radar.opacity(0.5), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.leading, 76) // clear the traffic lights (hidden title bar)
        .padding(.trailing, 12)
        .frame(height: 38)
        .background(Theme.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}
