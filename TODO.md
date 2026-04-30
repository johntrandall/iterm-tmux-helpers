# TODO — iterm-tmux-helpers

For future agent sessions in this repo. Items here have full context so they can be picked up cold.

For test methodology, edge cases, and the production-path testing rule, see `AGENTS.md`.

## Empirical investigations (no clear fix yet)

### Hidden tmux windows in iTerm

iTerm's `-CC` integration can mark a tmux window as hidden (Hide/Detach/Kill dialog → Hide). Hidden windows persist server-side but don't render as iTerm tabs. Symptom: `tmux list-windows` shows N windows, iTerm shows < N tabs. They appear in iTerm's tmux dashboard.

**Possible solutions to explore:**
- New script `itmux-unhide-all` that walks the dashboard or sets a tmux user-option.
- Extend `itmux-tidy-from-tmux` to unhide before tidying.
- Investigate iTerm's hide/show API surface — may be tmux user-option (`@hidden`), iTerm `-CC` control sequence, or iTerm Python API.

**Workaround for now:** open the dashboard and right-click → Show.

### Drag tab → tab pane-body propagation matrix

Verified (per SKILL.md structural propagation matrix in `~/.claude/skills/iterm-tmux-integration/SKILL.md`):
- single-pane source dragged onto pane body → `tmux join-pane` (mapping survives)
- multi-pane source dragged onto pane body → refused by iTerm

Open: a deliberate test of all the multi-pane/multi-tab/split-zone-hint variants to confirm the matrix is exhaustive.

### Pane-size / prompt-render desync on freshly-created windows

When a tmux window is created during attach (e.g. by the chooser's old `new-window`-before-attach pattern), the new pane sometimes renders with the wrong column width — visible as zsh prompt text being overwritten by user input. Confirmed 2026-04-30 reboot. Less common after the chooser fix in `afa2d9c`, but the root cause is unresolved. Likely the same family as the inactive-tab-pane-resize-lag below.

### Inactive-tab pane-resize lag

After dragging an iTerm tab between windows, the *non-active* tmux window's pane layout stays at its old dimensions (e.g. `80x25`) even though its containing iTerm window is much larger — leaving large empty bands. Active tab resizes fine. Settings checked: `aggressive-resize off`, `window-size latest`. With `latest`, tmux should re-grow when the client changes size, but iTerm doesn't appear to send a resize for non-visible tabs after a drag.

`tmux refresh-client -S` should force re-sync. John reports manual iTerm window resize does NOT fix the inactive tab — panes stay at the old size. The gap is more stubborn than a missed resize signal.

**Investigate:**
- Is this a known iTerm `-CC` quirk for inactive tabs?
- Should we set `aggressive-resize on` and accept its tradeoffs?
- Is there a tmux hook to call `refresh-client` automatically on tab switch (and would that even help, since iTerm isn't sending the size)?

## New skills (would benefit from this codebase)

### `iterm-python-api` skill

Primer on common iTerm Python API operations John actually uses. Cover: `Window.async_create`, `Window.async_close(force=True)`, `Window.async_set_tabs`, `Tab.async_move_to_window`, `Tab.async_set_title`, `App.async_get_app`, the `iterm2.run_until_complete` entry pattern, and how to write a one-shot script. Lift examples from `bin/itmux-attach-all`, `bin/itmux-tidy-from-tmux`, and `bin/itmux-tidy-from-iterm`.

DO NOT lift from the deleted `itmux-rename-from-*` scripts — they're gone (commit `75ebec5`), and their logic was based on the false premise that tmux-backed tabs have an iTerm-local title override. See `~/.claude/skills/iterm-tmux-integration/SKILL.md` "Rename-In-tmux Rule" for the verified behavior.

### `tmux-pane-operations` skill

When and how to use `join-pane`, `break-pane`, `swap-pane`, `swap-window`, `move-window`, `link-window`. The "I want to reorganize my tmux structure" reference. Should cross-reference the structural propagation matrix in `~/.claude/skills/iterm-tmux-integration/SKILL.md` so users know which UI gestures already map to these commands.

### Hooks to enforce conventions

(Live in `~/.claude/hooks/`, not this repo — but the conventions they'd enforce are documented in this codebase.)

1. **iTerm AppleScript guard** (PreToolUse on Bash): scan for `osascript.*iTerm`, suggest the Python API. Soft-warn on writes; allow read-only.
2. **Cleanup ordering guard** (PreToolUse on Bash): catch `osascript.*close.*iTerm` without prior `tmux kill-session` and warn about the Hide/Detach/Kill dialog gotcha.
3. **`force=True` lint** (PostToolUse on Edit/Write): when a Python file imports `iterm2`, lint that any `async_close()` call has `force=True` (or explicit `force=False` with a comment).
