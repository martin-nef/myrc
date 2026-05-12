#!/usr/bin/env bats
#
# One-big-loop coverage of every sourced shell file across every shell.
#
# Coverage matrix:
#   - .prep / .myenv / .myrc must parse cleanly under any POSIX shell
#     (sh, dash, bash, zsh). They are sourced under all of them.
#   - .rc-* / .env-* are only required to parse under bash and zsh —
#     they ride on .myrc (interactive only) and may use bash/zsh-isms
#     internally. .myenv's guards (e.g. .env-nvm's MYRC_SHELL check)
#     keep them from being sourced where they'd misbehave.
#   - Smoke test: sourcing .prep + .myenv must succeed under every
#     shell. This exercises the whole .env-* chain end-to-end and
#     confirms the graceful guards work.

load helpers

setup() {
  setup_test_repo
}

parse_in() {
  local shell=$1 file=$2
  case "$shell" in
    bash) "$shell" --noprofile --norc -n "$file" ;;
    zsh) "$shell" -f -n "$file" ;;
    *) "$shell" -n "$file" ;;
  esac
}

source_chain_in() {
  local shell=$1
  # MYRC_DIR is exported into the env of the spawned shell rather than
  # passed as a prefix assignment to `.` — `VAR=val .` only persists
  # past `.`'s return when `.` is treated as a POSIX special builtin,
  # which bash and zsh skip in their default (non-POSIX) modes.
  local cmd=". '$REPO/.prep' && . '$REPO/.myenv'"
  case "$shell" in
    bash) MYRC_DIR="$REPO" "$shell" --noprofile --norc -c "$cmd" ;;
    zsh) MYRC_DIR="$REPO" "$shell" -f -c "$cmd" ;;
    *) MYRC_DIR="$REPO" "$shell" -c "$cmd" ;;
  esac
}

@test "shell-file coverage matrix" {
  local failures=""
  local shell file rel

  for shell in sh dash bash zsh; do
    if ! command -v "$shell" >/dev/null 2>&1; then
      echo "skip: $shell not installed" >&3
      continue
    fi

    # Pure-POSIX top-level files: must parse under every shell.
    for file in "$REPO/.prep" "$REPO/.myenv" "$REPO/.myrc"; do
      rel=$(basename "$file")
      if ! parse_in "$shell" "$file"; then
        failures="$failures $shell:$rel"
      fi
    done

    # Plugins: bash/zsh only — they may use shell-isms internally.
    case "$shell" in
      bash | zsh)
        for file in "$REPO"/.rc-* "$REPO"/.env-*; do
          rel=$(basename "$file")
          if ! parse_in "$shell" "$file"; then
            failures="$failures $shell:$rel"
          fi
        done
        ;;
    esac

    # End-to-end smoke: prep + myenv chain sources cleanly under
    # this shell, exercising every .env-* via the loop in .myenv.
    local chain_stderr
    chain_stderr=$(source_chain_in "$shell" 2>&1 >/dev/null) || {
      failures="$failures $shell:source-chain"
      echo "  $shell source-chain stderr: $chain_stderr" >&2
    }
  done

  if [ -n "$failures" ]; then
    echo "FAILED:$failures" >&2
    return 1
  fi
}

# Behavioural assertions on the top-level entry points. These run
# only under bash because the assertions need a single, predictable
# host shell — the matrix test above already covers parse + chain
# success for every available shell.

@test ".prep sets MYRC_SHELL=bash and requires MYRC_DIR" {
  run bash --noprofile --norc -c "unset MYRC_DIR; . '$REPO/.prep'" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"MYRC_DIR is not set"* ]]

  run bash --noprofile --norc -c "MYRC_DIR='$REPO' . '$REPO/.prep' && echo \"\$MYRC_SHELL\""
  [ "$status" -eq 0 ]
  [ "$output" = "bash" ]
}

@test ".myenv exports BASH_ENV pointing at itself" {
  run bash --noprofile --norc -c "MYRC_DIR='$REPO' . '$REPO/.myenv' && echo \"\$BASH_ENV\""
  [ "$status" -eq 0 ]
  [ "$output" = "$REPO/.myenv" ]
}

