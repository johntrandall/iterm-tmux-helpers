# iterm-tmux-helpers

Small helper scripts for iTerm2 + tmux integration in `-CC` control mode on macOS. Solves common pain points: attaching every detached session as its own window, tidying iTerm grouping after drag-shuffles, and a fzf-driven session/window picker.

> **Verified against iTerm2 3.6.x and tmux 3.6a.** Every claim in [BEHAVIOR.md](BEHAVIOR.md) was tested in isolation. The scripts emit a one-line stderr warning when run against any other tmux/iTerm major.minor (silenceable with `ITMUX_SUPPRESS_VERSION_WARN=1`).

## What it does

| Script | Purpose |
|---|---|
| `itmux-chooser` | fzf session/window picker. Wire it as your iTerm profile command and it becomes the entry-point UI for ad-hoc attach. Prevents duplicate gateways. |
| `itmux-attach-all` | Attach every detached tmux session as its own iTerm window. Skips already-attached sessions. Spills sessions with > 5 windows into multiple iTerm windows. |
| `itmux-tidy-from-tmux` | Regroup iTerm tabs so each tmux session lives in its own iTerm window. Use after drag-shuffling. Dry-run by default; `--apply` to act. |
| `itmux-tidy-from-iterm` | Inverse: read your current iTerm grouping and push it down to tmux as `move-window` operations. "I dragged tabs across iTerm windows on purpose; make tmux match." |

All scripts read iTerm via the iTerm2 Python API (no AppleScript writes) and tmux via the `tmux` CLI. The [behavioral matrix](BEHAVIOR.md) documents which of the iTerm/tmux interactions actually work the way you'd expect — there are several common gotchas.

## Why

iTerm2's `-CC` control mode binds tmux's session/window/pane model to iTerm's window/tab/split-pane model — but the binding has rough edges:

- Multiple `-CC` clients on the same session create **duplicate gateways** (every window appears twice). The chooser detects existing attaches via the iTerm window-title prefix `↣ <session>:` and refocuses instead of duplicating.
- Drag-rearranging iTerm tabs across windows can scramble the per-session grouping. The two `tidy-from-*` scripts let you reconcile in either direction.
- Attaching N detached sessions cleanly means N invocations of `tmux -CC attach` in N fresh iTerm windows. The `attach-all` script automates that.

<a id="whats-a-gateway-tab"></a>
### What's a "gateway tab"?

In iTerm `-CC` mode, the **gateway tab** is the iTerm tab running `tmux -CC attach`. It's the SSH/local pipe — every other tab you see for that session is a render target driven by the gateway. **Closing the gateway tears down all the windows/tabs that connection rendered.** That's why the recommended setting `AutoHideTmuxClientSession = 1` exists below — it buries the gateway tab so you can't accidentally close it.

