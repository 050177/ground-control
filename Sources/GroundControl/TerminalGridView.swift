import GCCore
import SwiftUI

/// Adaptive grid: 1 pane full-width, otherwise 2 columns, rows as needed.
struct TerminalGridView: View {
    @EnvironmentObject var appState: AppState

    private var columns: Int { appState.panes.count <= 1 ? 1 : 2 }
    private var rows: Int { Int(ceil(Double(max(appState.panes.count, 1)) / Double(columns))) }

    var body: some View {
        if appState.panes.isEmpty {
            DashboardView()
        } else {
            VStack(spacing: 1) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 1) {
                        ForEach(paneIndices(inRow: row), id: \.self) { index in
                            let pane = appState.panes[index]
                            TerminalPaneView(
                                pane: pane,
                                isSelected: appState.selectedPaneId == pane.id,
                                onSelect: { appState.selectedPaneId = pane.id },
                                onClose: { appState.removeTerminal(pane.id) }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .background(Theme.hairline)
        }
    }

    private func paneIndices(inRow row: Int) -> Range<Int> {
        let start = row * columns
        let end = min(start + columns, appState.panes.count)
        return start..<max(start, end)
    }
}

// MARK: - Dashboard (shown when no terminals are open)

struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    private var recents: [RecentProject] {
        appState.recentProjects.projects
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Theme.hairline)
            newProjectButton
            Divider().background(Theme.hairline)
            if recents.isEmpty {
                noRecents
            } else {
                recentsList
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.panel)
    }

    private var header: some View {
        HStack {
            Text("Ground Control")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.landed)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    private var newProjectButton: some View {
        Button(action: { appState.addTerminalPrompt() }) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("New terminal")
                    .font(Theme.mono(11, weight: .bold))
                Spacer()
                Text("⌘N")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.dim)
            }
            .foregroundStyle(Theme.radar)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
    }

    private var noRecents: some View {
        Text("No recent projects yet.")
            .font(Theme.mono(11))
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 14)
            .padding(.top, 16)
    }

    private var recentsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECENTS")
                .font(Theme.mono(9, weight: .bold))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ForEach(recents) { project in
                RecentRow(project: project) {
                    appState.openRecent(project)
                }
            }
        }
    }
}

// MARK: - Recent project row

private struct RecentRow: View {
    let project: RecentProject
    let onOpen: () -> Void
    @State private var hovering = false

    private var canResume: Bool { project.lastSessionId != nil }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.landed)
                    Text(project.abbreviatedPath)
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if canResume {
                    Text("resume")
                        .font(Theme.mono(9, weight: .bold))
                        .foregroundStyle(Theme.radar)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Theme.radar.opacity(0.4), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(hovering ? Theme.bg.opacity(0.6) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// Expose Theme.muted2 to this file
extension Theme {
    static let muted2 = Color(red: 0x3A / 255, green: 0x45 / 255, blue: 0x50 / 255)
}
