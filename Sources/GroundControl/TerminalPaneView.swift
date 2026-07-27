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
    let onSplit: () -> Void
    let onClose: () -> Void

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
            Button(action: onSplit) {
                Image(systemName: "rectangle.split.2x1")
            }
            .buttonStyle(TitleBarButtonStyle())
            .help("Split — open another agent in this folder")
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

struct TitleBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Theme.landed : Theme.dim)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
    }
}
