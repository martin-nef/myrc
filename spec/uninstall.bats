#!/usr/bin/env bats

load helpers

setup() {
  setup_test_repo
}

@test "reports nothing to uninstall on a clean system" {
  run "$REPO/uninstall.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to uninstall"* ]]
}

@test "strips the myrc block from .zshrc" {
  cat > "$HOME/.zshrc" <<EOF
# user content above

# >>> myrc >>>
export MYRC_DIR="$REPO"
. "\$MYRC_DIR/.prep"
. "\$MYRC_DIR/.myrc"
# <<< myrc <<<

# user content below
EOF

  run "$REPO/uninstall.sh"
  [ "$status" -eq 0 ]
  refute_has_block "$HOME/.zshrc"
  grep -Fq "user content above" "$HOME/.zshrc"
  grep -Fq "user content below" "$HOME/.zshrc"
}

@test "is a no-op for profile files without the block" {
  echo "untouched" > "$HOME/.zshrc"
  run "$REPO/uninstall.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.zshrc")" = "untouched" ]
}

@test "round-trip: install then uninstall restores .zshrc" {
  echo "original line" > "$HOME/.zshrc"
  local before
  before=$(cat "$HOME/.zshrc")

  "$REPO/install.sh" >/dev/null
  "$REPO/uninstall.sh" >/dev/null

  # Trailing whitespace from the injected block is tolerated.
  [ "$(printf '%s' "$(cat "$HOME/.zshrc")")" = "$before" ]
}

@test "removes command symlinks created by install" {
  touch "$HOME/.zshrc"
  "$REPO/install.sh" >/dev/null
  [ -L "$HOME/.claude/commands/draft-pr.md" ]

  run "$REPO/uninstall.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude/commands/draft-pr.md" ]
  [ ! -e "$HOME/.claude/commands/worktree.md" ]
  [ ! -e "$HOME/.claude/commands/monitor-pull-request.md" ]
}

@test "leaves a real file at a command name alone" {
  touch "$HOME/.zshrc"
  mkdir -p "$HOME/.claude/commands"
  echo "my own draft-pr" > "$HOME/.claude/commands/draft-pr.md"

  run "$REPO/uninstall.sh"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.claude/commands/draft-pr.md" ]
  [ ! -L "$HOME/.claude/commands/draft-pr.md" ]
  grep -Fq "my own draft-pr" "$HOME/.claude/commands/draft-pr.md"
}

@test "removes any symlink at a command name, regardless of target" {
  touch "$HOME/.zshrc"
  mkdir -p "$HOME/.claude/commands"
  ln -s "/tmp/elsewhere.md" "$HOME/.claude/commands/draft-pr.md"

  run "$REPO/uninstall.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude/commands/draft-pr.md" ]
}
