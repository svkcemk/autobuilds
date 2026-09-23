#!/usr/bin/env bash
# Performance Benchmark Script
# Tests performance improvements from Phase 1: caching, parallel processing, incremental updates
# Part of the PNC Build Config Generator project

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
BENCHMARK_DIR="./benchmark-results"
TEST_ARTIFACT="org.apache.camel:camel-kafka:4.18.1"
TEST_BOM="org.apache.camel:camel-bom:4.18.1"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Logging
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_benchmark() { echo -e "${CYAN}[BENCHMARK]${NC} $1"; }

# Measure execution time
measure_time() {
  local start_time end_time duration
  start_time=$(date +%s)
  
  "$@"
  
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  echo "$duration"
}

# Format duration
format_duration() {
  local seconds="$1"
  local minutes=$((seconds / 60))
  local remaining_seconds=$((seconds % 60))
  
  if [[ $minutes -gt 0 ]]; then
    echo "${minutes}m ${remaining_seconds}s"
  else
    echo "${seconds}s"
  fi
}

# Run benchmark test
run_benchmark() {
  local test_name="$1"
  local output_dir="$2"
  shift 2
  local args=("$@")
  
  log_benchmark "Running: $test_name"
  
  # Clean output directory
  rm -rf "$output_dir"
  
  # Measure execution time
  local duration
  duration=$(measure_time ./generate_build_configs.sh \
    -a "$TEST_ARTIFACT" \
    -b "$TEST_BOM" \
    -o "$output_dir" \
    --no-pnc-integration \
    "${args[@]}" 2>&1 | tee "$output_dir.log")
  
  # Extract statistics
  local total_deps third_party_deps productized_count pending_count
  total_deps=$(wc -l < "$output_dir/all-dependencies.txt" 2>/dev/null | tr -d ' ' || echo "0")
  third_party_deps=$(wc -l < "$output_dir/third-party-dependencies.txt" 2>/dev/null | tr -d ' ' || echo "0")
  productized_count=$(wc -l < "$output_dir/build-from-source.txt" 2>/dev/null | tr -d ' ' || echo "0")
  pending_count=$(wc -l < "$output_dir/pending-productized.txt" 2>/dev/null | tr -d ' ' || echo "0")
  
  # Display results
  log_success "$test_name completed in $(format_duration $duration)"
  echo "  Total Dependencies: $total_deps"
  echo "  Third-Party Dependencies: $third_party_deps"
  if [[ -f "$output_dir/build-from-source.txt" ]]; then
    echo "  Already Productized: $productized_count"
    echo "  Pending Productization: $pending_count"
  fi
  echo ""
  
  # Return duration
  echo "$duration"
}

