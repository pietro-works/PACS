#!/usr/bin/env bash
# pacs2_alpha/lib/check_orphans.sh — Detect orphaned registry rows
#
# An orphaned row is a registry entry (0001-0099 tier) with no matching
# PACS#### tag anywhere in the codebase. The map describes territory
# that doesn't exist.
#
# Usage:
#   source lib/check_orphans.sh
#   errors=$(pacs_check_orphans "$yaml" "$project_dir")

set -euo pipefail

pacs_check_orphans() {
  local yaml="${1:?Usage: pacs_check_orphans <yaml> <project-dir>}"
  local project_dir="${2:?}"
  local errors=""

  local codes
  codes=$(printf '%s\n' "$yaml" | yq -r '(. // {}) | keys | .[]' 2>/dev/null) || return 0

  [[ -z "$codes" ]] && return 0

  while IFS= read -r code; do
    # Skip retired entries
    local retired
    retired=$(printf '%s\n' "$yaml" | yq -r ".\"$code\".retired // false" 2>/dev/null)
    [[ "$retired" == "true" ]] && continue

    # Extract the numeric part
    local num="${code#PACS}"
    # 0100+ tier = process rules, no code anchor expected.
    # 10# forces base 10 — codes are zero-padded and 0008/0009 are not valid octal.
    if (( 10#$num >= 100 )); then
      continue
    fi

    # Search for the tag in source files (excluding AGENTS.md itself,
    # .git, node_modules, and common non-source dirs)
    local hits
    hits=$(rg -l --fixed-strings "$code" \
      --glob '!AGENTS.md' \
      --glob '!.git' \
      --glob '!node_modules' \
      --glob '!pacs2_alpha' \
      "$project_dir" 2>/dev/null | head -1) || true

    if [[ -z "$hits" ]]; then
      errors+="  ORPHAN: $code exists in registry but no tag found in codebase"$'\n'
    fi
  done <<< "$codes"

  if [[ -n "$errors" ]]; then
    printf '%s' "$errors"
    return 1
  fi
  return 0
}
