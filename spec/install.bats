#!/usr/bin/env bats

load helpers

setup() {
  setup_test_repo
}

@test "fails when run from a directory without .prep" {
  rm "$REPO/.prep"
  touch "$HOME/.zshrc"
  run "$REPO/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *".prep not found"* ]]
}

@test "fails when no profile files exist" {
  run "$REPO/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no existing profile files"* ]]
}

@test "creates .tokens from dummy.tokens when missing" {
  touch "$HOME/.zshrc"
  run "$REPO/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$REPO/.tokens" ]
  cmp -s "$REPO/.tokens" "$REPO/dummy.tokens"
}

@test "leaves existing .tokens alone" {
  touch "$HOME/.zshrc"
  echo "MY_SECRET=keep-me" > "$REPO/.tokens"
  run "$REPO/install.sh"
  [ "$status" -eq 0 ]
  grep -Fq "MY_SECRET=keep-me" "$REPO/.tokens"
}

@test "injects block into existing .zshrc" {
  touch "$HOME/.zshrc"
  run "$REPO/install.sh"
  [ "$status" -eq 0 ]
  assert_has_block "$HOME/.zshrc"
  grep -Fq ".myrc" "$HOME/.zshrc"
  grep -Fq "MYRC_DIR=\"$REPO\"" "$HOME/.zshrc"
}

@test "injects .myenv into .zshenv (env-only file)" {
  touch "$HOME/.zshenv"
  run "$REPO/install.sh"
  [ "$status" -eq 0 ]
  assert_has_block "$HOME/.zshenv"
  grep -Fq ".myenv" "$HOME/.zshenv"
  ! grep -Fq "/.myrc\"" "$HOME/.zshenv"
}

@test "skips non-existent profile files" {
  touch "$HOME/.zshrc"
  run "$REPO/install.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.bashrc" ]
  [ ! -e "$HOME/.profile" ]
}

@test "is idempotent: does not double-inject" {
  touch "$HOME/.zshrc"
  "$REPO/install.sh" >/dev/null
  local first_size
  first_size=$(wc -c < "$HOME/.zshrc")

  run "$REPO/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  [ "$(wc -c < "$HOME/.zshrc")" -eq "$first_size" ]
}

@test "creates ~/.claude/commands and symlinks command files" {
  touch "$HOME/.zshrc"
  run "$REPO/install.sh"
  [ "$status" -eq 0 ]
  [ -d "$HOME/.claude/commands" ]
  [ -L "$HOME/.claude/commands/draft-pr.md" ]
  [ -L "$HOME/.claude/commands/worktree.md" ]
  [ -L "$HOME/.claude/commands/monitor-pull-request.md" ]
  [ "$(readlink "$HOME/.claude/commands/draft-pr.md")" = "$REPO/commands/draft-pr.md" ]
}

@test "refreshes a stale symlink at the same name" {
  touch "$HOME/.zshrc"
  mkdir -p "$HOME/.claude/commands"
  ln -s "/tmp/somewhere-else.md" "$HOME/.claude/commands/draft-pr.md"

  run "$REPO/install.sh"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude/commands/draft-pr.md" ]
  [ "$(readlink "$HOME/.claude/commands/draft-pr.md")" = "$REPO/commands/draft-pr.md" ]
}

@test "leaves a real file at the same name alone" {
  touch "$HOME/.zshrc"
  mkdir -p "$HOME/.claude/commands"
  echo "my own draft-pr" > "$HOME/.claude/commands/draft-pr.md"

  run "$REPO/install.sh"
  [ "$status" -eq 0 ]
  [ ! -L "$HOME/.claude/commands/draft-pr.md" ]
  grep -Fq "my own draft-pr" "$HOME/.claude/commands/draft-pr.md"
  [[ "$output" == *"is not a symlink"* ]]
}