# Main benchmark suite
main() {
  log_info "Performance Benchmark Suite"
  log_info "Timestamp: $TIMESTAMP"
  log_info "Test Artifact: $TEST_ARTIFACT"
  log_info "Test BOM: $TEST_BOM"
  echo ""
  
  # Create benchmark directory
  mkdir -p "$BENCHMARK_DIR"
  
  # Results file
  local results_file="$BENCHMARK_DIR/results_${TIMESTAMP}.txt"
  
  {
    echo "Performance Benchmark Results"
    echo "============================="
    echo "Timestamp: $(date)"
    echo "Test Artifact: $TEST_ARTIFACT"
    echo "Test BOM: $TEST_BOM"
    echo ""
  } > "$results_file"
  
  # Test 1: Baseline (no optimizations)
  log_info "Test 1: Baseline (no optimizations)"
  local baseline_duration
  baseline_duration=$(run_benchmark \
    "Baseline" \
    "$BENCHMARK_DIR/test1-baseline" \
    --parallel 1)
  
  {
    echo "Test 1: Baseline (no optimizations)"
    echo "  Duration: $(format_duration $baseline_duration)"
    echo "  Parallel Workers: 1"
    echo "  Caching: Disabled"
    echo "  Incremental: Disabled"
    echo ""
  } >> "$results_file"
  
  # Test 2: Parallel processing (20 workers)
  log_info "Test 2: Parallel processing (20 workers)"
  local parallel_duration
  parallel_duration=$(run_benchmark \
    "Parallel Processing" \
    "$BENCHMARK_DIR/test2-parallel" \
    --parallel 20 \
    --max-parallel 20 \
    --check-productization \
    --redhat-suffix "redhat-*")
  
  local parallel_speedup
  parallel_speedup=$(echo "scale=2; $baseline_duration / $parallel_duration" | bc)
  
  {
    echo "Test 2: Parallel Processing (20 workers)"
    echo "  Duration: $(format_duration $parallel_duration)"
    echo "  Speedup: ${parallel_speedup}x"
    echo "  Parallel Workers: 20"
    echo "  Caching: Disabled"
    echo "  Incremental: Disabled"
    echo ""
  } >> "$results_file"
  
  # Test 3: With caching (first run)
  log_info "Test 3: With caching (first run)"
  
  # Clear cache first
  if [[ -f "lib/cache_manager.sh" ]]; then
    source lib/cache_manager.sh
    clear_all_caches
  fi
  
  local cache_first_duration
  cache_first_duration=$(run_benchmark \
    "Caching (First Run)" \
    "$BENCHMARK_DIR/test3-cache-first" \
    --parallel 20 \
    --max-parallel 20 \
    --use-cache \
    --check-productization \
    --redhat-suffix "redhat-*")
  
  {
    echo "Test 3: Caching (First Run)"
    echo "  Duration: $(format_duration $cache_first_duration)"
    echo "  Parallel Workers: 20"
    echo "  Caching: Enabled (cold cache)"
    echo "  Incremental: Disabled"
    echo ""
  } >> "$results_file"
  
  # Test 4: With caching (second run - cache hit)
  log_info "Test 4: With caching (second run - cache hit)"
  local cache_second_duration
  cache_second_duration=$(run_benchmark \
    "Caching (Second Run)" \
    "$BENCHMARK_DIR/test4-cache-second" \
    --parallel 20 \
    --max-parallel 20 \
    --use-cache \
    --check-productization \
    --redhat-suffix "redhat-*")
  
  local cache_speedup
  cache_speedup=$(echo "scale=2; $cache_first_duration / $cache_second_duration" | bc)
  
  {
    echo "Test 4: Caching (Second Run - Cache Hit)"
    echo "  Duration: $(format_duration $cache_second_duration)"
    echo "  Speedup vs First Run: ${cache_speedup}x"
    echo "  Speedup vs Baseline: $(echo "scale=2; $baseline_duration / $cache_second_duration" | bc)x"
    echo "  Parallel Workers: 20"
    echo "  Caching: Enabled (warm cache)"
    echo "  Incremental: Disabled"
    echo ""
  } >> "$results_file"
  
  # Test 5: Incremental processing (first run)
  log_info "Test 5: Incremental processing (first run)"
  local incremental_first_duration
  incremental_first_duration=$(run_benchmark \
    "Incremental (First Run)" \
    "$BENCHMARK_DIR/test5-incremental-first" \
    --parallel 20 \
    --max-parallel 20 \
    --use-cache \
    --incremental \
    --check-productization \
    --redhat-suffix "redhat-*")
  
  {
    echo "Test 5: Incremental Processing (First Run)"
    echo "  Duration: $(format_duration $incremental_first_duration)"
    echo "  Parallel Workers: 20"
    echo "  Caching: Enabled"
    echo "  Incremental: Enabled (first run)"
    echo ""
  } >> "$results_file"
  
  # Test 6: Incremental processing (second run - no changes)
  log_info "Test 6: Incremental processing (second run - no changes)"
  local incremental_second_duration
  incremental_second_duration=$(run_benchmark \
    "Incremental (Second Run)" \
    "$BENCHMARK_DIR/test5-incremental-first" \
    --parallel 20 \
    --max-parallel 20 \
    --use-cache \
    --incremental \
    --check-productization \
    --redhat-suffix "redhat-*")
  
  local incremental_speedup
  incremental_speedup=$(echo "scale=2; $incremental_first_duration / $incremental_second_duration" | bc)
  
  {
    echo "Test 6: Incremental Processing (Second Run - No Changes)"
    echo "  Duration: $(format_duration $incremental_second_duration)"
    echo "  Speedup vs First Run: ${incremental_speedup}x"
    echo "  Speedup vs Baseline: $(echo "scale=2; $baseline_duration / $incremental_second_duration" | bc)x"
    echo "  Parallel Workers: 20"
    echo "  Caching: Enabled"
    echo "  Incremental: Enabled (no changes)"
    echo ""
  } >> "$results_file"
  
  # Summary
  {
    echo "Summary"
    echo "======="
    echo "Baseline Duration: $(format_duration $baseline_duration)"
    echo ""
    echo "Performance Improvements:"
    echo "  Parallel Processing (20 workers): ${parallel_speedup}x faster"
    echo "  Caching (warm cache): ${cache_speedup}x faster than cold cache"
    echo "  Caching (warm cache): $(echo "scale=2; $baseline_duration / $cache_second_duration" | bc)x faster than baseline"
    echo "  Incremental (no changes): ${incremental_speedup}x faster than first run"
    echo "  Incremental (no changes): $(echo "scale=2; $baseline_duration / $incremental_second_duration" | bc)x faster than baseline"
    echo ""
    echo "Best Case Scenario (incremental + cache):"
    echo "  Duration: $(format_duration $incremental_second_duration)"
    echo "  Speedup: $(echo "scale=2; $baseline_duration / $incremental_second_duration" | bc)x faster than baseline"
    echo ""
  } >> "$results_file"
  
  # Display summary
  echo ""
  log_success "Benchmark completed!"
  echo ""
  cat "$results_file"
  echo ""
  log_info "Full results saved to: $results_file"
  log_info "Logs saved to: $BENCHMARK_DIR/*.log"
  
  # Display cache statistics
  if [[ -f "lib/cache_manager.sh" ]]; then
    echo ""
    log_info "Cache Statistics:"
    source lib/cache_manager.sh
    get_cache_stats
  fi
}

# Run main
main "$@"
