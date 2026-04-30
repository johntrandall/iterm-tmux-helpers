"""Shared version check for itmux-* helpers.

Prints a one-line warning to stderr if the running tmux or iTerm2 version
differs from the version this codebase was empirically verified against.
Non-fatal: the warning is advisory.

Usage from a Python helper:

    from _version_check import warn_if_versions_unverified
    warn_if_versions_unverified()
"""
import os
import re
import subprocess
import sys

# Versions verified empirically (see ~/.claude/skills/iterm-tmux-integration/SKILL.md
# frontmatter `freshness.additional_refresh_triggers`).
VERIFIED_TMUX_VERSION = "3.6a"
VERIFIED_ITERM_VERSION = "3.6"  # major.minor only — iTerm patches release frequently

_WARNED = False  # process-local: warn at most once per invocation


def _running_tmux_version():
    try:
        out = subprocess.run(
            [os.environ.get("TMUX_BIN", "tmux"), "-V"],
            capture_output=True, text=True, timeout=2,
        ).stdout.strip()
        # "tmux 3.6a" / "tmux next-3.7" / "tmux 3.5"
        m = re.match(r"tmux\s+(\S+)", out)
        return m.group(1) if m else None
    except Exception:
        return None


def _running_iterm_version():
    """Read iTerm2's CFBundleShortVersionString without booting the Python API."""
    plist = "/Applications/iTerm.app/Contents/Info.plist"
    if not os.path.exists(plist):
        return None
    try:
        out = subprocess.run(
            ["defaults", "read", plist, "CFBundleShortVersionString"],
            capture_output=True, text=True, timeout=2,
        ).stdout.strip()
        return out or None
    except Exception:
        return None


def warn_if_versions_unverified():
    """Emit a one-line stderr warning if tmux/iTerm versions don't match what
    we verified against. Suppressed when ITMUX_SUPPRESS_VERSION_WARN is set."""
    global _WARNED
    if _WARNED or os.environ.get("ITMUX_SUPPRESS_VERSION_WARN"):
        return

    issues = []
    tmux_ver = _running_tmux_version()
    if tmux_ver and tmux_ver != VERIFIED_TMUX_VERSION:
        issues.append(f"tmux {tmux_ver} (verified: {VERIFIED_TMUX_VERSION})")

    iterm_ver = _running_iterm_version()
    if iterm_ver:
        # Match on major.minor — patch versions release frequently and aren't
        # behaviorally distinct for our purposes.
        running_mm = ".".join(iterm_ver.split(".")[:2])
        if running_mm != VERIFIED_ITERM_VERSION:
            issues.append(f"iTerm2 {iterm_ver} (verified: {VERIFIED_ITERM_VERSION}.x)")

    if issues:
        print(
            f"⚠ itmux: untested against {' and '.join(issues)} — "
            f"behavior may differ. Set ITMUX_SUPPRESS_VERSION_WARN=1 to silence.",
            file=sys.stderr,
        )

    _WARNED = True


if __name__ == "__main__":
    warn_if_versions_unverified()
