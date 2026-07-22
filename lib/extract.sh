#!/usr/bin/env bash
# pacs2_alpha/lib/extract.sh — Extract the YAML registry from AGENTS.md
#
# Finds the first ```yaml fenced block under a "## PACS Registry" heading
# and prints its contents to stdout. Returns exit 1 if no block found.
#
# Usage:
#   source lib/extract.sh
#   yaml_content=$(pacs_extract_yaml "$PROJECT_DIR/AGENTS.md")

set -euo pipefail

pacs_extract_yaml() {
  local registry_file="${1:?Usage: pacs_extract_yaml <path-to-AGENTS.md>}"

  if [[ ! -f "$registry_file" ]]; then
    echo "error: registry file not found: $registry_file" >&2
    return 1
  fi

  # Extract YAML between ```yaml and ``` fences that appear after a
  # "## PACS Registry" heading. awk is more reliable than sed for
  # stateful multiline extraction.
  local yaml
  yaml=$(awk '
    /^##[[:space:]]+PACS[[:space:]]+Registry/ { in_section = 1; next }
    in_section && /^##/ { in_section = 0; next }
    in_section && /^```yaml/ { in_block = 1; next }
    in_section && in_block && /^```/ { in_block = 0; in_section = 0; next }
    in_block { print }
  ' "$registry_file")

  if [[ -z "$yaml" ]]; then
    # No YAML block found — might be a markdown-table-only registry or empty.
    # Return empty string (not an error) so callers can distinguish
    # "no YAML block" from "file not found".
    return 0
  fi

  printf '%s\n' "$yaml"
}

# List all PACS codes from the extracted YAML.
# Output: one code per line (e.g., PACS0001)
pacs_list_codes() {
  local yaml="${1:?Usage: pacs_list_codes <yaml-string>}"
  printf '%s\n' "$yaml" | yq -r '(. // {}) | keys | .[]' 2>/dev/null
}

# Get a specific field from a specific code.
# Usage: pacs_get_field "$yaml" "PACS0001" "anchor"
pacs_get_field() {
  local yaml="$1" code="$2" field="$3"
  printf '%s\n' "$yaml" | yq -r ".\"$code\".\"$field\" // \"\"" 2>/dev/null
}

# Get the sync_with array as newline-separated paths.
# Usage: pacs_get_sync_with "$yaml" "PACS0001"
pacs_get_sync_with() {
  local yaml="$1" code="$2"
  printf '%s\n' "$yaml" | yq -r ".\"$code\".sync_with | .[]" 2>/dev/null || true
}
