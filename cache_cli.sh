#!/usr/bin/env bash
# Cache Management CLI Tool
# Provides command-line interface for cache operations
# Part of the PNC Build Config Generator performance optimization

set -euo pipefail

# Source cache manager
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/cache_manager.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Show usage
show_usage() {
  cat <<'USAGE'
Cache Management CLI

Manage the autobuilder cache for improved performance.

Usage:
  ./cache_cli.sh <command> [options]

Commands:
  stats                   Show cache statistics
  clear [type]           Clear cache (all or specific type)
  cleanup [hours]        Remove cache entries older than N hours
  init                   Initialize cache directory structure
  test                   Test cache functionality
  
Cache Types:
  maven/poms             Maven POM files
  maven/trees            Maven dependency trees
  pnc/queries            PNC query results
  pnc/build-configs      PNC build configurations
  scm/resolutions        SCM URL/revision resolutions
  productization/checks  Productization check results

Examples:
  # Show cache statistics
  ./cache_cli.sh stats
  
  # Clear all cache
  ./cache_cli.sh clear
  
  # Clear only Maven cache
  ./cache_cli.sh clear maven/poms
  
  # Remove entries older than 48 hours
  ./cache_cli.sh cleanup 48
  
  # Test cache functionality
  ./cache_cli.sh test

USAGE
}

# Show cache statistics
cmd_stats() {
  echo -e "${BLUE}=== Cache Statistics ===${NC}"
  echo ""
  cache_stats
}

# Clear cache
cmd_clear() {
  local cache_type="${1:-}"
  
  if [[ -z "$cache_type" ]]; then
    echo -e "${YELLOW}Warning: This will clear ALL cache data.${NC}"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Cancelled."
      return 0
    fi
    
    cache_clear_all
    echo -e "${GREEN}✓ All cache cleared${NC}"
  else
    cache_clear_type "$cache_type"
    echo -e "${GREEN}✓ Cleared $cache_type cache${NC}"
  fi
}

# Cleanup old cache entries
cmd_cleanup() {
  local max_age_hours="${1:-24}"
  local max_age_seconds=$((max_age_hours * 3600))
  
  echo -e "${BLUE}Cleaning cache entries older than $max_age_hours hours...${NC}"
  
  local deleted
  deleted=$(cache_cleanup "$max_age_seconds")
  
  echo -e "${GREEN}✓ Removed $deleted old cache entries${NC}"
}

# Initialize cache
cmd_init() {
  echo -e "${BLUE}Initializing cache...${NC}"
  init_cache true
  echo -e "${GREEN}✓ Cache initialized at $CACHE_DIR${NC}"
}

# Test cache functionality
cmd_test() {
  echo -e "${BLUE}=== Testing Cache Functionality ===${NC}"
  echo ""
  
  # Test 1: Basic put/get
  echo -n "Test 1: Basic put/get... "
  local test_key="test_key_$$"
  local test_content="test content $(date)"
  
  cache_put "maven/poms" "$test_key" "$test_content"
  local retrieved
  retrieved=$(cache_get "maven/poms" "$test_key" 3600)
  
  if [[ "$retrieved" == "$test_content" ]]; then
    echo -e "${GREEN}✓ PASS${NC}"
  else
    echo -e "${RED}✗ FAIL${NC}"
    return 1
  fi
  
  # Test 2: Cache expiration
  echo -n "Test 2: Cache expiration... "
  cache_put "maven/poms" "${test_key}_expire" "expire test"
  sleep 2
  
  if cache_get "maven/poms" "${test_key}_expire" 1; then
    echo -e "${RED}✗ FAIL (should have expired)${NC}"
    return 1
  else
    echo -e "${GREEN}✓ PASS${NC}"
  fi
  
  # Test 3: File caching
  echo -n "Test 3: File caching... "
  local test_file
  test_file=$(mktemp)
  echo "test file content" > "$test_file"
  
  cache_put_file "maven/trees" "${test_key}_file" "$test_file"
  
  local retrieved_file
  retrieved_file=$(mktemp)
  if cache_get_file "maven/trees" "${test_key}_file" "$retrieved_file" 3600; then
    if diff -q "$test_file" "$retrieved_file" > /dev/null; then
      echo -e "${GREEN}✓ PASS${NC}"
    else
      echo -e "${RED}✗ FAIL (content mismatch)${NC}"
      rm -f "$test_file" "$retrieved_file"
      return 1
    fi
  else
    echo -e "${RED}✗ FAIL (file not found)${NC}"
    rm -f "$test_file" "$retrieved_file"
    return 1
  fi
  
  rm -f "$test_file" "$retrieved_file"
  
  # Test 4: Helper functions
  echo -n "Test 4: Helper functions... "
  cache_maven_pom "org.example" "test-artifact" "1.0.0" "<pom>test</pom>"
  
  if get_cached_maven_pom "org.example" "test-artifact" "1.0.0" > /dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
  else
    echo -e "${RED}✗ FAIL${NC}"
    return 1
  fi
  
  # Test 5: SCM resolution caching
  echo -n "Test 5: SCM resolution caching... "
  cache_scm_resolution "org.example" "test-artifact" "1.0.0" \
    "https://github.com/example/test.git" "v1.0.0"
  
  local scm_result
  scm_result=$(get_cached_scm_resolution "org.example" "test-artifact" "1.0.0")
  
  if echo "$scm_result" | grep -q "SCM_URL=https://github.com/example/test.git"; then
    echo -e "${GREEN}✓ PASS${NC}"
  else
    echo -e "${RED}✗ FAIL${NC}"
    return 1
  fi
  
  # Cleanup test data
  cache_clear_type "maven/poms"
  cache_clear_type "maven/trees"
  
  echo ""
  echo -e "${GREEN}✓ All tests passed${NC}"
}

# Main command dispatcher
main() {
  local command="${1:-}"
  
  if [[ -z "$command" ]]; then
    show_usage
    exit 1
  fi
  
  case "$command" in
    stats)
      cmd_stats
      ;;
    clear)
      shift
      cmd_clear "$@"
      ;;
    cleanup)
      shift
      cmd_cleanup "$@"
      ;;
    init)
      cmd_init
      ;;
    test)
      cmd_test
      ;;
    help|--help|-h)
      show_usage
      ;;
    *)
      echo -e "${RED}Error: Unknown command: $command${NC}" >&2
      echo ""
      show_usage
      exit 1
      ;;
  esac
}

main "$@"
