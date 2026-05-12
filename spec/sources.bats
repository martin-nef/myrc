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
  local cmd=". '$REPO/.prep' && . '$REPO/.myenv'"
  case "$shell" in
    bash) "$shell" --noprofile --norc -c "MYRC_DIR='$REPO' $cmd" ;;
    zsh) "$shell" -f -c "MYRC_DIR='$REPO' $cmd" ;;
    *) "$shell" -c "MYRC_DIR='$REPO' $cmd" ;;
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
    if ! source_chain_in "$shell" >/dev/null 2>&1; then
      failures="$failures $shell:source-chain"
    fi
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
