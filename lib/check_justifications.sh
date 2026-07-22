#!/usr/bin/env bash
# pacs2_alpha/lib/check_justifications.sh — Detect hollow justifications
#
# A hollow justification is one that says nothing specific to this coupling:
# generic language that could be pasted into any row without editing.
# This is drift too — a code without a real justification hasn't earned
# its place (SPEC §9).
#
# Usage:
#   source lib/check_justifications.sh
#   errors=$(pacs_check_justifications "$yaml")

set -euo pipefail

# Known-generic phrases that signal a hollow justification.
# These are case-insensitive substring matches.
GENERIC_PATTERNS=(
  "this is important"
  "could break things"
  "needs to be in sync"
  "must be kept in sync"
  "important to keep"
  "should be updated"
  "keep updated"
  "needs updating"
  "may cause issues"
  "might cause problems"
  "could cause bugs"
)

pacs_check_justifications() {
  local yaml="${1:?Usage: pacs_check_justifications <yaml-string>}"
  local errors=""

  local codes
  codes=$(printf '%s\n' "$yaml" | yq -r '(. // {}) | keys | .[]' 2>/dev/null) || return 0

  [[ -z "$codes" ]] && return 0

  while IFS= read -r code; do
    # Skip retired entries
    local retired
    retired=$(printf '%s\n' "$yaml" | yq -r ".\"$code\".retired // false" 2>/dev/null)
    [[ "$retired" == "true" ]] && continue

    local justification
    justification=$(printf '%s\n' "$yaml" | yq -r ".\"$code\".justification // \"\"" 2>/dev/null)

    if [[ -z "$justification" ]]; then
      # Missing justification is caught by validate.sh; skip here.
      continue
    fi

    # Check minimum length
    if [[ ${#justification} -le 20 ]]; then
      errors+="  HOLLOW: $code.justification too terse (${#justification} chars): \"$justification\""$'\n'
      continue
    fi

    # Check against generic patterns
    local lower_just
    lower_just=$(printf '%s' "$justification" | tr '[:upper:]' '[:lower:]')

    local pattern
    for pattern in "${GENERIC_PATTERNS[@]}"; do
      if [[ "$lower_just" == *"$pattern"* ]]; then
        errors+="  HOLLOW: $code.justification matches generic pattern '$pattern': \"$justification\""$'\n'
        break
      fi
    done
  done <<< "$codes"

  if [[ -n "$errors" ]]; then
    printf '%s' "$errors"
    return 1
  fi
  return 0
}
