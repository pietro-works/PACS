#!/usr/bin/env bash
# pacs2_alpha/lib/check_verify.sh — Run executable predicates
#
# For entries with a `verify:` field, run the script.
# Exit 0 = pass, non-zero = fail.
# Times out after 30 seconds per script.
#
# Usage:
#   source lib/check_verify.sh
#   errors=$(pacs_check_verify "$yaml" "$project_dir")

set -euo pipefail

run_with_timeout() {
  local timeout_sec="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_sec" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$timeout_sec" "$@"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import subprocess, sys; sys.exit(subprocess.run(sys.argv[2:], timeout=float(sys.argv[1])).returncode)" "$timeout_sec" "$@"
  else
    "$@"
  fi
}

pacs_check_verify() {
  local yaml="${1:?Usage: pacs_check_verify <yaml> <project-dir>}"
  local project_dir="${2:?}"
  local errors=""
  local ran=0
  local passed=0

  local codes
  codes=$(printf '%s\n' "$yaml" | yq -r '(. // {}) | keys | .[]' 2>/dev/null) || return 0

  [[ -z "$codes" ]] && return 0

  while IFS= read -r code; do
    # Skip retired entries
    local retired
    retired=$(printf '%s\n' "$yaml" | yq -r ".\"$code\".retired // false" 2>/dev/null)
    [[ "$retired" == "true" ]] && continue

    # Get verify command
    local verify_cmd
    verify_cmd=$(printf '%s\n' "$yaml" | yq -r ".\"$code\".verify // \"\"" 2>/dev/null)
    [[ -z "$verify_cmd" ]] && continue

    ran=$((ran + 1))

    # Run with timeout
    local output
    local exit_code=0
    output=$(cd "$project_dir" && run_with_timeout "$PACS_VERIFY_TIMEOUT" bash -c "$verify_cmd" 2>&1) || exit_code=$?

    if [[ $exit_code -eq 127 ]]; then
      errors+="  VERIFY: $code command not found (exit 127): $verify_cmd"$'\n'
    elif [[ $exit_code -eq 124 ]]; then
      errors+="  VERIFY: $code timed out after ${PACS_VERIFY_TIMEOUT}s: $verify_cmd"$'\n'
    elif [[ $exit_code -ne 0 ]]; then
      errors+="  VERIFY: $code FAILED (exit $exit_code): $verify_cmd"$'\n'
      if [[ -n "$output" ]]; then
        # Indent output for readability
        errors+="$(printf '%s\n' "$output" | sed 's/^/          /')"$'\n'
      fi
    else
      passed=$((passed + 1))
    fi
  done <<< "$codes"

  # Summary line to stderr (informational, not errors)
  if [[ $ran -gt 0 ]]; then
    echo "  verify: $passed/$ran predicates passed" >&2
  fi

  if [[ -n "$errors" ]]; then
    printf '%s' "$errors"
    return 1
  fi
  return 0
}
