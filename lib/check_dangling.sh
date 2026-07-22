#!/usr/bin/env bash
# pacs2_alpha/lib/check_dangling.sh — Detect dangling tags in the codebase
#
# A dangling tag is a PACS#### comment in the source code that has no
# matching entry in the registry. The territory has a marker the map
# doesn't know about.
#
# Usage:
#   source lib/check_dangling.sh
#   errors=$(pacs_check_dangling "$yaml" "$project_dir")

set -euo pipefail

pacs_check_dangling() {
  local yaml="${1:?Usage: pacs_check_dangling <yaml> <project-dir>}"
  local project_dir="${2:?}"
  local errors=""

  # Find all PACS#### tags in the codebase
  local tags_in_code
  tags_in_code=$(rg -o --no-filename '\bPACS[0-9]{4}\b' \
    --glob '!AGENTS.md' \
    --glob '!.git' \
    --glob '!node_modules' \
    --glob '!pacs2_alpha' \
    "$project_dir" 2>/dev/null | sort -u) || true

  [[ -z "$tags_in_code" ]] && return 0

  # Get all codes in registry
  local registry_codes
  registry_codes=$(printf '%s\n' "$yaml" | yq -r '(. // {}) | keys | .[]' 2>/dev/null | sort -u) || true

  # Find tags in code that are NOT in registry
  while IFS= read -r tag; do
    if ! printf '%s\n' "$registry_codes" | grep -qxF "$tag"; then
      # Find which file(s) contain this dangling tag
      local files
      files=$(rg -l --fixed-strings "$tag" \
        --glob '!AGENTS.md' \
        --glob '!.git' \
        --glob '!node_modules' \
        --glob '!pacs2_alpha' \
        "$project_dir" 2>/dev/null | head -3) || true
      errors+="  DANGLING: $tag found in code but missing from registry"
      if [[ -n "$files" ]]; then
        errors+=" (in: $(echo "$files" | tr '\n' ', ' | sed 's/,$//'))"
      fi
      errors+=$'\n'
    fi
  done <<< "$tags_in_code"

  if [[ -n "$errors" ]]; then
    printf '%s' "$errors"
    return 1
  fi
  return 0
}
