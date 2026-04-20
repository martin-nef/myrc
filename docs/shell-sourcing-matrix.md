# Shell sourcing matrix

Which files get sourced by which shell, and where myrc slots in.

## The two axes

Shell invocations vary along **two independent** axes:

- **Login vs non-login** — is this the "entry" shell of a session (console,
  SSH, or a terminal emulator configured to launch a login shell), or a
  child shell inside an existing session (new terminal tab on Linux,
  subshell, script, `ssh host 'cmd'`, editor-spawned shell)?
- **Interactive vs non-interactive** — is a human typing at a prompt (has
  a tty, reads input), or is the shell reading from a file / `-c` string
  and exiting?

They are orthogonal. Every shell is one of four combinations.

## What each shell reads (stock defaults)

| Shell | Login + interactive | Login + non-interactive | Non-login + interactive | Non-login + non-interactive |
| --- | --- | --- | --- | --- |
| `sh` / `dash` | `/etc/profile`, `~/.profile` | `/etc/profile`, `~/.profile` | `$ENV` if set | `$ENV` if set |
| `bash` | `/etc/profile`, then the first of `~/.bash_profile` / `~/.bash_login` / `~/.profile`, then `~/.bashrc` only if the profile file sources it | same, minus `.bashrc` | `/etc/bash.bashrc` (Debian-family only), `~/.bashrc` | `$BASH_ENV` if set |
| `zsh` | `/etc/zshenv`, `~/.zshenv`, `/etc/zprofile`, `~/.zprofile`, `/etc/zshrc`, `~/.zshrc`, `/etc/zlogin`, `~/.zlogin` | `/etc/zshenv`, `~/.zshenv`, `/etc/zprofile`, `~/.zprofile` | `/etc/zshenv`, `~/.zshenv`, `/etc/zshrc`, `~/.zshrc` | `/etc/zshenv`, `~/.zshenv` |

Two things are easy to miss:

- **`~/.zshenv` is the only file zsh reads in every case.** It's the right
  home for things every zsh invocation must see (PATH, env vars,
  language-manager shims). `~/.zprofile` misses non-interactive shells
  and is therefore a strict subset.
- **Non-login + non-interactive bash reads nothing by default.** Scripts,
  `ssh host 'cmd'`, editor subshells, cron jobs, systemd user units —
  none of them run your `.profile` or `.bashrc`. They only see exported
  environment inherited from whatever started them. The escape hatch is
  `BASH_ENV`: if set, bash sources the named file when it is
  non-interactive.

## Typical real-world invocations

| You do this | Resulting shell |
| --- | --- |
| Open macOS Terminal or iTerm2 (default) | login + interactive |
| New tab in GNOME Terminal / Konsole / Alacritty / Arch / WSL | non-login + interactive |
| `ssh host` (interactive session) | login + interactive |
| `ssh host 'echo $FOO'` | non-login + non-interactive |
| `bash ./script.sh`, `./script.sh` with `#!/bin/bash` | non-login + non-interactive |
| `$(...)` / `` `...` `` inside an existing shell | no new shell — reuses parent |
| VSCode / JetBrains "integrated terminal" | non-login + interactive on Linux; usually login + interactive on macOS |
| cron job, systemd user unit | non-login + non-interactive (and no parent env to inherit from) |

## Where myrc plugs in

myrc has two entry points:

- **`.myenv`** — tokens + every `.env-*` plugin. Light, idempotent,
  guarded against double-sourcing. Exports `BASH_ENV` and `ENV` pointing
  at itself.
- **`.myrc`** — sources `.myenv` first, then every `.rc-*` plugin
  (aliases, completions, interactive-only tweaks).

`install.sh` injects a small marker-delimited block into these files:

| File | Sources | Rationale |
| --- | --- | --- |
| `~/.profile` | `.myenv` | POSIX login shells (sh/dash), also the bash login fallback |
| `~/.bash_profile` | `.myenv` | bash login shell, when present |
| `~/.zshenv` | `.myenv` | zsh — every invocation, interactive or not |
| `~/.bashrc` | `.myrc` | bash interactive (non-login) |
| `~/.zshrc` | `.myrc` | zsh interactive |

## Coverage of the four combinations

| Combination | Linux/WSL example | What fires | Result |
| --- | --- | --- |---|
| Login + interactive | SSH in, text console | profile (`.myenv`) + rc (`.myrc`) | tokens + interactive bits ✓ |
| Login + non-interactive | `bash -l -c …` | profile (`.myenv`) | tokens only ✓ |
| Non-login + interactive | GNOME Terminal / WSL tab | rc (`.myrc`, which sources `.myenv` first) | tokens + interactive bits ✓ |
| Non-login + non-interactive | script / editor subshell / `ssh host cmd` | inherits `BASH_ENV=.myenv` / `ENV=.myenv` from parent → sources `.myenv` | tokens only ✓ |
| Non-login + non-interactive (fresh) | cron / systemd | nothing | **not covered** — see below |

## What isn't covered

Anything started **outside** of one of your interactive shells doesn't
inherit `BASH_ENV` / `ENV` and therefore never reaches `.myenv`:

- cron jobs (unless you `. "$MYRC_DIR/.myenv"` at the top of the script)
- systemd user units (use `EnvironmentFile=` or a wrapper that sources
  `.myenv`)
- launchd jobs on macOS (use `EnvironmentVariables` or a wrapper)

These are per-service concerns and outside what `install.sh` can
reasonably automate.

## Why `.myenv` guards against double-sourcing

In the common interactive-zsh case, both `.zshenv` *and* `.zshrc` pull
in `.myenv` (the latter transitively, via `.myrc`). The file sets a
shell-local `MYENV_LOADED=1` on the first run and early-returns on the
second. It is deliberately **not** exported — child shells must re-run
`.myenv` so their shell functions (the lazy stubs for nvm / rbenv /
pyenv) get defined.
