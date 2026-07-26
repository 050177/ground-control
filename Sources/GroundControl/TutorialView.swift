import SwiftUI

private struct Step {
    let title: String
    let body: String
    let detail: String? // smaller code/example block, nil = skip
}

private let steps: [Step] = [
    Step(
        title: "Welcome to Ground Control",
        body: "This is your mission control for Claude Code. Instead of juggling terminals across your screen, you run all your sessions here — side by side, with a live radar showing what each one is doing.\n\nIf you've used Claude Code before, nothing changes about how it works. Ground Control just wraps it and watches it.",
        detail: nil
    ),
    Step(
        title: "Opening a terminal",
        body: "Hit ⌘N (or the + New Terminal button in the top right) and pick a project folder. That's it — Ground Control opens a full Claude Code session in that directory.\n\nEach terminal gets a label: T1, T2, T3 and so on. You can have as many running at once as your machine can handle. They tile automatically into a grid.",
        detail: "⌘N  →  pick a folder  →  Claude Code starts"
    ),
    Step(
        title: "The status beacons",
        body: "See the small dot in each terminal's title bar? That's the radar. It changes color based on what Claude is doing right now — you don't have to watch the terminal output to know if something needs your attention.\n\nGreen means it's working. Amber means it's waiting on you. The chatter bar at the very bottom of the window logs every status change in real time.",
        detail: "● DEPARTED   agent is working\n! HOLDING    needs your input\n■ LANDED     finished its turn\n· DARK       session ended"
    ),
    Step(
        title: "The departures board",
        body: "The board at the bottom of the window is where tasks live. Think of it like a flight information display — each row is a task (called a flight), and the status column tells you where it is in the process.\n\nYou can file a flight yourself by typing in the + bar at the bottom of the board. Or you can tell Claude to do it. Either way it ends up here.",
        detail: "○ SCHEDULED  →  waiting to start\n◔ BOARDING   →  agent just picked it up\n▶ DEPARTED   →  actively being worked\n■ LANDED     →  done"
    ),
    Step(
        title: "Agents can manage the board themselves",
        body: "Every Claude session you open gets five tools automatically injected via MCP:\n\ndepartures_file — create a new task\ndepartures_claim — assign it to this terminal\ndepartures_update — change the status\ndepartures_list — read the whole board\ndepartures_get — look up one task\n\nSo you can literally tell Claude: \"file a flight plan for each sub-task, then work through them in order\" — and watch the board update as it goes.",
        detail: "Try: \"break this into tasks and file each one as a flight\""
    ),
    Step(
        title: "Running multiple agents at once",
        body: "This is the whole point. Open T1 on your API, T2 on your frontend, T3 on your test suite. Give each one a different task. They work in parallel, completely independently — separate sessions, separate context.\n\nWhen T2 hits a permission prompt and needs you, the beacon goes amber and you get a macOS notification. You don't have to keep checking.",
        detail: "T1  ▶ DEPARTED   fixing the auth bug\nT2  ! HOLDING    needs permission to run tests\nT3  ▶ DEPARTED   updating the README"
    ),
    Step(
        title: "A few things worth knowing",
        body: "Ground Control never touches your project files. The config it injects into each Claude session lives in a temp folder and disappears when you quit.\n\nThe board persists between restarts — it's saved to ~/Library/Application Support/GroundControl/board.json.\n\nYou can close a terminal from its × button, restart it with the ↺ button, and toggle the departures board with ⌘B.\n\nThat's everything. Hit the ? button in the toolbar any time to come back here.",
        detail: nil
    ),
]

struct TutorialView: View {
    @EnvironmentObject var appState: AppState
    @State private var index = 0

    private var step: Step { steps[index] }
    private var isFirst: Bool { index == 0 }
    private var isLast:  Bool { index == steps.count - 1 }

    var body: some View {
        ZStack {
            // backdrop
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture { /* eat taps so underlying UI isn't clickable */ }

            VStack(spacing: 0) {
                // header
                HStack {
                    Text("Ground Control")
                        .font(Theme.mono(10, weight: .bold))
                        .foregroundStyle(Theme.radar)
                    Text("/ Tutorial")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.dim)
                    Spacer()
                    // step dots
                    HStack(spacing: 6) {
                        ForEach(0..<steps.count, id: \.self) { i in
                            Circle()
                                .fill(i == index ? Theme.radar : Theme.dim.opacity(0.35))
                                .frame(width: 5, height: 5)
                                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { index = i } }
                        }
                    }
                    Spacer()
                    Button(action: dismiss) {
                        Text("Skip")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.dim)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 12)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 20)

                Divider().background(Theme.hairline)

                // content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(step.title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.landed)

                        Text(step.body)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(red: 0.72, green: 0.78, blue: 0.84))
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)

                        if let detail = step.detail {
                            Text(detail)
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.radar.opacity(0.85))
                                .lineSpacing(6)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.panel)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(Theme.hairline, lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }

                Divider().background(Theme.hairline)

                // nav
                HStack {
                    if !isFirst {
                        Button(action: prev) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.dim)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Text("\(index + 1) of \(steps.count)")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.dim)
                    Spacer()
                    if isLast {
                        Button(action: dismiss) {
                            Text("Done")
                                .font(Theme.mono(11, weight: .bold))
                                .foregroundStyle(Theme.bg)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 7)
                                .background(Theme.radar)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: next) {
                            HStack(spacing: 6) {
                                Text("Next")
                                Image(systemName: "chevron.right")
                            }
                            .font(Theme.mono(11, weight: .bold))
                            .foregroundStyle(Theme.bg)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 7)
                            .background(Theme.radar)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
            }
            .frame(width: 520)
            .background(Color(red: 0.09, green: 0.11, blue: 0.135))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 40, x: 0, y: 16)
        }
        .transition(.opacity)
    }

    private func next() {
        withAnimation(.easeInOut(duration: 0.2)) { index = min(index + 1, steps.count - 1) }
    }
    private func prev() {
        withAnimation(.easeInOut(duration: 0.2)) { index = max(index - 1, 0) }
    }
    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.15)) { appState.tutorialVisible = false }
    }
}
