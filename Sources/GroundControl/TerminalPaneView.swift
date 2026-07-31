import GCCore
import SwiftTerm
import SwiftUI

/// Thin representable — PaneModel owns the view and process lifecycle.
struct TerminalRepresentable: NSViewRepresentable {
    let pane: PaneModel

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        pane.ensureStarted()
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}

/// One pane: instrument-panel title bar + terminal, focus ring when selected.
struct TerminalPaneView: View {
    @ObservedObject var pane: PaneModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onSplit: (String) -> Void
    let onClose: () -> Void
    @State private var showSplitInput = false
    @State private var splitTask = ""

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            TerminalRepresentable(pane: pane)
        }
        .background(Theme.panel)
        .overlay(
            Rectangle()
                .strokeBorder(isSelected ? Theme.radar.opacity(0.55) : Color.clear, lineWidth: 1)
        )
        .simultaneousGesture(TapGesture().onEnded { onSelect() })
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            BeaconView(state: pane.state)
            Text(pane.label)
                .font(Theme.mono(11, weight: .bold))
                .foregroundStyle(Theme.landed)
            Text(pane.state.label)
                .font(Theme.mono(10, weight: .medium))
                .foregroundStyle(color(for: pane.state))
            Spacer()
            if let branch = pane.branch {
                Text("⎇ \(branch)")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.dim)
            }
            Text(abbreviated(pane.cwd))
                .font(Theme.mono(10))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .truncationMode(.head)
            Button(action: { showSplitInput.toggle() }) {
                Image(systemName: "rectangle.split.2x1")
                    .foregroundStyle(showSplitInput ? Theme.radar : Theme.dim)
            }
            .buttonStyle(TitleBarButtonStyle())
            .help("Deploy sub-agent in this folder")
            .popover(isPresented: $showSplitInput, arrowEdge: .bottom) {
                SplitTaskPopover(task: $splitTask) {
                    let t = splitTask
                    splitTask = ""
                    showSplitInput = false
                    onSplit(t)
                }
            }
            Button(action: { pane.restart() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(TitleBarButtonStyle())
            .help("Restart session")
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(TitleBarButtonStyle())
            .help("Close terminal")
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Theme.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    private func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func color(for state: PaneState) -> SwiftUI.Color {
        switch state {
        case .standby: return Theme.dim
        case .departed: return Theme.radar
        case .holding: return Theme.amber
        case .landed: return Theme.landed
        case .dark: return Theme.dim
        case .noContact: return Theme.red
        }
    }
}

/// Status beacon; pulses while the agent is working.
struct BeaconView: View {
    let state: PaneState
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .opacity(state == .departed ? (pulse ? 0.3 : 1) : 1)
            .animation(
                state == .departed
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: pulse
            )
            .onAppear { pulse = true }
    }

    private var color: SwiftUI.Color {
        switch state {
        case .standby: return Theme.dim
        case .departed: return Theme.radar
        case .holding: return Theme.amber
        case .landed: return Theme.landed
        case .dark: return Theme.dim.opacity(0.5)
        case .noContact: return Theme.red
        }
    }
}

// MARK: - Sub-agent deploy popover

private struct SplitTaskPopover: View {
    @Binding var task: String
    let onDeploy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DEPLOY SUB-AGENT")
                .font(Theme.mono(9, weight: .bold))
                .foregroundStyle(Theme.dim)

            TextField("What should this agent work on?", text: $task)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.landed)
                .textFieldStyle(.plain)
                .frame(width: 280)
                .onSubmit { if !task.isEmpty { onDeploy() } }

            HStack {
                Spacer()
                Button("Deploy") { onDeploy() }
                    .buttonStyle(.plain)
                    .font(Theme.mono(10, weight: .bold))
                    .foregroundStyle(task.isEmpty ? Theme.dim : Theme.radar)
                    .disabled(task.isEmpty)
            }
        }
        .padding(14)
        .background(Theme.panel)
    }
}

struct TitleBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Theme.landed : Theme.dim)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
    }
}
