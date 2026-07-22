#!/usr/bin/env bash
# test/run_tests.sh — Test suite for PACS

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACS_BIN="${TEST_DIR}/../bin/pacs"

PASSED=0
FAILED=0

assert_exit_code() {
  local name="$1"
  local expected_code="$2"
  shift 2
  local actual_code=0
  local output
  output=$("$PACS_BIN" "$@" 2>&1) || actual_code=$?

  if [[ "$actual_code" -eq "$expected_code" ]]; then
    echo "  ✓ [PASS] $name (exit code $actual_code matches expected $expected_code)"
    PASSED=$((PASSED + 1))
  else
    echo "  ✗ [FAIL] $name (expected exit code $expected_code, got $actual_code)"
    echo "    Output:"
    echo "$output" | sed 's/^/      /'
    FAILED=$((FAILED + 1))
  fi
}

assert_output_contains() {
  local name="$1"
  local substring="$2"
  shift 2
  local output
  output=$("$PACS_BIN" "$@" 2>&1) || true

  if echo "$output" | grep -qF "$substring"; then
    echo "  ✓ [PASS] $name (output contains '$substring')"
    PASSED=$((PASSED + 1))
  else
    echo "  ✗ [FAIL] $name (output missing expected string '$substring')"
    echo "    Output:"
    echo "$output" | sed 's/^/      /'
    FAILED=$((FAILED + 1))
  fi
}

echo "=== PACS Test Suite ==="
echo ""

# Test 1: Clean fixture should pass completely (exit 0)
assert_exit_code "Clean fixture passes all checks" 0 check --project-dir "${TEST_DIR}/fixture_clean"

# Test 2: Fixture with issues should fail (exit 1)
assert_exit_code "Fixture with issues fails check" 1 check --project-dir "${TEST_DIR}/fixture"

# Test 3: Fixture with issues reports orphaned row PACS0002
assert_output_contains "Detects orphaned row PACS0002" "ORPHAN: PACS0002" check --project-dir "${TEST_DIR}/fixture"

# Test 4: Fixture with issues reports dangling tag PACS9999
assert_output_contains "Detects dangling tag PACS9999" "DANGLING: PACS9999" check --project-dir "${TEST_DIR}/fixture"

# Test 5: Fixture with issues reports dead path
assert_output_contains "Detects dead path" "DEAD_PATH: PACS0002" check --project-dir "${TEST_DIR}/fixture"

# Test 6: Fixture with issues reports hollow justification
assert_output_contains "Detects hollow justification" "HOLLOW: PACS0003" check --project-dir "${TEST_DIR}/fixture"

# Test 7: Fixture with issues reports verify failure
assert_output_contains "Detects verify failure" "VERIFY: PACS0004 FAILED" check --project-dir "${TEST_DIR}/fixture"

# Test 8: pacs extract on clean fixture
assert_output_contains "Extract command returns valid YAML key" "PACS0001:" extract --project-dir "${TEST_DIR}/fixture_clean"

# Test 9: pacs report command
assert_output_contains "Report command lists active counts" "Active:" report --project-dir "${TEST_DIR}/fixture"

echo ""
echo "=== Test Summary ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
exit 0
