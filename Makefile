.PHONY: install clean test fmt-check shellcheck lint check

SHFMT_FLAGS := -i 2 -ci
SHELL_SCRIPTS := $(shell find . -name '*.sh' -not -path './spec/*')
# Sourced fragments (.prep, .myenv, .myrc, .rc-*, .env-*) have pre-existing
# shellcheck issues — clean those up in a separate pass before adding
# them here.

install:
	./install.sh

clean:
	./uninstall.sh

test:
	bats spec/

fmt-check:
	shfmt $(SHFMT_FLAGS) -d $(SHELL_SCRIPTS)

shellcheck:
	shellcheck $(SHELL_SCRIPTS)

# Auto-fix what's fixable (shfmt -w), then flag the rest (shellcheck).
# Mutates files — safe to commit afterwards.
lint:
	shfmt $(SHFMT_FLAGS) -w $(SHELL_SCRIPTS)
	shellcheck $(SHELL_SCRIPTS)

# Read-only verification: shellcheck + formatting diff + tests.
# Run this before opening a PR / in CI.
check: fmt-check test shellcheck
