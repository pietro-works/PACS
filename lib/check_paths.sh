#!/usr/bin/env bash
# pacs2_alpha/lib/check_paths.sh — Detect dead sync_with paths
#
# For each entry in the registry, verify that every path listed in
# sync_with actually exists on disk. A missing path means a refactor
# moved or deleted the file without updating the registry.
#
# Usage:
#   source lib/check_paths.sh
#   errors=$(pacs_check_paths "$yaml" "$project_dir")

set -euo pipefail

pacs_check_paths() {
  local yaml="${1:?Usage: pacs_check_paths <yaml> <project-dir>}"
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

    # Get sync_with paths
    local paths
    paths=$(printf '%s\n' "$yaml" | yq -r ".\"$code\".sync_with | .[]" 2>/dev/null) || true

    [[ -z "$paths" ]] && continue

    while IFS= read -r path; do
      [[ -z "$path" ]] && continue

      # Resolve relative to project dir
      local full_path="${project_dir%/}/${path}"

      if [[ ! -e "$full_path" ]]; then
        errors+="  DEAD_PATH: $code.sync_with references '$path' but file not found"$'\n'
      fi
    done <<< "$paths"

    # Also check anchor path (extract file part before the colon)
    local anchor
    anchor=$(printf '%s\n' "$yaml" | yq -r ".\"$code\".anchor // \"\"" 2>/dev/null)
    if [[ -n "$anchor" ]]; then
      local anchor_file="${anchor%%:*}"  # Strip :symbol part
      local anchor_full="${project_dir%/}/${anchor_file}"
      if [[ -n "$anchor_file" && ! -e "$anchor_full" ]]; then
        errors+="  DEAD_PATH: $code.anchor references '$anchor_file' but file not found"$'\n'
      fi
    fi
  done <<< "$codes"

  if [[ -n "$errors" ]]; then
    printf '%s' "$errors"
    return 1
  fi
  return 0
}
