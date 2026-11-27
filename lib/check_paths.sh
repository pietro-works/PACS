#!/usr/bin/env bash
# lib/check_paths.sh — Detect dead anchor and sync_with paths
#
# Every anchor and sync_with item of a live entry must name a file that exists.
# Text after the first colon is a symbol ("src/a.js:UNITS" checks src/a.js),
# and an item holding <...> is a placeholder ("runs/<run>/rubric.md"): skipped.
#
# Usage:
#   source lib/check_paths.sh
#   errors=$(pacs_check_paths "$yaml" "$project_dir")

set -euo pipefail

pacs_check_paths() {
  local yaml="${1:?Usage: pacs_check_paths <yaml> <project-dir>}"
  local project_dir="${2:?}"
  local errors="" where item file items

  items=$(printf '%s\n' "$yaml" | yq -r '(. // {}) | to_entries[] | select(.value.retired != true) | .key as $k
    | (($k + ".anchor\t" + (.value.anchor // "")), ((.value.sync_with // [])[] | $k + ".sync_with\t" + .))' 2>/dev/null) || return 0

  while IFS=$'\t' read -r where item; do
    [[ -z "$item" || "$item" == *"<"* ]] && continue
    file="${item%%:*}"
    [[ -z "$file" || -e "${project_dir%/}/${file}" ]] && continue
    errors+="  DEAD_PATH: $where references '$file' but file not found"$'\n'
  done <<< "$items"

  if [[ -n "$errors" ]]; then
    printf '%s' "$errors"
    return 1
  fi
  return 0
}
