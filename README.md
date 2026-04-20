# My RC files

My personal terminal script, command and alias collection.

Designed to work on a fresh PC, but expand as as dependencies become available.

## Requirements

- A POSIX shell: `sh`, `dash`, `bash`, or `zsh`.
- `make` (optional — you can invoke `./install.sh` directly).
- `awk`, `grep`, `cp`, `mktemp` — available on any standard macOS or Linux install.

Individual `.rc-*` plugins (git, nvm, pyenv, rbenv, kubectl, ...) activate only
when the corresponding tool is already on your `PATH`, so a fresh machine is
supported — install what you need and re-open your shell.

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
     a small, marker-delimited block to each. Login/profile files
     (`~/.profile`, `~/.bash_profile`, `~/.zprofile`) source `.myprofile`
     (environment only). Interactive rc files (`~/.bashrc`, `~/.zshrc`)
     source `.myrc` (environment + aliases + every `.rc-*` plugin).
   - The injected block sets `MYRC_DIR` to this repository's absolute path,
     then sources `.prep` followed by the appropriate entry point.
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
