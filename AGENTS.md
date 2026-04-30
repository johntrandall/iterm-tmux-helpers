# AGENTS.md — iterm-tmux-helpers

Notes for any agent (Claude Code, Codex, etc.) working in this repo.

## What this is

A small set of Python + bash helpers that sit between iTerm2 (in `-CC` tmux integration mode) and tmux on macOS. Installed as `itmux-*` symlinks in `~/.local/bin/`. The canonical reference for *what* tmux↔iTerm behavior these scripts assume is the `iterm-tmux-integration` skill at `~/.claude/skills/iterm-tmux-integration/` (start with `SKILL.md`).

## Testing rule (mandatory)

**Run the actual `itmux-*` binary against a deliberately broad scenario before declaring a fix verified.** Do *not* test by writing a separate helper script that mirrors the apply-branch logic against a filtered subset of sessions.

This rule exists because of a concrete miss on 2026-04-30. After the initial fresh-window-strategy fix to `itmux-tidy-from-tmux` (commit 269b5f5), a scoped helper that mirrored the apply logic against two test sessions reported "all clean" — and an independent code-reviewer subagent agreed the algorithm handled the failure mode. The production binary, run end-to-end against three test sessions plus a real fourth split session, then surfaced a second bug: `Tab.async_move_to_window()` refused on the trailing session in a multi-session-in-one-window scenario because earlier iterations had emptied the source window down to that session's sole tab. iTerm rejects the move when the source has only one tab. The scoped helper never sequenced multiple unclean sessions through live iTerm state, so the cascade didn't surface. Fix in commit e5924ef adds a mid-loop `is_clean()` re-check.

The general principle (production-path testing, anti-pattern of scoped mirroring) is captured in `~/admin-technical/conventions/agentic-systems-development.md` § "Test via the production path."

## How to set up a test scenario

The scripts mutate live iTerm + tmux state. Use throwaway tmux sessions named `tidy-test-*` to avoid disturbing real work.

Pattern from a known-good test run:

```bash
# 1. Create throwaway sessions exercising the edge cases you care about.
TMX="$(command -v tmux)"  # /opt/homebrew/bin/tmux on John's Mac.
                          # The TMX variable is intentional — `$TMUX` is the
                          # tmux socket path inside an attached session, NOT
                          # the binary, so don't try to use it that way.
                          # `env -u TMUX` strips the socket var so a nested
                          # tmux command isn't confused about its parent.
env -u TMUX $TMX new-session -d -s tidy-test-A -n alpha
env -u TMUX $TMX new-window -t tidy-test-A -n beta
env -u TMUX $TMX new-session -d -s tidy-test-B -n one
env -u TMUX $TMX new-window -t tidy-test-B -n two
env -u TMUX $TMX new-session -d -s tidy-test-C -n solo  # single-tab edge case

# 2. Attach via the real production attach script.
itmux-attach-all

# 3. Use the iTerm Python API to scramble tabs into a deliberate bad state
#    (multiple sessions sharing one mixed iTerm window, sessions split across
#    multiple windows, etc.). Drive the API via:
/Users/johnrandall/.local/pipx/venvs/it2/bin/python  # the iTerm-aware Python

# 4. Run the actual binary, dry-run first, then --apply.
itmux-tidy-from-tmux
itmux-tidy-from-tmux --apply

# 5. Re-run --apply for idempotency.
itmux-tidy-from-tmux --apply  # should report all sessions "already clean"

# 6. Cleanup ordering: tmux kill BEFORE iTerm window close (otherwise the
#    Hide/Detach/Kill dialog blocks).
env -u TMUX $TMX kill-session -t tidy-test-A
env -u TMUX $TMX kill-session -t tidy-test-B
env -u TMUX $TMX kill-session -t tidy-test-C
```

When designing a scenario, exercise *multiple* edge cases simultaneously, not one at a time. The cascade between them is where bugs hide.

## Edge cases worth exercising for `itmux-tidy-from-tmux`

- Multiple sessions sharing one mixed iTerm window (the original bug)
- A session with a single tab caught in a mixed window (`async_move_to_window` will refuse if it ends up as the sole occupant)
- A session split across multiple iTerm windows with no foreign tabs in any of them
- An already-clean session (skip path)
- Idempotency: a second `--apply` should report all sessions clean

## Where things live

- `bin/itmux-*` — the helpers (entry points). Symlinked into `~/.local/bin/`.
- `~/.claude/skills/iterm-tmux-integration/SKILL.md` — the canonical behavior reference for iTerm↔tmux semantics on John's machine.
- `~/.claude/skills/iterm-tmux-integration/FOLLOWUPS.md` — open followups, test logs, resolved bugs with commit refs.
- `~/admin-technical/conventions/agentic-systems-development.md` — the production-path testing principle that grounds the testing rule above.

## Known iTerm Python API quirks

These bit us in this codebase. Don't relearn them the hard way:

- `Tab.async_move_to_window()` refuses ("Window has only one tab") if the source iTerm window has only the tab being moved. The move is rejected because moving would leave the source empty.
- `Tab.async_set_title('X')` for a tmux-backed tab is a direct passthrough to `tmux rename-window` — *not* a local override. `async_set_title('')` blanks the tmux `window_name` (destructive).
- `Session.async_set_name()` for a tmux-backed tab is a silent no-op.
- AppleScript `set name of session` for a tmux tab is auto-overridden within milliseconds by iTerm's dynamic naming.

See the SKILL.md "Rename-In-tmux Rule" table for the fully-tested matrix.
