# Tide

Native macOS terminal designed around projects, not just sessions.

Built with SwiftUI + SwiftTerm. No Electron. No webview. Lightweight bundle.

## What it is

iTerm2-style terminal with a real project sidebar. Each project has its own startup setup (multi-pane layout + per-pane commands). Click a project, hit Start, your dev environment spins up the way you defined it.

## Features

- **Project sidebar** — add/edit/remove projects, drag to reorder, color tag each, JSON-persisted in `~/Library/Application Support/Tide/projects.json`
- **Start screen** — every project opens to a Start screen with a Configure button. Forces explicit launch — won't fire commands by mistake
- **Per-project startup configs** — define a layout (single, 2×2 grid, big-top+3-bottom, left+stack, rows) and a command per pane. Exportable + importable as JSON
- **End button** — kills all running processes via SIGINT → SIGTERM → SIGKILL escalation on the shell's process group. Returns to Start screen
- **Tabs per project** — `Cmd+T` new tab, click `×` to close, compact iTerm2-style chrome with bottom accent line
- **Splits** — `Cmd+D` split right, `Cmd+Shift+D` split down. Drag dividers to resize. Each column in 2×2 has independent row dividers
- **Hidden panes tab** — hide a pane to keep its process running off-screen. A "Hidden" tab appears with a badge count; click it for a live 2×2/3×3 grid of all hidden panes. Restore or kill from there
- **Zoom** — double-click pane title bar to fullscreen that pane; double-click again to unzoom
- **Find in scrollback** — `Cmd+F` opens SwiftTerm's built-in find bar on the active pane
- **Per-pane titles** — auto-pulled from terminal escape sequences (zsh/vim/ssh set these)
- **Snippets bar** — persistent input row at the bottom. Type a command, Enter to send to active pane. Save snippets per-project or globally. `Cmd+L` to focus
- **Terminal theme** — Tokyo Night palette (`#1A1B26` bg / `#C0CAF5` fg, full 16-ANSI set)
- **Native window chrome** — NavigationSplitView, draggable splits, traffic lights, sidebar toolbar

## Install

Requires macOS 14+ and Xcode 16+ (Swift 6).

```bash
git clone <repo> tide
cd tide
./build.sh
open Tide.app
```

First launch may need to right-click → Open (Gatekeeper) since binary is ad-hoc signed.

## Build

```bash
./build.sh
```

Produces `Tide.app` in the repo root. Regenerates the icon (`Tide.icns`) from `assets/icon.svg` if newer than the existing icns. Embeds a minimal `Info.plist` and `AppIcon.icns`.

For release build:

```bash
CONFIG=release ./build.sh
```

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| New tab | `Cmd+T` |
| Split right | `Cmd+D` |
| Split down | `Cmd+Shift+D` |
| Close pane / tab | `Cmd+W` |
| Find in pane | `Cmd+F` |
| Focus snippets bar | `Cmd+L` |
| Start (on Start screen) | `Return` |
| Zoom pane | Double-click pane title bar |

## File layout

| Path | Purpose |
|---|---|
| `Sources/Tide/TideApp.swift` | `@main` entrypoint, scene + command menus |
| `Sources/Tide/Models/Project.swift` | `Project` model |
| `Sources/Tide/Models/ProjectStore.swift` | Project persistence + drag-sort |
| `Sources/Tide/Models/ProjectSession.swift` | Per-project runtime: tabs, splits, hidden panes, kill orchestration |
| `Sources/Tide/Models/StartupConfig.swift` | Startup config schema (layout + panes) |
| `Sources/Tide/Models/StartupStore.swift` | Per-project startup config persistence |
| `Sources/Tide/Models/Snippet.swift` / `SnippetStore.swift` | Snippet model + storage |
| `Sources/Tide/Models/TerminalTheme.swift` | Tokyo Night palette applied to each `LocalProcessTerminalView` |
| `Sources/Tide/Models/TerminalKill.swift` | PID-based graceful kill (SIGINT → SIGTERM → SIGKILL of process group) |
| `Sources/Tide/Views/` | All SwiftUI views |

## Storage

| File | What |
|---|---|
| `~/Library/Application Support/Tide/projects.json` | Project list (name, path, color) |
| `~/Library/Application Support/Tide/startups.json` | Per-project startup configs |
| `~/Library/Application Support/Tide/snippets.json` | Saved snippets |

All JSON, hand-editable, exportable.

## Architecture notes

- **Why SwiftTerm**: handles PTY spawn + xterm escape sequence rendering. ~5MB added to the binary
- **NSView reuse**: each pane's `LocalProcessTerminalView` is cached in `TabSession.terminals` (or `ProjectSession.hiddenTerminals` when hidden). Reparented across SwiftUI redraws so the underlying process is never re-spawned
- **Kill strategy**: `kill(-pid, SIGINT)` to send Ctrl-C to the entire process group. After 400ms, escalate to SIGTERM, then SIGKILL. The shell is forked as a session leader so its PID == PGID — children of background daemons (rails, npm, etc.) get the signal too
- **Split model**: recursive `SplitNode.Content = .leaf(sessionID) | .split(axis, children)`. Splits are mutated in-place; SwiftUI re-renders via `@Observable`. `HSplitView` / `VSplitView` from SwiftUI give native draggable dividers
- **Why 2×2 is "columns of rows"**: nested splits have a single divider per level. Modeling 2×2 as `outer = vertical (left|right) → each column = horizontal (top/bottom)` means each column has its own independent row divider, instead of one row-divider that resizes all four cells at once

## Status

Working MVP. Things still rough or missing:

- No workspace persistence across app launches (quit Tide → restart → back to Start screen)
- No global hotkey window
- Shell integration (cwd tracking, mark prompts) — not yet
- Background process status indicators (running/stopped per pane) — not yet
- Triggers / smart selection / semantic history — not yet
- Notifications — not yet
- Profiles beyond startup configs — not yet
- App Store / notarization — not packaged

## License

Personal project. Use at your own risk.
