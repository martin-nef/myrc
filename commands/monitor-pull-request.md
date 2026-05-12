Monitor the pull request for the currently checked out branch. Continuously poll for CI check results and PR comments/reviews, evaluate what actions are needed, and either take them automatically or propose them to the user.

# Step 1: Find the Pull Request

Run `gh pr view --json number,url,title,headRefName,state` to find the PR for the current branch. If no PR exists, inform the user and stop.

Display the PR number, title, and URL to the user.

# Step 2: Initialize Tracking State

You will maintain two sets of "already seen" identifiers to detect new events on each poll cycle:

- **Seen checks**: a set of `(check_name, status, conclusion)` tuples.
- **Seen comments**: a set of comment IDs (from both issue comments and review comments).
- **Seen reviews**: a set of review IDs.

On the first poll, populate these sets from current data without taking any action (treat everything already present as "already seen" baseline).

# Step 3: Poll Loop

Repeat the following cycle. Between each cycle, wait 30 seconds using `sleep 30`.

## 3a. Poll CI Checks

Run:
```
gh pr checks --json name,state,conclusion,link,startedAt,completedAt
```

Compare against seen checks. For any check whose `(name, state, conclusion)` tuple is new:

- **If state is `SUCCESS`/`PASS`**: Log it and move on.
- **If state is `FAILURE`/`ERROR`**:
  1. Identify the failing check name and get its run ID from the link (extract the run ID from the URL).
  2. Fetch logs: `gh run view <run_id> --log-failed 2>&1 | tail -300`
  3. Analyze the failure. Categorize it:
     - **Linting failure** (rubocop, eslint, etc.): Run `make lint` to auto-fix locally, then commit and push.
     - **Type check failure** (Sorbet): Read the error, fix the type annotation in the relevant file, then run `make typecheck` to verify, commit and push.
     - **Test failure** (rspec): Read the failed test output, identify the root cause, fix the code or test, re-run the specific failing spec with `bundle exec rspec <file>:<line>` to verify, commit and push.
     - **Packwerk violation**: Run `make packwerk`, fix boundary violations or update todo files, commit and push.
     - **Schema validation failure**: Run `make schema` and commit any generated changes.
     - **Other/unclear failure**: Show the failure logs to the user and ask what action to take.
  4. After pushing fixes, update the seen checks set.
- **If state is `PENDING`/`IN_PROGRESS`**: Note it, no action needed yet.

## 3b. Poll Comments and Reviews

Fetch issue comments (general PR comments):
```
gh api repos/{owner}/{repo}/issues/<pr_number>/comments --jq '.[] | {id, body, user: .user.login, created_at}'
```

Fetch review comments (inline code review comments):
```
gh api repos/{owner}/{repo}/pulls/<pr_number>/comments --jq '.[] | {id, body, path, line, original_line, diff_hunk, user: .user.login, created_at}'
```

Fetch reviews:
```
gh api repos/{owner}/{repo}/pulls/<pr_number>/reviews --jq '.[] | {id, body, state, user: .user.login, submitted_at}'
```

For the owner/repo, extract them from `gh repo view --json owner,name`.

For any **new** comment or review (ID not in seen set):

1. Read the comment body carefully.
2. Classify the comment:

### Auto-actionable (take action immediately without asking):
- **Typo fix**: A reviewer points out a typo in code, comments, or strings → fix it directly.
- **Remove debug code**: Reviewer asks to remove a `puts`, `binding.pry`, `console.log`, `debugger`, leftover comment, etc. → remove it.
- **Trivial rename**: Reviewer suggests a simple variable/method rename → apply it.
- **Delete dead/irrelevant code or comment**: Reviewer asks to remove unused code → remove it.
- **Nit: style/formatting**: Reviewer flags a style issue (spacing, trailing whitespace, missing newline, etc.) → fix it.
- **Missing frozen_string_literal or typed sigil**: Add the missing magic comment.
- **Import/require ordering**: Fix the ordering.

After each auto-fix, commit with a message referencing the review comment (e.g., "Address review: fix typo in payments_controller"), push, and optionally reply to the comment thread if the `gh` API supports it.

### Requires user confirmation (propose and ask):

- **Architectural suggestions**: Reviewer suggests restructuring, moving code to a different component, changing the approach.
- **Logic changes**: Reviewer questions business logic or suggests a different algorithm.
- **New feature requests**: Reviewer asks for additional functionality.
- **Ambiguous feedback**: The comment is unclear or could be interpreted multiple ways.
- **Disagreements**: The reviewer disagrees with the approach fundamentally.

**Exception** if the PR comment is made by the current git user, do not ask - fix.

For these, present the comment to the user with:
- Who wrote it
- The exact comment text
- The file/line context if it's an inline comment
- Your proposed action (or multiple options)

Then ask the user how to proceed before making changes.

## 3c. Report Status

At the end of each poll cycle, give a brief status summary:
- Number of checks passing / failing / pending
- Any new comments processed
- Any actions taken or pending user input

If ALL checks are passing AND there are no unresolved review comments requiring action, inform the user that the PR looks good and ask if they want to continue monitoring or stop.

# Step 4: Committing and Pushing Changes

When making fixes (either from CI failures or review comments):

1. Stage only the relevant changed files: `git add <specific files>`
2. Commit with a descriptive message: `git commit -m "<description of fix>"`
3. Push: `git push`
4. Log what was pushed so the user has a clear audit trail.

Group related small fixes into a single commit when they happen in the same poll cycle (e.g., multiple typo fixes from the same review). Keep CI fixes in separate commits for clarity.

# Important Rules

- **Never force-push** unless explicitly asked by the user.
- **Never modify non-English locale files** — translations are managed by Smartling.
- **Always run the relevant validation** (e.g. `make lint`, `make typecheck`, `bundle exec rspec`) locally before pushing a fix to avoid cascading CI failures.
- If a fix attempt fails verification locally, inform the user rather than pushing broken code.
- When analyzing CI logs, focus on the actual error message — skip boilerplate setup/teardown output.
- If the same check keeps failing after your fix, present the situation to the user after 2 attempts rather than looping indefinitely.
- Respect component boundaries (Packwerk) when making changes.
