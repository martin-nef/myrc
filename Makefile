.PHONY: install clean test lint fmt fmt-check check

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

lint:
	shellcheck $(SHELL_SCRIPTS)

fmt:
	shfmt -i 2 -ci -w $(SHELL_SCRIPTS)

fmt-check:
	shfmt -i 2 -ci -d $(SHELL_SCRIPTS)

check: lint fmt-check test