One gateway = one tmux client = one attached session. To work with N sessions concurrently, you run N `-CC attach` invocations (and `itmux-attach-all` automates that). For the full conceptual model — sessions ↔ iTerm windows, windows ↔ iTerm tabs, panes ↔ iTerm splits, gateway as the SSH/local pipe — see [BEHAVIOR.md § `-CC` control mode mechanics](BEHAVIOR.md#-cc-control-mode-mechanics).

## Install

### Homebrew (recommended)

```bash
brew tap johntrandall/tap
brew install iterm-tmux-helpers
```

This bundles the `iterm2` Python package and its dependencies into a private venv — you do **not** need to install `iterm2` into your system Python. `tmux` and `fzf` are pulled in as Homebrew dependencies.

The binaries land at `$(brew --prefix)/bin/itmux-*` (typically `/opt/homebrew/bin/` on Apple Silicon).

### Manual

Install the dependencies first:

```bash
brew install tmux fzf
python3 -m pip install --user iterm2     # or: pipx install iterm2
```

Then clone and run the installer:

```bash
git clone https://github.com/johntrandall/iterm-tmux-helpers.git
cd iterm-tmux-helpers
./install.sh
```

The installer symlinks `bin/itmux-*` into `~/.local/bin/` (make sure that's on your `PATH`) and prints any missing dependencies it detects.

The scripts use `#!/usr/bin/env python3`, so whatever `python3` is first on your `PATH` is what they'll use. If `import iterm2` fails at runtime, install the `iterm2` package into that specific interpreter.

### Dependencies — summary

Required for **both** install paths:

- macOS (uses iTerm2's macOS-specific Python API)
- iTerm2 with the **Python API enabled** (Settings → General → Magic → Enable Python API)

| Dependency | Homebrew install | Manual install |
|---|---|---|
| `tmux` 3.x | auto-installed | `brew install tmux` |
| `fzf` | auto-installed | `brew install fzf` |
| `python@3.13` | auto-installed (private venv) | system `python3` 3.10+ |
| `iterm2` Python pkg | bundled in private venv | `python3 -m pip install --user iterm2` |

## Configure iTerm to launch the chooser

Open iTerm Settings → Profiles → your default profile → General. Set **Command** to:

- **Homebrew install:** `/opt/homebrew/bin/itmux-chooser` (or run `which itmux-chooser` to confirm the path on your system)
- **Manual install:** `~/.local/bin/itmux-chooser`

Now Cmd-N (or any new-window action that uses the default profile) drops into the picker.

For best `-CC` ergonomics, also set these iTerm preferences (these aren't exposed in iTerm's GUI for `-CC` mode — set via `defaults write`):

| Setting (defaults key) | Recommended | What it does |
|---|---|---|
| `AutoHideTmuxClientSession` | `1` (On) | Buries the [gateway tab](#whats-a-gateway-tab) so you can't accidentally close it (and tear down the whole tmux client). The hidden gateway lives under iTerm menu → Window → Select Buried Session. Without this, the gateway shows as a normal tab and one stray Cmd-W kills your `-CC` connection. |
| `OpenTmuxWindowsIn` | `1` (`NEW_TABS`) | Where iTerm renders tmux windows when you attach. Three modes: `0` (`NATIVE_WINDOWS`) = a separate iTerm window per tmux window — fragmented and almost never what you want; `1` (`NEW_TABS`) = tabs in the iTerm window you attached from — the standard "tmux feels native" mode; `2` (`NEW_WINDOWS_WITH_TABS`) = a brand-new iTerm window containing tabs. **Verified empirically 2026-04-30** — earlier iTerm docs had the value mapping inverted. |
| `TmuxDashboardLimit` | `50` | The **tmux Dashboard** is an iTerm panel that lists all tmux sessions/windows in a tree, useful for huge sessions. iTerm auto-pops it on attach if the session has ≥ N windows (default `10`, which is annoyingly aggressive for normal use). Raising to `50` means it effectively never auto-pops; you can still open it manually from the iTerm menu when you actually want it. |

```bash
defaults write com.googlecode.iterm2 AutoHideTmuxClientSession -int 1
defaults write com.googlecode.iterm2 OpenTmuxWindowsIn -int 1
defaults write com.googlecode.iterm2 TmuxDashboardLimit -int 50
```

## Usage

### Daily flow

```bash
itmux-attach-all                  # Set the world to a known state every login
itmux-chooser                     # Open a window, pick a session — used by the iTerm profile command
itmux-tidy-from-tmux              # Dry-run after a messy drag session
itmux-tidy-from-tmux --apply      # Actually rearrange
```

### After deliberately re-grouping in iTerm

```bash
itmux-tidy-from-iterm             # Show what tmux moves would match your iTerm grouping
itmux-tidy-from-iterm --apply     # Execute the tmux move-window operations
```

## Further reading

The full verified behavioral matrix — what propagates between tmux and iTerm, what doesn't, and why — is in **[BEHAVIOR.md](BEHAVIOR.md)** (in this repo). A few highlights:

- **Manual rename pins the name** via an internal tmux flag, NOT by setting `automatic-rename off`. Paste-runnable test in BEHAVIOR.md.
- **`Tab.async_set_title()` for tmux-backed tabs** is a direct passthrough to `tmux rename-window` — NOT a local override. `async_set_title("")` blanks the tmux window name (destructive).
- **Drag a single-pane tab onto another tab's pane body** sends `tmux join-pane` over `-CC` — the mapping survives. Multi-pane source: drop refused.
- **Drag a pane onto the tab strip** sends `tmux break-pane`.

If you're going to maintain or extend these scripts, see [AGENTS.md](AGENTS.md) for the testing rule (run the actual binary against a deliberately broad scenario; do NOT write a scoped helper that mirrors the apply logic — it can mask cascade bugs).

## License

MIT — see [LICENSE](LICENSE).
