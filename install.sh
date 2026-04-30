#!/usr/bin/env bash
# install.sh — symlink itmux-* helpers into ~/.local/bin/
# Idempotent: re-running is safe.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_SRC="$SCRIPT_DIR/bin"
BIN_DST="$HOME/.local/bin"

mkdir -p "$BIN_DST"

echo "=== iterm-tmux-helpers — installer ==="
echo "Source: $BIN_SRC"
echo "Dest:   $BIN_DST"
echo

# 1. Symlink each itmux-* script
linked=0
backed_up=0
already=0
for src in "$BIN_SRC"/itmux-*; do
    [ -f "$src" ] || continue
    name="$(basename "$src")"
    dst="$BIN_DST/$name"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        echo "  ✓ $name already linked"
        already=$((already+1))
    elif [ -e "$dst" ] || [ -L "$dst" ]; then
        echo "  ⚠ $dst exists; backing up to ${dst}.bak"
        mv "$dst" "${dst}.bak"
        ln -s "$src" "$dst"
        echo "  ✓ $name linked"
        backed_up=$((backed_up+1))
    else
        ln -s "$src" "$dst"
        echo "  ✓ $name linked"
        linked=$((linked+1))
    fi
done

# 2. Backward-compat: keep tmux-chooser → itmux-chooser
COMPAT_DST="$BIN_DST/tmux-chooser"
COMPAT_SRC="$BIN_DST/itmux-chooser"
if [ -L "$COMPAT_DST" ] && [ "$(readlink "$COMPAT_DST")" = "$COMPAT_SRC" ]; then
    echo "  ✓ tmux-chooser compat symlink already in place"
elif [ -e "$COMPAT_DST" ] || [ -L "$COMPAT_DST" ]; then
    echo "  ⚠ $COMPAT_DST exists (different target); leaving alone"
else
    ln -s "$COMPAT_SRC" "$COMPAT_DST"
    echo "  ✓ tmux-chooser compat symlink created (→ itmux-chooser)"
fi

# 3. Dependency check (advisory only)
echo
echo "=== Dependency check ==="
missing=0
check_dep() {
    local name="$1" cmd="$2" install_hint="$3"
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "  ✓ $name: $(command -v "$cmd")"
    else
        echo "  ✗ $name MISSING — $install_hint"
        missing=$((missing+1))
    fi
}
check_dep "tmux" tmux "brew install tmux"
check_dep "fzf"  fzf  "brew install fzf"
check_dep "python3" python3 "macOS ships python3; or brew install python"

if command -v python3 >/dev/null 2>&1; then
    if python3 -c "import iterm2" 2>/dev/null; then
        echo "  ✓ python3 'iterm2' package importable"
    else
        echo "  ✗ python3 cannot import 'iterm2' — install with:"
        echo "      python3 -m pip install --user iterm2"
        echo "    or via pipx:"
        echo "      pipx install iterm2"
        missing=$((missing+1))
    fi
fi

# 4. PATH check
echo
case ":$PATH:" in
    *":$BIN_DST:"*) echo "  ✓ $BIN_DST is on PATH" ;;
    *) echo "  ⚠ $BIN_DST is NOT on PATH — add to your shell rc:"
       echo "      export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

echo
echo "Linked $linked  Backed-up $backed_up  Already-present $already"
if [ "$missing" -gt 0 ]; then
    echo "⚠  $missing dependency issue(s) above — install before using the scripts"
    exit 1
fi

echo "✓ Installation complete."
echo
echo "Next steps:"
echo "  1. Set iTerm Profiles → default → General → Command to: $BIN_DST/itmux-chooser"
echo "  2. Enable iTerm Settings → General → Magic → 'Enable Python API'"
echo "  3. Recommended defaults:"
echo "     defaults write com.googlecode.iterm2 AutoHideTmuxClientSession -int 1"
echo "     defaults write com.googlecode.iterm2 OpenTmuxWindowsIn -int 1"
