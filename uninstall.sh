#!/usr/bin/env bash
# uninstall.sh — remove itmux-* symlinks from ~/.local/bin/
# Only removes symlinks that point back into THIS repo. Leaves regular files alone.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_SRC="$SCRIPT_DIR/bin"
BIN_DST="$HOME/.local/bin"

echo "=== iterm-tmux-helpers — uninstaller ==="
echo "Removing symlinks in $BIN_DST that point into $BIN_SRC"
echo

removed=0
skipped=0
for dst in "$BIN_DST"/itmux-* "$BIN_DST/tmux-chooser"; do
    [ -L "$dst" ] || continue
    target="$(readlink "$dst")"
    case "$target" in
        "$BIN_SRC"/*|"$BIN_DST/itmux-chooser")
            rm "$dst"
            echo "  ✓ removed $(basename "$dst")"
            removed=$((removed+1))
            ;;
        *)
            echo "  ⚠ skipped $(basename "$dst") — points to $target (not ours)"
            skipped=$((skipped+1))
            ;;
    esac
done

echo
echo "Removed $removed  Skipped $skipped"
echo "✓ Uninstall complete."
echo "Note: this does not remove dependencies (tmux, fzf, iterm2 python pkg)."
