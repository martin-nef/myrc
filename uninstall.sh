#!/bin/sh
# myrc uninstaller. Strips the block install.sh added to shell profile files.
# Safe to run multiple times and from any working directory.
set -eu

BEGIN_MARKER="# >>> myrc >>>"
END_MARKER="# <<< myrc <<<"
removed_any=0

strip() {
  target=$1
  [ -e "$target" ] || return 0
  grep -Fq "$BEGIN_MARKER" "$target" 2>/dev/null || return 0

  tmp=$(mktemp "${TMPDIR:-/tmp}/myrc.uninstall.XXXXXX")
  awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
    $0 == b { skip=1; next }
    skip && $0 == e { skip=0; next }
    !skip { print }
  ' "$target" > "$tmp"

  # Preserve original permissions.
  cat "$tmp" > "$target"
  rm -f "$tmp"

  echo "myrc: removed from $target"
  removed_any=1
}

strip "$HOME/.profile"
strip "$HOME/.bash_profile"
strip "$HOME/.zprofile"
strip "$HOME/.bashrc"
strip "$HOME/.zshrc"

if [ "$removed_any" -eq 0 ]; then
  echo "myrc: nothing to uninstall."
else
  echo "myrc: uninstall complete. Your .tokens file (if any) was left in place;"
  echo "      delete it manually if you no longer need the secrets."
fi
