#!/usr/bin/env bash
# test_env_selection.sh - Test environment selection workflow
# Usage: ./test_env_selection.sh

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_test() { echo -e "${BLUE}[TEST]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
  local test_name="$1"
  local test_command="$2"
  local expected_pattern="$3"
  
  log_test "$test_name"
  
  local output
  if output=$(eval "$test_command" 2>&1); then
    if echo "$output" | grep -q "$expected_pattern"; then
      log_pass "$test_name"
      TESTS_PASSED=$((TESTS_PASSED + 1))
      return 0
    else
      log_fail "$test_name - Expected pattern not found: $expected_pattern"
      echo "Output: $output"
      TESTS_FAILED=$((TESTS_FAILED + 1))
      return 1
    fi
  else
    log_fail "$test_name - Command failed"
    echo "Output: $output"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

echo "========================================"
echo "Environment Selection Workflow Tests"
echo "========================================"
echo ""

# Test 1: Environment Parser
log_info "Testing env_parser.sh..."
run_test "Parse environments from env.txt" \
  "./env_parser.sh -i env.txt -o test-env-db.json" \
  "Parsed.*environments"

# Test 2: Query environment database
run_test "Query environment by ID" \
  "jq '.[] | select(.id == \"316\")' test-env-db.json" \
  "\"id\": \"316\""

run_test "Count usable environments" \
  "jq '[.[] | select(.is_usable == true)] | length' test-env-db.json" \
  "^[0-9]"

# Test 3: POM Analyzer
log_info "Testing pom_analyzer.sh..."
run_test "Analyze POM from Maven Central" \
  "./pom_analyzer.sh org.apache.camel camel-core 3.20.0" \
  "\"build_tool\": \"maven\""

# Test 4: Environment Selector
log_info "Testing env_selector.sh..."
run_test "Select environment for Java 11 + Maven 3.6.3" \
  "./env_selector.sh -d test-env-db.json -j 11 -m 3.6.3" \
  "\"id\": \"456\""

run_test "Select environment for Java 17" \
  "./env_selector.sh -d test-env-db.json -j 17" \
  "\"id\":"

run_test "Select environment for Java 8" \
  "./env_selector.sh -d test-env-db.json -j 8 -m 3.5.4" \
  "\"id\":"

# Test 5: Fallback behavior
run_test "Fallback when no Java version specified" \
  "./env_selector.sh -d test-env-db.json -f 316" \
  "\"id\": \"316\""

# Test 6: Integration test - Full workflow
log_info "Testing full workflow..."
cat > test-requirements.json <<'JSON'
{
  "java_version": "11",
  "maven_version": "3.6.3",
  "has_nodejs": false,
  "has_gradle": false,
  "build_tool": "maven"
}
JSON

run_test "Full workflow with requirements file" \
  "./env_selector.sh test-env-db.json test-requirements.json" \
  "\"id\": \"456\""

# Cleanup
rm -f test-env-db.json test-requirements.json

echo ""
echo "========================================"
echo "Test Results"
echo "========================================"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
  log_pass "All tests passed!"
  exit 0
else
  log_fail "Some tests failed"
  exit 1
fi
