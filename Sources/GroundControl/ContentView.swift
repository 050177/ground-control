import GCCore
import SwiftUI

/// Root layout: ops toolbar on top, terminal grid filling the window.
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showRecents = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                toolbar
                HStack(spacing: 0) {
                    TerminalGridView()
                    if appState.previewVisible {
                        PreviewPanelView()
                            .frame(width: 440)
                            .transition(.move(edge: .trailing))
                    }
                }
                .animation(.spring(duration: 0.25), value: appState.previewVisible)
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
            if !appState.recentProjects.projects.isEmpty {
                Button(action: { showRecents.toggle() }) {
                    Text("RECENTS")
                        .font(Theme.mono(10, weight: .bold))
                        .foregroundStyle(showRecents ? Theme.landed : Theme.dim)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Theme.hairline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showRecents, arrowEdge: .bottom) {
                    RecentsPopover(onOpen: { project in
                        showRecents = false
                        appState.openRecent(project)
                    })
                    .environmentObject(appState)
                }
            }
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
            Button(action: { appState.togglePreview() }) {
                Text("PREVIEW")
                    .font(Theme.mono(10, weight: .bold))
                    .foregroundStyle(appState.previewVisible ? Theme.landed : Theme.dim)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Theme.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("p", modifiers: [.command, .shift])
            if let update = appState.pendingUpdate {
                Button(action: { NSWorkspace.shared.open(update.url) }) {
                    Text("UPDATE")
                        .font(Theme.mono(9, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.radar)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
                .help("Update available: \(update.version) — click to download")
            }
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

// MARK: - Recents popover

private struct RecentsPopover: View {
    @EnvironmentObject var appState: AppState
    let onOpen: (RecentProject) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECENT PROJECTS")
                .font(Theme.mono(9, weight: .bold))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider().background(Theme.hairline)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(appState.recentProjects.projects) { project in
                        Button(action: { onOpen(project) }) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Theme.landed)
                                    Text(project.abbreviatedPath)
                                        .font(Theme.mono(9))
                                        .foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                if project.lastSessionId != nil {
                                    Text("resume")
                                        .font(Theme.mono(9, weight: .bold))
                                        .foregroundStyle(Theme.radar)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().background(Theme.hairline)
                    }
                }
            }
            .frame(maxHeight: 320)

            Button(action: {
                appState.addTerminalPrompt()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    Text("Browse…")
                        .font(Theme.mono(10))
                }
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 280)
        .background(Theme.panel)
    }
}
