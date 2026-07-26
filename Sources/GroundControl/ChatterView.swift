import SwiftUI

/// Radio-chatter ticker: the latest hook event rendered as an ATC message.
struct ChatterView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            Text("CHATTER")
                .font(Theme.mono(9, weight: .bold))
                .foregroundStyle(Theme.dim)
            Text(appState.chatter.last?.text ?? "frequency clear")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.landed.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.tail)
                .id(appState.chatter.last?.id) // re-render on new line
            Spacer()
            Text("\(appState.chatter.count)")
                .font(Theme.mono(9))
                .foregroundStyle(Theme.dim.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .frame(height: 22)
        .background(Theme.bg)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}
