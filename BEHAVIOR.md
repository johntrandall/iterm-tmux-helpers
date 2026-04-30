# iTerm2 + tmux `-CC` mode — verified behavioral matrix

How tmux concepts map onto iTerm2 in `-CC` control mode, and the rules that follow from that mapping. This is the documentation that grounds the helper scripts in this repo — the differentiator vs. generic "iTerm + tmux tips" guides is that **every claim below was tested in isolation** (changed one variable, observed the effect) rather than inferred from docs or a sequence of changes.

## Verified against

| Software | Version |
|---|---|
| iTerm2 | **3.6.x** (tested against 3.6.9) |
| tmux | **3.6a** |
| macOS | Apple Silicon, Sequoia / Sonoma class |

Verified 2026-04-30. The helper scripts emit a one-line stderr warning when run against any other tmux or iTerm major.minor (silenceable with `ITMUX_SUPPRESS_VERSION_WARN=1`). Behavior may differ on other versions; if you find drift please open an issue.

## Concept mapping

| tmux | iTerm (in `-CC` mode) | Notes |
|---|---|---|
| Server (one per user, per socket) | (no equivalent) | iTerm doesn't model "server." One tmux server can feed many iTerm clients. |
| Session | A group of iTerm tabs (typically one iTerm window's worth) | Created per `-CC attach` invocation. |
| Client (`-CC`) | The **gateway tab** (hidden by default) | One client = one gateway = one set of native tabs. |
| Window | iTerm **tab** | Live-synced. tmux window rename → iTerm tab title updates. |
| Pane | iTerm **split pane** (inside a tab) | Layout (h/v split, percentages) round-trips. |
| Pane title (`#{pane_title}`) | iTerm pane title (badge) | Set via `printf '\033]2;...\033\\'` from inside the pane. |
| (no equivalent) | iTerm Window | iTerm has a window layer tmux doesn't. `-CC` puts session tabs in their own iTerm window. |

**Alternative `OpenTmuxWindowsIn = NATIVE_WINDOWS` mode:** if iTerm is configured to open each tmux window as its own iTerm window (`OpenTmuxWindowsIn = 0`), the mapping shifts: tmux window ↔ iTerm window (1:1, with exactly 1 tab inside), and iTerm tabs are no longer used as a tmux-mapping layer. Recognize this mode by seeing N iTerm windows for N tmux windows in a single attached session. The helpers in this repo assume `NEW_TABS = 1`; behavior under `NATIVE_WINDOWS = 0` is not tested.

**Key asymmetries:**

- tmux has no Window-of-windows. iTerm invents one to host tmux's flat window list.
- iTerm has no Server. Multiple `-CC` connections look independent to iTerm.
- A tmux Client is N:1 to a Session — multiple `-CC` clients can attach the same session, producing duplicate iTerm tab sets ("double gateway"). Avoid this.

## `-CC` control mode mechanics

**Gateway tab:** the iTerm tab running `tmux -CC attach`. It's the SSH/local pipe; every other tab is a render target driven by the gateway. **Closing the gateway tears down all the windows/tabs that connection rendered.**

**One gateway = one client = one session.** A single `-CC` invocation can only be attached to one session at a time (same as plain tmux). To work with multiple sessions concurrently, run multiple `-CC` invocations — one per session.

**Duplicate-gateway problem:** if you `-CC attach` the same session twice, iTerm renders both clients' tab sets in parallel — every window appears twice. Always check `has_cc_client` before attaching:

```bash
tmux list-clients -t <session> -F '#{client_control_mode}' | grep -q '^1$' && echo "already CC-attached"
```

The `itmux-chooser` script in this repo automates this check.

**Window title convention:** iTerm names a `-CC` window with the prefix `↣ <session>:` followed by the active window's name. That prefix is the standard signal used by tooling in this repo to find the iTerm window for a given tmux session.

## Naming rules

Two distinct properties, no symmetry:

| Concept | Has a... | tmux variable | Set by |
|---|---|---|---|
| Session | name | `#{session_name}` / `#S` | `tmux rename-session` |
| Window | name | `#{window_name}` / `#W` | `tmux rename-window` *or* automatic-rename from running command |
| Pane | title | `#{pane_title}` / `#T` | OSC 2 escape sequence from inside the pane |
| Window | ~~title~~ | (does not exist) | — |
| Pane | ~~name~~ | (does not exist) | — |

**Naming convention:** "name" = something you/tmux set deliberately via a command. "title" = something the program in the pane advertises about itself.

### The Rename-In-tmux Rule

**Verified empirically.** The tmux ↔ iTerm name binding is **one-way: tmux → iTerm**, and the propagation is complete across all three name-bearing layers (session, window, pane). Test method: created a tmux session with 2 windows × 2 panes, attached via `-CC`, renamed every layer in tmux, confirmed iTerm reflected each change within ~1s. iTerm subscribes to tmux's window/pane state and renders it. iTerm does not push name changes back unless it explicitly sends a tmux command via `-CC`.

| Action | Mechanism | Propagates to tmux? |
|---|---|---|
| `tmux rename-session/window` from a shell | tmux command | ✅ |
| `Ctrl-b ,` (rename current window) | tmux command | ✅ |
| `Ctrl-b $` (rename current session) | tmux command | ✅ |
| **iTerm tmux Dashboard → rename** | sends tmux command via `-CC` | ✅ (it's part of iTerm's tmux integration, not generic UI) |
| iTerm Python API `Tab.async_set_title()` (tmux-backed tab) | direct tmux `rename-window` passthrough | ✅ NOT a local override — it sets `window_name` directly. Setting `""` blanks the tmux name (destructive). |
| AppleScript `set name of session` (tmux-backed tab) | iTerm-local but auto-overridden | ❌ sets a local value; iTerm's dynamic naming reverts within milliseconds. |
| iTerm Python API `Session.async_set_name()` (tmux-backed tab) | silent no-op | ❌ doesn't affect tmux or iTerm display. |
| Edit Tab Title… right-click menu (tmux-backed tab) | direct tmux `rename-window` passthrough | ✅ verified with operator-driven test: right-click → Edit Tab Title… → typed value → Enter; `tmux window_name` updated to the typed value. |

**For tmux-backed tabs in `-CC` mode, names are tmux-derived. There is no separate iTerm-local override layer accessible via Python API.** This was a common misassumption — earlier guidance assumed a sticky iTerm-local title override existed for tmux tabs (analogous to iTerm's normal tab-title override for non-tmux tabs); empirical testing disproved this.

**Rule:** rename in tmux (or via the tmux dashboard, which is tmux). For programmatic renames, `Tab.async_set_title()` is acceptable because it does propagate (it's effectively a `tmux rename-window` shortcut), but be aware you're mutating tmux state, not iTerm-local state. **Never call `async_set_title("")` — it blanks the tmux window name.**

### Manual rename pins the name (without changing `automatic-rename`)

When you rename a window via any of the propagating mechanisms above, the new name persists across subsequent process changes within that pane. tmux internally flags the window as "manually named" and skips it in the auto-rename loop.

**The `automatic-rename` window option is NOT modified.** Earlier guidance claimed manual renames set `automatic-rename off` for the window — wrong about the mechanism. The window-level option remains empty (inheriting the global default, typically `on`), but the internal flag pins the name regardless.

Test that proved it:

```bash
TMX="$(command -v tmux)"
env -u TMUX $TMX new-session -d -s probe -n shell-now
env -u TMUX $TMX rename-window -t probe:shell-now my-pinned-name
env -u TMUX $TMX send-keys -t probe:my-pinned-name "vim" Enter
sleep 2
env -u TMUX $TMX list-windows -t probe \
    -F "name=#{window_name} auto=#{automatic_rename} cmd=#{pane_current_command}"
# Output: name=my-pinned-name auto= cmd=vim
# (name didn't revert to "vim" even though automatic_rename is empty/inheriting)
env -u TMUX $TMX kill-session -t probe
```

To unpin and re-enable auto-rename for a window (so process changes update the name again):

```bash
tmux set-option -w -t '<session>:<window>' automatic-rename on
```

To pin a name *before* renaming:

```bash
tmux set-option -w -t '<session>:<window>' automatic-rename off
```

`#{automatic_rename}` returns empty when the option is unset at the window level (inheriting global), `on`/`off` when explicit.

## Structural change propagation matrix

How structural changes flow between tmux and iTerm — verified empirically by issuing tmux commands and reading iTerm state via the iTerm Python API (and vice versa).

### tmux → iTerm

| tmux command | iTerm reflects? | Notes |
|---|---|---|
| `rename-session` / `rename-window` / `select-pane -T` | ✅ | All three name layers propagate. |
| `swap-window -s X -t Y` | ❌ | tmux per-session **index** swaps, but **iTerm tab strip order does not change**. iTerm pins each tab to its tmux global `window_id` (`@N`) and ignores reindexing. |
| `move-window -s X -t Y` | ❌ (likely) | Same root cause as `swap-window` — iTerm displays by `window_id` order, not `window_index`. |
| `swap-pane -s a.0 -t a.1` | ✅ | iTerm visually swaps the panes in the affected tab. tmux pane geometry is what iTerm renders. |
| `join-pane -s X.0 -t Y` | ✅ | The pane moves to the destination window's tab in iTerm. Source tab loses a pane (or disappears if it had only one). |
| `break-pane -s X.0` | ✅ | A new iTerm tab appears for the new window (auto-named from running command, e.g. `zsh`). |
| `kill-pane` / `kill-window` | ✅ | iTerm closes the affected pane / tab. |

### iTerm → tmux (Python API)

| iTerm Python API call | tmux reflects? | Notes |
|---|---|---|
| `Window.async_set_tabs([...])` for simple swap (two adjacent tabs) | ✅ | tmux receives `move-window` and reorders per-session indices. iTerm and tmux end up matching. |
| `Window.async_set_tabs([...])` for full reverse (3+ tabs) | ⚠️ partial | tmux receives some moves but the result desyncs from iTerm — iTerm's display ends up in one order, tmux in another. Avoid complex reorders via API; do them as a sequence of simple swaps. |
| `Tab.async_move_to_window()` | ✅ | Sends `tmux break-pane`. Pane becomes its own new window. |

### Drag-and-drop gestures DO propagate

(Correction to common belief — drag gestures are commonly assumed to be iTerm-local cosmetic moves; in reality, several of them issue tmux commands over `-CC`.)

| Drag gesture | tmux result |
|---|---|
| Drag iTerm tab onto another iTerm window's **tab strip** | iTerm-local UI consolidation only — tmux unchanged. Useful for manually combining `NATIVE_WINDOWS` mode → tabs-in-one-window. |
| Drag iTerm tab (with **single pane**) onto another iTerm tab's **pane body** (split-zone hint shows) | iTerm sends `tmux join-pane` over `-CC`. The source tmux window disappears; its pane joins the destination window. **Mapping survives.** |
| Drag iTerm tab (with **multiple panes**) onto another tab's pane body | iTerm shows **no split-zone hints** — drop is refused. Workaround: `tmux break-pane` first to split into single-pane windows, then drag those individually. |
| Drag a **pane** (via its inner pane title bar) onto another tab's pane body | iTerm shows no hints — refused. Pane-to-pane-across-tabs drag is not supported. |
| Drag a **pane** (via its inner pane title bar) onto the **iTerm tab strip** | iTerm sends `tmux break-pane` over `-CC`. The pane is removed from its current window and becomes its own new tmux window (auto-named from the running command, e.g. `zsh`). **Mapping survives.** |

So iTerm's `-CC` integration does more structural translation than commonly assumed. For single-pane sources, the drag is effectively a UI shortcut for `join-pane`. For multi-pane sources, fall back to tmux commands.

## The "Hide / Detach / Kill" dialog

When you close a `-CC` iTerm window or tab (Cmd-W or the close button), iTerm prompts with three options. **Picking the wrong one is the most common way to accidentally lose tmux state**, so it's worth knowing what each does:

| Button | Effect |
|---|---|
| **Hide** | Bury the iTerm window (still reachable via iTerm menu → Window → Select Buried Session). tmux completely untouched. |
| **Detach tmux Session** | Clean `-CC` disconnect. iTerm window closes; tmux session continues running server-side and you can reattach later. **The right default when you're "done with this view."** |
| **Kill** | Kill the *tmux window* itself (destroys panes/jobs). If it was the session's last window, the session dies. **Destructive — picks this only when you actually want the work gone.** |
| **Cancel** | Don't close. |

The dialog only appears for tmux-backed iTerm windows. Regular (non-`-CC`) iTerm windows close silently.

If you set `AutoHideTmuxClientSession = 1` (recommended), the gateway tab is hidden so you mostly only see this dialog when closing render-target tabs.