# Startup smoke: each shell must finish sourcing the full chain that
# install.sh would inject into its profile within the threshold below.
# Locally we target 100ms — current warm numbers are ~30ms on an M2 Pro,
# so 100ms catches new heavy plugins without flaking. CI relaxes to
# 500ms because shared runners are 5×+ slower for shell I/O than a
# laptop; tighter than that produces flakes without catching anything
# real (CI is for correctness, perf regressions show up locally first).
@test "startup time: each shell sources its chain under threshold" {
  local threshold_ms=100
  if [ -n "${CI:-}" ]; then
    threshold_ms=500
  fi
  local stub_dir="$BATS_TEST_TMPDIR/stubs"
  local failures=""
  local shell entry flags time_s time_ms

  # Stub ssh-agent so .rc-ssh doesn't spawn a real agent (which would
  # both pollute the test environment and add nondeterministic time).
  mkdir -p "$stub_dir"
  cat >"$stub_dir/ssh-agent" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$stub_dir/ssh-agent"

  # Pre-populate $SSH_ENV so .rc-ssh's steady-state branch is exercised
  # rather than its cold-start fork.
  mkdir -p "$HOME/.ssh"
  cat >"$HOME/.ssh/agent.env" <<EOF
SSH_AGENT_PID=$$; export SSH_AGENT_PID;
SSH_AUTH_SOCK=/tmp/myrc-test-fake.sock; export SSH_AUTH_SOCK;
EOF
  chmod 600 "$HOME/.ssh/agent.env"

  for shell in sh dash bash zsh; do
    if ! command -v "$shell" >/dev/null 2>&1; then
      echo "skip: $shell not installed" >&3
      continue
    fi

    case "$shell" in
      bash | zsh) entry=.myrc ;;
      *) entry=.myenv ;;
    esac

    case "$shell" in
      bash) flags="--noprofile --norc" ;;
      zsh) flags="-f" ;;
      *) flags="" ;;
    esac

    local chain=". '$REPO/.prep' && . '$REPO/$entry'"
    local warmup_stderr
    # Warm the cache once (.rc-flux / .rc-kubectl regenerate completion
    # files on first run). Real users hit this once at install time, not
    # every shell startup — the threshold is for the steady state.
    warmup_stderr=$(MYRC_DIR="$REPO" PATH="$stub_dir:$PATH" "$shell" $flags \
      -c "$chain" 2>&1 >/dev/null) || {
      echo "  $shell warmup stderr: $warmup_stderr" >&2
      failures="$failures $shell:warmup"
      continue
    }

    time_s=$(
      MYRC_DIR="$REPO" PATH="$stub_dir:$PATH" /usr/bin/time -p "$shell" $flags \
        -c "$chain" \
        2>&1 >/dev/null | awk '/^real/ {print $2}'
    )
    time_ms=$(awk "BEGIN { printf \"%.0f\", $time_s * 1000 }")

    echo "  $shell ($entry): ${time_ms}ms" >&3

    if [ "$time_ms" -gt "$threshold_ms" ]; then
      failures="$failures $shell:${time_ms}ms"
    fi
  done

  if [ -n "$failures" ]; then
    echo "Exceeded ${threshold_ms}ms threshold:$failures" >&2
    return 1
  fi
}

# Per-plugin smoke: each .rc-* and .env-* must source in under 10ms
# warm (50ms in CI). Matches the README's <10ms target for plugin
# authors. We measure each plugin in isolation after the parent chain
# is loaded, take the min of N runs to drop jitter, and only check
# under bash and zsh — sh/dash don't load .rc-* and .env-* nearly all
# guard-and-return under non-zsh/bash. CI gets a much wider tolerance
# because shared runners spike unpredictably on small workloads.
@test "per-plugin startup time: each .rc/.env under threshold" {
  local threshold_ms=10
  if [ -n "${CI:-}" ]; then
    threshold_ms=50
  fi

  local stub_dir="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$stub_dir"
  cat >"$stub_dir/ssh-agent" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$stub_dir/ssh-agent"

  # Pre-populate $HOME/.ssh/agent.env so .rc-ssh's steady-state branch is
  # exercised (existing agent, kill -0 succeeds) rather than the cold-start
  # branch which forks ssh-agent. SSH_AGENT_PID points at our own bats
  # process so kill -0 always works for the test user.
  mkdir -p "$HOME/.ssh"
  cat >"$HOME/.ssh/agent.env" <<EOF
SSH_AGENT_PID=$$; export SSH_AGENT_PID;
SSH_AUTH_SOCK=/tmp/myrc-test-fake.sock; export SSH_AUTH_SOCK;
EOF
  chmod 600 "$HOME/.ssh/agent.env"

  local shell flags preamble failures="" results
  local runs=3

  for shell in bash zsh; do
    if ! command -v "$shell" >/dev/null 2>&1; then
      echo "skip: $shell not installed" >&3
      continue
    fi

    case "$shell" in
      bash)
        flags="--noprofile --norc"
        preamble=""
        ;;
      zsh)
        flags="-f"
        preamble="zmodload zsh/datetime"
        ;;
    esac

    # Warm caches with one full chain source.
    MYRC_DIR="$REPO" PATH="$stub_dir:$PATH" "$shell" $flags \
      -c "MYRC_DIR='$REPO' . '$REPO/.prep' && . '$REPO/.myrc'" >/dev/null 2>&1

    # Time each plugin individually; print "<name> <ms>" lines.
    # Each plugin is sourced $runs times in a fresh shell and we
    # keep the minimum reading.
    results=$(
      for i in $(seq 1 "$runs"); do
        MYRC_DIR="$REPO" PATH="$stub_dir:$PATH" "$shell" $flags -c "
          $preamble
          . \"\$MYRC_DIR/.prep\"
          for f in \"\$MYRC_DIR\"/.rc-* \"\$MYRC_DIR\"/.env-*; do
            t0=\$EPOCHREALTIME
            . \"\$f\"
            t1=\$EPOCHREALTIME
            awk -v n=\"\${f##*/}\" -v a=\"\$t0\" -v b=\"\$t1\" \
              'BEGIN { printf \"%s %.0f\n\", n, (b - a) * 1000 }'
          done
        " 2>/dev/null
      done | awk '{
        if (!($1 in best) || $2 < best[$1]) best[$1] = $2
      } END {
        for (n in best) print n, best[n]
      }' | sort
    )

    while read -r name ms; do
      [ -n "$name" ] || continue
      echo "  $shell $name: ${ms}ms" >&3
      if [ "$ms" -gt "$threshold_ms" ]; then
        failures="$failures $shell:$name:${ms}ms"
      fi
    done <<<"$results"
  done

  if [ -n "$failures" ]; then
    echo "Exceeded ${threshold_ms}ms threshold:$failures" >&2
    return 1
  fi
}
