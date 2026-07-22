#!/usr/bin/env bash
# pacs2_alpha/lib/validate.sh — Schema validation for PACS YAML registry
#
# Validates each entry has:
#   - Key matching PACS\d{4}
#   - Required fields: anchor, sync_with, fails_silently, justification
#   - sync_with is an array
#   - justification has meaningful length (>20 chars)
#
# Usage:
#   source lib/validate.sh
#   errors=$(pacs_validate_schema "$yaml")

set -euo pipefail

pacs_validate_schema() {
  local yaml="${1:?Usage: pacs_validate_schema <yaml-string>}"
  local errors=""
  local code

  # Get all top-level keys
  local codes
  codes=$(printf '%s\n' "$yaml" | yq -r '(. // {}) | keys | .[]' 2>/dev/null) || {
    echo "error: failed to parse YAML registry"
    return 1
  }

  if [[ -z "$codes" ]]; then
    # Empty registry — valid, nothing to check.
    return 0
  fi

  while IFS= read -r code; do
    # Check key format: must be PACS followed by exactly 4 digits
    if ! [[ "$code" =~ ^PACS[0-9]{4}$ ]]; then
      errors+="  SCHEMA: key '$code' does not match PACS####"$'\n'
      continue
    fi

    # Skip retired entries
    local retired
    retired=$(printf '%s\n' "$yaml" | yq -r ".\"$code\".retired // false" 2>/dev/null)
    if [[ "$retired" == "true" ]]; then
      continue
    fi

    # Check required fields
    local field
    for field in anchor fails_silently justification; do
      local val
      val=$(printf '%s\n' "$yaml" | yq -r ".\"$code\".\"$field\" // \"\"" 2>/dev/null)
      if [[ -z "$val" ]]; then
        errors+="  SCHEMA: $code missing required field '$field'"$'\n'
      fi
    done

    # Check sync_with exists and is an array
    local sw_type
    sw_type=$(printf '%s\n' "$yaml" | yq -r ".\"$code\".sync_with | type" 2>/dev/null)
    if [[ "$sw_type" != "!!seq" ]]; then
      errors+="  SCHEMA: $code.sync_with must be an array (got $sw_type)"$'\n'
    fi

    # Check justification is not hollow (>20 chars, not generic)
    local justification
    justification=$(printf '%s\n' "$yaml" | yq -r ".\"$code\".justification // \"\"" 2>/dev/null)
    if [[ ${#justification} -le 20 && -n "$justification" ]]; then
      errors+="  SCHEMA: $code.justification too short (${#justification} chars, need >20)"$'\n'
    fi

  done <<< "$codes"

  if [[ -n "$errors" ]]; then
    printf '%s' "$errors"
    return 1
  fi
  return 0
}
