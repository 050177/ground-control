# Ground Control

*Your agents are cleared for takeoff.* &nbsp;[Discord](https://discord.gg/RygfdCZEm)

A native macOS app that runs multiple [Claude Code](https://claude.ai/code) sessions
in parallel, watches each one on a live status radar, and auto-tracks what every agent
is working on in a shared departures board.

Built in Swift + SwiftUI + [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).
No Electron. No accounts. No telemetry. ~8 MB.

```
┌─────────────────────────────────────────────────────────────┐
│ ● LIVE  Ground Control                  1 TERMINAL  [+NEW]  │
├─────────────────────────────────────────────────────────────┤
│ ● T1  DEPARTED                          ~/Documents/myapp ↺ ×│
│                                                             │
│  ▶ Refactoring auth middleware                              │
│    Read  src/auth/middleware.ts                             │
│    Edit  src/auth/middleware.ts                             │
│    Bash  npm test                         ▌                 │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ Departures  3 ACTIVE                                        │
│ FLIGHT  MISSION                       AGENT   STATUS        │
│  #03    Refactor auth middleware       T1      ▶ DEPARTED   │
│  #01    Add rate limiting to API       T1      ■ LANDED     │
│  #02    Fix signup validation          —       ○ SCHEDULED  │
├─────────────────────────────────────────────────────────────┤
│ CHATTER  T1 · #03 DEPARTED — Refactor auth middleware       │
└─────────────────────────────────────────────────────────────┘
```

## How to use it

1. `Scripts/build-app.sh && open "build/Ground Control.app"`
2. **⌘N** — pick a project folder. Claude Code starts in that directory.
3. Type your prompt as normal. The beacon in the title bar turns green (working),
   amber (needs input), dims when done. The departures board logs it automatically.
4. **⌘N again** for another project. Both sessions run in parallel.
5. macOS notification fires when an agent finishes or goes HOLDING.

That's it. It's Claude Code with a window that shows all your sessions at once and
tells you what each one is doing.

## Features

**Terminal grid**
⌘N opens a claude session in any project directory. Panes tile in a 1- or 2-column
grid. Restart or close from the title bar. The last directory you opened is remembered.

**Session resume**
Every project path stores its last session ID. Reopen a folder from the recents list
and Ground Control passes `--resume` to claude automatically — the conversation picks
up exactly where it left off. Manual restart always starts fresh.

**Recent projects**
The dashboard (shown when no terminals are open) lists recently opened projects with
a `resume` badge when a session can be continued. Click to open.

**Status radar**
Claude's hook system fires on every lifecycle event. Ground Control listens on a
token-authenticated loopback HTTP server and drives each pane's beacon in real time.

| State | Meaning |
|---|---|
| `DEPARTED` ▶ green | Agent is actively working |
| `HOLDING` ! amber | Waiting on your input or a permission |
| `STANDBY` · | Idle at the prompt |
| `LANDED` ■ | Finished its turn |
| `DARK` · | Session ended normally |
| `NO CONTACT` ✕ red | Process exited unexpectedly |

**Departures board**
A flight-strip task board — not kanban columns. Every prompt you type is automatically
filed as a flight and set to DEPARTED. When the agent finishes, it flips to LANDED.

Agents can also self-manage the board using MCP tools injected into every session:

| Tool | What it does |
|---|---|
| `departures_file` | Create a task with title + notes |
| `departures_claim` | Assign a flight to this terminal |
| `departures_update` | Change status, title, or notes |
| `departures_list` | Read the full board |
| `departures_get` | Look up a single flight by number |

Tell Claude *"break this into tasks on the board and work through them"* — it'll file
flights, claim them, and mark them done on its own.

Board persists to `~/Library/Application Support/GroundControl/board.json`. Nothing
is written to your project directories.

**Git in the title bar**
Current branch + dirty file count per pane, refreshed every 5 seconds.

## Build & run

Requires macOS 14+, Swift command line tools, and the `claude` CLI.

```sh
# debug build + launch
Scripts/run.sh

# release build → build/Ground Control.app
Scripts/build-app.sh
open "build/Ground Control.app"
```

No Xcode project — plain SwiftPM package bundled by script, ad-hoc signed.

## Keyboard shortcuts

| Key | Action |
|---|---|
| ⌘N | New terminal — opens a directory picker |
| ⌘B | Toggle departures board |
| ⌘Q | Quit (terminates all sessions) |

## How it works under the hood

```
┌──────────── Ground Control.app ─────────────────────┐
│  SwiftUI grid  ◄── HookServer (127.0.0.1:port)       │ ◄── POST /hook      (claude http hooks)
│  DeparturesView ◄── BoardStore (board.json)          │ ◄── /api/flights    (gc-mcp → HTTP)
└───────┬──────────────────────────────────────────────┘
        │ spawns with --session-id --settings --mcp-config --resume
   ┌────┴──────┐                        ┌───────────┐
   │  claude   │ ── MCP stdio ────────► │  gc-mcp   │
   └───────────┘                        └───────────┘
```

Each pane forces a `--session-id` UUID (hooks map 1:1 to panes), writes a temp
settings file wiring http hooks to the app's loopback server, and an MCP config
pointing at the bundled `gc-mcp` binary. Session config lives in `$TMPDIR` and is
cleaned up on quit. Nothing touches your project.

## Roadmap

| Version | Status | What's in it |
|---|---|---|
| v0.1 | ✓ shipped | Single terminal, hooks, departures board + MCP |
| v0.2 | ✓ shipped | Resume, recent projects, auto-filed departures |
| v0.3 | in progress | Split pane, restore sessions on launch, history search, export |
| v0.4 | planned | Real-time diffs, screenshot diff, token cost tracker |
| v0.5 | planned | Codex/Gemini/aider support, turbo mode, prompt templates |
| v0.6 | planned | MCP marketplace, webhook triggers, shared pane context |
| v0.7 | planned | Autonomous dispatcher — agents spawn and coordinate agents |

## License

MIT — built by [050177](https://050177.com)
