import GCCore
import SwiftUI

/// The departures board: flights as rows, split-flap status changes,
/// click a row to jump to its terminal.
struct DeparturesView: View {
    @EnvironmentObject var appState: AppState

    /// In-flight work on top, then queued, then landed/cancelled.
    private var sortedFlights: [Flight] {
        let rank: [FlightStatus: Int] = [
            .holding: 0, .departed: 1, .boarding: 2,
            .scheduled: 3, .landed: 4, .cancelled: 5,
        ]
        return appState.board.flights.sorted {
            (rank[$0.status] ?? 9, -$0.number) < (rank[$1.status] ?? 9, -$1.number)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            columnHeader
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedFlights) { flight in
                        FlightRow(
                            flight: flight,
                            onFocus: { appState.focusOrReopenFlight(flight) },
                            onRemove: { appState.removeFlight(id: flight.id) }
                        )
                    }
                    if appState.board.flights.isEmpty {
                        Text("NO FLIGHTS — start working in a terminal and tasks appear here automatically")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                }
            }
        }
        .frame(height: 230)
        .background(Theme.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Departures")
                .font(Theme.header(10))
                .foregroundStyle(Theme.landed)
            Text("\(appState.board.flights.filter { $0.status != .landed && $0.status != .cancelled }.count) ACTIVE")
                .font(Theme.mono(9))
                .foregroundStyle(Theme.radar)
            Spacer()
            Text("○ SCHEDULED  ◔ BOARDING  ▶ DEPARTED  ! HOLDING  ■ LANDED")
                .font(Theme.mono(8))
                .foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("FLIGHT").frame(width: 60, alignment: .leading)
            Text("MISSION").frame(maxWidth: .infinity, alignment: .leading)
            Text("AGENT").frame(width: 50, alignment: .leading)
            Text("STATUS").frame(width: 110, alignment: .leading)
            Spacer().frame(width: 20)
        }
        .font(Theme.mono(8, weight: .bold))
        .foregroundStyle(Theme.dim)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

}

struct FlightRow: View {
    let flight: Flight
    let onFocus: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Text("#\(String(format: "%02d", flight.number))")
                .font(Theme.mono(11, weight: .bold))
                .foregroundStyle(Theme.dim)
                .frame(width: 60, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(flight.title)
                    .font(Theme.mono(11))
                    .foregroundStyle(flight.status == .landed ? Theme.dim : Theme.landed)
                    .strikethrough(flight.status == .cancelled)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if flight.status == .departed, !flight.notes.isEmpty {
                    Text(flight.notes)
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.radar.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(flight.assignedPane ?? "—")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.dim)
                .frame(width: 50, alignment: .leading)
            HStack(spacing: 6) {
                Text(glyph)
                    .foregroundStyle(color)
                SplitFlapText(text: flight.status.label, color: color)
            }
            .frame(width: 110, alignment: .leading)
            // Remove button — only visible on hover
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Remove flight")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(minHeight: 26)
        .background(hovering ? Theme.bg.opacity(0.6) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onFocus)
        .help(flight.notes.isEmpty ? flight.title : flight.notes)
    }

    private var glyph: String {
        switch flight.status {
        case .scheduled: return "○"
        case .boarding: return "◔"
        case .departed: return "▶"
        case .holding: return "!"
        case .landed: return "■"
        case .cancelled: return "✕"
        }
    }

    private var color: Color {
        switch flight.status {
        case .scheduled: return Theme.dim
        case .boarding: return Theme.amber
        case .departed: return Theme.radar
        case .holding: return Theme.amber
        case .landed: return Theme.landed
        case .cancelled: return Theme.red
        }
    }
}

/// Status text that flips like a split-flap display when it changes.
struct SplitFlapText: View {
    let text: String
    let color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Text(text)
                .font(Theme.mono(10, weight: .bold))
                .foregroundStyle(color)
                .id(text)
                .transition(.flip)
        }
        .animation(.spring(duration: 0.35), value: text)
    }
}

private struct FlipModifier: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .opacity(angle == 0 ? 1 : 0)
    }
}

extension AnyTransition {
    static var flip: AnyTransition {
        .modifier(active: FlipModifier(angle: 90), identity: FlipModifier(angle: 0))
    }
}
