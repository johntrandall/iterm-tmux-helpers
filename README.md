# iterm-tmux-helpers

Small helper scripts for iTerm2 + tmux integration in `-CC` control mode on macOS. Solves common pain points: attaching every detached session as its own window, tidying iTerm grouping after drag-shuffles, and a fzf-driven session/window picker.

## What it does

| Script | Purpose |
|---|---|
| `itmux-chooser` | fzf session/window picker. Wire it as your iTerm profile command and it becomes the entry-point UI for ad-hoc attach. Prevents duplicate gateways. |
| `itmux-attach-all` | Attach every detached tmux session as its own iTerm window. Skips already-attached sessions. Spills sessions with > 5 windows into multiple iTerm windows. |
| `itmux-tidy-from-tmux` | Regroup iTerm tabs so each tmux session lives in its own iTerm window. Use after drag-shuffling. Dry-run by default; `--apply` to act. |
| `itmux-tidy-from-iterm` | Inverse: read your current iTerm grouping and push it down to tmux as `move-window` operations. "I dragged tabs across iTerm windows on purpose; make tmux match." |

All scripts read iTerm via the iTerm2 Python API (no AppleScript writes — see [SKILL doc](#further-reading)) and tmux via the `tmux` CLI.

## Why

iTerm2's `-CC` control mode binds tmux's session/window/pane model to iTerm's window/tab/split-pane model — but the binding has rough edges:

- Multiple `-CC` clients on the same session create **duplicate gateways** (every window appears twice). The chooser detects existing attaches via the iTerm window-title prefix `↣ <session>:` and refocuses instead of duplicating.
- Drag-rearranging iTerm tabs across windows can scramble the per-session grouping. The two `tidy-from-*` scripts let you reconcile in either direction.
- Attaching N detached sessions cleanly means N invocations of `tmux -CC attach` in N fresh iTerm windows. The `attach-all` script automates that.

## Install

### Homebrew (recommended)

```bash
brew tap johntrandall/tap
brew install iterm-tmux-helpers
```

### Manual

```bash
git clone https://github.com/johntrandall/iterm-tmux-helpers.git
cd iterm-tmux-helpers
./install.sh
```

The installer symlinks `bin/itmux-*` into `~/.local/bin/`. Make sure that's on your `PATH`.

### Dependencies

- macOS (uses iTerm2's macOS-specific Python API)
- iTerm2 with the **Python API enabled** (Settings → General → Magic → Enable Python API)
- `tmux` 3.x (`brew install tmux`)
- `fzf` (`brew install fzf`)
- Python 3.10+ with the `iterm2` package: `python3 -m pip install --user iterm2` *or* a pipx venv (`pipx install iterm2`).

The scripts use `#!/usr/bin/env python3`, so whatever python3 is first on your `PATH` is what they'll use. If `import iterm2` fails, install the package into that interpreter.

## Configure iTerm to launch the chooser

Open iTerm Settings → Profiles → your default profile → General. Set **Command** to:

```
~/.local/bin/itmux-chooser
```

Now Cmd-N (or any new-window action that uses the default profile) drops into the picker.

For best `-CC` ergonomics, also set:

| Setting (defaults key) | Value | Effect |
|---|---|---|
| `AutoHideTmuxClientSession` | `1` | Hides the gateway tab so you can't accidentally close it. |
| `OpenTmuxWindowsIn` | `1` | Open tmux windows as iTerm tabs (NOT separate windows). The value mapping is `0`=separate windows, `1`=tabs, `2`=tabs in new window. |
| `TmuxDashboardLimit` | `50` | Don't auto-pop the dashboard for moderately-sized sessions. |

```bash
defaults write com.googlecode.iterm2 AutoHideTmuxClientSession -int 1
defaults write com.googlecode.iterm2 OpenTmuxWindowsIn -int 1
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

The behavioral matrix that grounds these scripts — what propagates between tmux and iTerm, what doesn't, and why — is captured in the [`iterm-tmux-integration` Claude Code skill](https://github.com/johntrandall/dot-claude/blob/main/skills/iterm-tmux-integration/SKILL.md). Highlights:

- **Manual rename pins the name** via an internal tmux flag (NOT by setting `automatic-rename off`). Verified empirically; paste-runnable test in the skill.
- **`Tab.async_set_title()` for tmux-backed tabs** is a direct passthrough to `tmux rename-window` — NOT a local override. `async_set_title("")` is destructive.
- **Drag a single-pane tab onto another tab's pane body** sends `tmux join-pane` over `-CC`. Multi-pane source: refused.
- **Drag a pane onto the tab strip** sends `tmux break-pane`.

If you're going to maintain or extend these scripts, see [AGENTS.md](AGENTS.md) for the testing rule (run the actual binary against a deliberately broad scenario; do NOT write a scoped helper that mirrors the apply logic — it can mask cascade bugs).

## License

MIT — see [LICENSE](LICENSE).
