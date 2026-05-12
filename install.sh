#!/bin/sh
# myrc installer. Portable POSIX sh (works under sh/dash/bash/zsh).
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"

if [ ! -r "$SCRIPT_DIR/.prep" ]; then
  echo "myrc: run this from the repository root (.prep not found)." >&2
  exit 1
fi

cd "$SCRIPT_DIR"

if [ ! -e .tokens ]; then
  cp dummy.tokens .tokens
  echo "myrc: created .tokens from dummy.tokens -- edit it to add your real values."
else
  echo "myrc: .tokens already exists, leaving it alone."
fi

BEGIN_MARKER="# >>> myrc >>>"
END_MARKER="# <<< myrc <<<"
installed_any=0

inject() {
  target=$1
  rc_file=$2

  # Only touch profile files the user already uses.
  [ -e "$target" ] || return 0

  if grep -Fq "$BEGIN_MARKER" "$target" 2>/dev/null; then
    echo "myrc: already installed in $target"
    installed_any=1
    return 0
  fi

  {
    printf '\n%s\n' "$BEGIN_MARKER"
    printf 'export MYRC_DIR="%s"\n' "$SCRIPT_DIR"
    printf '. "$MYRC_DIR/.prep"\n'
    printf '. "$MYRC_DIR/%s"\n' "$rc_file"
    printf '%s\n' "$END_MARKER"
  } >> "$target"

  echo "myrc: installed in $target"
  installed_any=1
}

# Env files get .myenv (tokens + env-manager plugins). For zsh we use
# .zshenv because it is sourced by *every* zsh invocation (login/non-login,
# interactive/non-interactive) — a strict superset of .zprofile.
inject "$HOME/.profile"      ".myenv"
inject "$HOME/.bash_profile" ".myenv"
inject "$HOME/.zshenv"       ".myenv"

# Interactive rc files get .myrc (env + aliases + .rc-* plugins).
inject "$HOME/.bashrc"       ".myrc"
inject "$HOME/.zshrc"        ".myrc"

if [ "$installed_any" -eq 0 ]; then
  echo "myrc: no existing profile files found under \$HOME."
  echo "      create one of ~/.profile, ~/.bashrc, ~/.zshrc, ~/.bash_profile or ~/.zshenv and re-run."
  exit 1
fi

# Symlink Claude Code slash commands into ~/.claude/commands.
if [ -d "$SCRIPT_DIR/commands" ]; then
  claude_cmd_dir="$HOME/.claude/commands"
  mkdir -p "$claude_cmd_dir"
  for src in "$SCRIPT_DIR"/commands/*.md; do
    [ -e "$src" ] || continue
    name=$(basename "$src")
    dest="$claude_cmd_dir/$name"

    if [ -L "$dest" ]; then
      # Re-point existing symlink (idempotent).
      ln -sfn "$src" "$dest"
      echo "myrc: refreshed symlink $dest"
    elif [ -e "$dest" ]; then
      echo "myrc: $dest exists and is not a symlink, leaving it alone."
    else
      ln -s "$src" "$dest"
      echo "myrc: linked $dest -> $src"
    fi
  done
fi

echo
echo "myrc: done. Populate $SCRIPT_DIR/.tokens, then open a new shell"
echo "      (or re-source the relevant profile file) to pick up changes."
