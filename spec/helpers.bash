# Shared helpers for bats tests.

# Set up an isolated copy of the repo under $BATS_TEST_TMPDIR and a fake
# $HOME so install.sh / uninstall.sh can be exercised without touching
# the user's real dotfiles.
setup_test_repo() {
  mkdir -p "$BATS_TEST_TMPDIR/repo"
  # Canonicalize so it matches what install.sh's `pwd -P` produces
  # (on macOS, /var/... resolves to /private/var/...).
  REPO=$(cd "$BATS_TEST_TMPDIR/repo" && pwd -P)

  local src
  src=$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)

  # Mirror the repo into the sandbox. Skip .git (large, irrelevant),
  # spec/ (the tests themselves), and any real .tokens the user has
  # locally — tests should start from a clean slate.
  rsync -a \
    --exclude='.git/' \
    --exclude='spec/' \
    --exclude='.tokens' \
    "$src/" "$REPO/"

  chmod +x "$REPO"/*.sh

  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

# Assert the file contains the myrc install block.
assert_has_block() {
  grep -Fq "# >>> myrc >>>" "$1"
  grep -Fq "# <<< myrc <<<" "$1"
}

# Assert the file does not contain the myrc install block.
refute_has_block() {
  ! grep -Fq "# >>> myrc >>>" "$1"
}
