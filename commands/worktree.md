---
description: Set up a new git worktree from a repository with a fresh branch
---

Create a git worktree from an existing repository, ensuring the repo is up to date before branching.

# Workflow

## 1. Gather inputs

Resolve each input via the priority rules below. **Never guess.** If a required input can't be resolved, stop and tell the user — you may *suggest* a value from context, but the user picks.

### Repo path

Priority: **user-specified path/name in `$ARGUMENTS` > fuzzy match in cwd > current working directory**.

- If the user gave a full path, use as-is.
- If the user gave a bare name (e.g. `payments-service`), treat as `./<name>`.
- If the user gave an **abbreviation, sentence, or likely-typo name** (e.g. `paysvc`, `payments service`, `paymetns-service`), look only at the immediate contents of the current directory (`ls ./`, no `find`, no recursion).
  - If exactly one entry is an obvious match (substring, common abbreviation, or single-edit typo of a directory name that is a git repo), use it and **inform** the user which one you picked — do not ask.
  - If zero or multiple plausible matches, **stop and tell the user**, listing what you saw.
- Otherwise (no `$ARGUMENTS`), use the current working directory.
- Confirm the resolved path exists and is a git repo (`git rev-parse --is-inside-work-tree`). If it isn't, **stop and tell the user** — optionally suggest a likely candidate from context, but do not pick for them.

### Prefix (ticket slug or team abbreviation)

Priority: **ticket slug > team abbreviation**.
Precedence: **`$ARGUMENTS` > current branch name**.

- Ticket slug: `[A-Z]+-\d+` pattern, case-insensitive, uppercase the result (e.g. `semo-123` → `SEMO-123`).
- Team abbreviation: an uppercase token in `$ARGUMENTS` that isn't a ticket (e.g. `PAYMENTS`).
- If no prefix is found anywhere, **continue without one** — do not invent one.

### Branch / worktree name

Always **very concise**. Naming rules depend on whether a prefix was resolved:

- **With prefix**: branch and worktree dir are identical, formatted as `<PREFIX>-<short-name>` (e.g. `SEMO-123-retry-fix`). Prefix is uppercase.
- **Without prefix**: branch is just `<short-name>`; the worktree directory is `worktree-<short-name>`.

Replace any `/` in branch names with `-` when deriving the worktree directory name.

Name precedence (stop at first match):
1. `$ARGUMENTS` — descriptive name the user passed.
2. Existing branch — if the user named an existing branch, use it as-is (worktree dir = branch name with `/` → `-`).
3. Conversation context — derive a short kebab-case name from what the user is clearly trying to do.
4. Uncommitted work in the repo — derive a short name from the diff (filenames, change theme).

If none of these yield a name, **stop and tell the user** — do not invent one.

### Base branch

Always base the worktree on the **latest** of the default branch (auto-detected) unless the user specified otherwise. Fetch before resolving.

If the repo has uncommitted or untracked changes, **do not ask** — carry them over to the new worktree without creating commits (stash + pop, see below).

## 2. Prepare the repo

```bash
cd <repo-path>

# 1. Always fetch first — before any other git operations.
git fetch origin

# 2. Detect default branch (or use the user-specified base).
git remote show origin | sed -n '/HEAD branch/s/.*: //p'

# 3. If there are uncommitted/untracked changes, stash them so we can
#    transfer them to the new worktree. Do NOT create commits.
git status --porcelain   # check first
git stash push --include-untracked -m "worktree-transfer"   # only if dirty

# 4. Pull the base branch up to date.
git checkout <base-branch>
git pull --ff-only
```

`git fetch origin` must run before anything else so all decisions use up-to-date refs.

If `git pull` fails (network, non-fast-forward), warn but continue — the worktree can be created from the local state of the base branch.

## 3. Create the worktree

The worktree goes as a **sibling** to the repo directory.

**Never** place the worktree inside a hidden/config directory — e.g. `./.claude/...`, `~/.claude/...`, `.git/worktrees/...`, `.vscode/...`, etc. It must live next to the repo (`../<worktree-dir-name>`) so editors, tooling, and the user's mental model treat it as a peer repo.

```bash
# NEW branch:
git worktree add -b <branch-name> ../<worktree-dir-name> <base-branch>

# EXISTING branch:
git worktree add ../<worktree-dir-name> <existing-branch>
```

If a stash was created in step 2, pop it inside the new worktree so the changes land there cleanly:

```bash
cd ../<worktree-dir-name>
git stash pop
```

## 4. Verify

```bash
pwd
git branch --show-current
```

Confirm:
- Current directory is the worktree path.
- Active branch matches the expected branch name.
- Any transferred changes are present (`git status`).

Report the worktree path to the user and remind them: **all further work in this session should happen inside the worktree directory**, not the original repo.

## 5. Change working directory

After verification, stay `cd`'d into the worktree so subsequent commands run there.

# Error handling

- **Repo path doesn't exist or isn't a git repo**: stop and inform the user.
- **No name can be derived**: stop and inform the user.
- **`git pull` fails**: warn but continue from local state.
- **Worktree directory already exists**: do not ask — switch into it (`cd ../<worktree-dir-name>`), verify the branch matches, and proceed.
