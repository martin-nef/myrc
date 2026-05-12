# My RC files

A modular shell rc/env-file system for `sh`, `bash`, and `zsh`, with a
plugin convention (`.rc-*`, `.env-*`) for tool-specific setup. Designed
to install cleanly on a fresh PC and grow as dependencies become available.

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Uninstalling](#uninstalling)
- [Documentation](#documentation)
- [Contribution](#contribution)
  - [Tooling](#tooling)
  - [Tests](#tests)
  - [Adding a new plugin](#adding-a-new-plugin)

## Requirements

- A POSIX shell: `sh`, `dash`, `bash`, or `zsh`.
- `make` (optional — you can invoke `./install.sh` directly).
- `awk`, `grep`, `cp`, `mktemp` — available on any standard macOS or Linux install.

Individual `.env-*` plugins (nvm, pyenv, rbenv) and `.rc-*` plugins (git,
kubectl, ssh, ...) activate only when the corresponding tool is already on
your `PATH`, so a fresh machine is supported — install what you need and
re-open your shell.

## Installation

1. Run the install script

   ```sh
   cd myrc
   make # or directly ./install.sh
   ```

   What it does:

   - Copies `dummy.tokens` to `.tokens` on first run. Your real `.tokens`
     file is git-ignored so secrets stay local.
   - Detects which shell profile files already exist in `$HOME` and appends
     a small, marker-delimited block to each. Env files (`~/.profile`,
     `~/.bash_profile`, `~/.zshenv`) source `.myenv` (tokens + every
     `.env-*` plugin). Interactive rc files (`~/.bashrc`, `~/.zshrc`)
     source `.myrc` (which brings in `.myenv` first, then every `.rc-*`
     plugin and aliases).
   - The injected block sets `MYRC_DIR` to this repository's absolute path,
     then sources `.prep` followed by the appropriate entry point.
   - `.myenv` is guarded against double-sourcing in the interactive case
     where `.zshenv` *and* `.zshrc` would both pull it in.
   - `.myenv` also exports `BASH_ENV` / `ENV` pointing at itself, so any
     non-interactive bash/dash spawned from your interactive shell still
     sees your tokens. See [docs/shell-sourcing-matrix.md](docs/shell-sourcing-matrix.md).
   - Is idempotent: rerunning skips any file already containing the myrc
     block, so it is safe to run again after you add a new profile file.
   - Errors out if run from the wrong directory (detects `.prep`).

2. Populate the `.tokens` file.

## Uninstalling

```sh
make clean # or directly ./uninstall.sh
```

Strips the injected block from every profile file. `.tokens` is left in
place so you do not lose any secrets you added — remove it manually if you
want a fully clean slate.

## Documentation

- [Shell sourcing matrix](docs/shell-sourcing-matrix.md) — which files
  fire for which shell (login vs non-login, interactive vs
  non-interactive) and how myrc slots into each, across sh, bash, and
  zsh. Read this if you are wondering why scripts, editor subshells, or
  cron jobs don't see your tokens.

## Contribution

### Tooling

| Tool                                                | Used for                                   | Required?          |
| --------------------------------------------------- | ------------------------------------------ | ------------------ |
| [bats-core](https://github.com/bats-core/bats-core) | Running the test suite (`make test`)       | Required for tests |
| [shellcheck](https://www.shellcheck.net/)           | Static analysis (`make lint`)              | Required for lint  |
| [shfmt](https://github.com/mvdan/sh)                | Formatting (`make fmt` / `make fmt-check`) | Optional           |

Install everything on macOS:

```sh
brew install bats-core shellcheck shfmt
```

On Debian/Ubuntu:

```sh
sudo apt-get install bats shellcheck
# shfmt: see https://github.com/mvdan/sh/releases or use `go install mvdan.cc/sh/v3/cmd/shfmt@latest`
```

### Tests

`spec/*.bats` exercises `install.sh` and `uninstall.sh` inside an isolated
`$HOME` and a copy of the repo under `$BATS_TEST_TMPDIR`, so the suite never
touches your real dotfiles. `spec/helpers.bash` rsyncs the repo into the
sandbox and skips `.git`, `spec/`, and any local `.tokens` so tests start
from a clean slate.

Common targets:

```sh
make lint        # auto-fix what's fixable (shfmt -w), then flag the rest (shellcheck)
make shellcheck  # shellcheck only
make fmt-check   # shfmt -d  — diff-only, no file changes
make test        # bats spec/
make check       # read-only: fmt-check + test + shellcheck (run before opening a PR / in CI)
```

Lint, fmt, and tests currently cover the installer scripts only. The
sourced fragments (`.prep`, `.myenv`, `.myrc`, `.rc-*`, `.env-*`) have
pre-existing shellcheck findings (mostly missing shell directives, plus
a few real quoting bugs) — they will be folded into `make lint` once
cleaned up.

### Adding a new plugin

A plugin is a single file in `$MYRC_DIR`. Two flavours:

- **`.rc-<tool>`** — interactive-only. Aliases, completions,
  interactive-shell tweaks. Sourced by `.myrc`, so it only runs in
  interactive shells (any bash/zsh tab you type in).
- **`.env-<tool>`** — environment/PATH setup that every shell (including
  scripts, editor subshells, cron) should see. Sourced by `.myenv`,
  which is pulled in by `~/.zshenv`, `~/.profile`, `~/.bash_profile`,
  and via `BASH_ENV` for non-interactive bash descendants.

Use `.env-` for PATH manipulations and tool-version managers whose
effects scripts rely on (nvm, rbenv, pyenv). Use `.rc-` for everything
else — aliases, completion setup, prompt tweaks.

Follow these conventions:

1. **Early return if the tool is absent.** A fresh machine should load
   your plugin as a no-op until the tool is installed. Use `command -v`
   (or a file check) and bail out at the top:

   ```sh
   command -v foo >/dev/null || return
   ```

2. **Stay portable.** Target `bash` and `zsh`, and write POSIX shell by
   default — plugins run from `sh` too when `$MYRC_DIR` is pre-set. If
   you genuinely need shell-specific features (zsh hooks, `autoload`,
   arrays, …), gate the file with `$MYRC_SHELL`:

   ```sh
   [ "$MYRC_SHELL" = "zsh" ] || return
   ```

   `.prep` sets `MYRC_SHELL` to `zsh`, `bash`, or `sh` before any plugin
   runs. See `.rc-kubectl` for a `case "$MYRC_SHELL"` example that
   branches instead of bailing.

3. **Keep startup snappy.** A new shell sources every plugin, so any
   subprocess or heavy source costs you every prompt. Two patterns we
   use:

   - **Lazy stubs** for tools whose init forks subprocesses
     (`eval "$(foo init -)"`) or sources a slow file (`nvm.sh`).
     Define stub functions for every command that should trigger the
     load; on first call they unset themselves, run the real init, and
     dispatch. See `.env-nvm`, `.env-rbenv`, `.env-pyenv` for the pattern.

   - **On-disk cache** for completion generators that always emit the
     same text per binary version (e.g. `kubectl completion zsh`).
     Write to `${XDG_CACHE_HOME:-$HOME/.cache}/myrc/` and regenerate
     only when the binary is newer than the cache. See `.rc-kubectl`.

   If a plugin only sets env vars or aliases, no laziness is needed —
   just keep it short.

4. **Namespace private helpers.** Prefix internal functions with
   `_myrc_` so they don't collide with the user's shell.

Before committing, time your plugin in isolation.

**zsh** (uses `$EPOCHREALTIME` for sub-millisecond resolution):

```sh
zsh -f -c '
  zmodload zsh/datetime
  export MYRC_DIR="'"$PWD"'" MYRC_SHELL=zsh
  . "$MYRC_DIR/.myenv"
  t0=$EPOCHREALTIME; . "$MYRC_DIR/.rc-yourplugin"; t1=$EPOCHREALTIME
  printf "%.3f s\n" $(( t1 - t0 ))
'
```

**bash** (5.0+ — supports `$EPOCHREALTIME` natively, no module needed):

```sh
bash --noprofile --norc -c '
  export MYRC_DIR="'"$PWD"'" MYRC_SHELL=bash
  . "$MYRC_DIR/.myenv"
  t0=$EPOCHREALTIME; . "$MYRC_DIR/.rc-yourplugin"; t1=$EPOCHREALTIME
  awk "BEGIN{printf \"%.3f s\n\", $t1 - $t0}"
'
```

**sh / older bash / any POSIX shell** — fall back to external `/usr/bin/time`:

```sh
/usr/bin/time -p sh -c '
  export MYRC_DIR="'"$PWD"'" MYRC_SHELL=sh
  . "$MYRC_DIR/.myenv"
  . "$MYRC_DIR/.rc-yourplugin"
' 2>&1 | grep real
```

Aim for <10 ms on a warm cache.

To time the whole startup for a given shell, drop the `.rc-yourplugin`
step and source `.myrc` instead — or just `/usr/bin/time -p zsh -i -c exit`.
