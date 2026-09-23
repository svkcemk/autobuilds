#!/usr/bin/env bash
# Parallel Processor Library
# Provides parallel processing utilities for productization checks and other operations
# Part of Phase 1: Performance Optimization

set -euo pipefail

# Default configuration
MAX_PARALLEL_WORKERS="${MAX_PARALLEL_WORKERS:-20}"
PARALLEL_TIMEOUT="${PARALLEL_TIMEOUT:-5}"
PARALLEL_RETRY_COUNT="${PARALLEL_RETRY_COUNT:-2}"

# Check if GNU parallel is available
HAS_GNU_PARALLEL=false
if command -v parallel &> /dev/null; then
  HAS_GNU_PARALLEL=true
fi

# Process items in parallel using background jobs
# Args: worker_function max_workers input_file output_dir
# The worker_function should accept: item_line output_dir worker_id
parallel_process_file() {
  local worker_function="$1"
  local max_workers="$2"
  local input_file="$3"
  local output_dir="$4"
  
  mkdir -p "$output_dir"
  
  local total_items
  total_items=$(wc -l < "$input_file" | tr -d ' ')
  
  if [[ $total_items -eq 0 ]]; then
    echo "[INFO] No items to process" >&2
    return 0
  fi
  
  echo "[INFO] Processing $total_items items with $max_workers parallel workers..." >&2
  
  local current_jobs=0
  local processed=0
  local worker_id=0
  
  while IFS= read -r item || [[ -n "$item" ]]; do
    [[ -z "$item" ]] && continue
    
    worker_id=$((worker_id + 1))
    
    # Launch background job
    (
      "$worker_function" "$item" "$output_dir" "$worker_id"
    ) &
    
    current_jobs=$((current_jobs + 1))
    processed=$((processed + 1))
    
    # Show progress
    if [[ $((processed % 10)) -eq 0 ]] || [[ $processed -eq $total_items ]]; then
      local progress_pct=$((processed * 100 / total_items))
      printf "\r[%3d%%] Processing %d/%d (active workers: %d)    " "$progress_pct" "$processed" "$total_items" "$current_jobs" >&2
    fi
    
    # Portable worker throttle (bash 3 compatible — 'wait -n' is bash 4+ only)
    while [[ $(jobs -rp | wc -l | tr -d ' ') -ge $max_workers ]]; do
      sleep 0.2
    done
    current_jobs=$(jobs -rp | wc -l | tr -d ' ')
  done < "$input_file"
  
  # Wait for remaining jobs
  wait
  
  printf "\r%-80s\r" "" >&2
  echo "[INFO] Completed processing $total_items items" >&2
}

# Parallel productization check worker
# Args: gav output_dir worker_id
parallel_productization_worker() {
  local gav="$1"
  local output_dir="$2"
  local worker_id="$3"
  
  local group_id artifact_id version
  group_id="$(echo "$gav" | cut -d: -f1)"
  artifact_id="$(echo "$gav" | cut -d: -f2)"
  version="$(echo "$gav" | cut -d: -f3)"
  
  # Check cache first if cache_manager is available
  if declare -f get_cached_productization_status &>/dev/null; then
    local cached_status
    if cached_status=$(get_cached_productization_status "$gav" "${REDHAT_SUFFIX:-redhat-*}" 2>/dev/null); then
      local productized
      productized=$(echo "$cached_status" | jq -r '.productized' 2>/dev/null || echo "false")
      
      if [[ "$productized" == "true" ]]; then
        local productized_version
        productized_version=$(echo "$cached_status" | jq -r '.productized_version' 2>/dev/null || echo "")
        echo "$group_id:$artifact_id:$productized_version" >> "$output_dir/productized.txt.tmp"
      else
        echo "$gav" >> "$output_dir/pending.txt.tmp"
      fi
      return 0
    fi
  fi
  
  # Check productization status
  local found=false
  local found_version=""
  local repository=""
  
  # Repository URLs to check (in priority order)
  local repos=(
    "https://indy.corp.redhat.com/api/content/maven/hosted/pnc-builds"
    "https://indy.psi.redhat.com/api/content/maven/group/builds-untested+shared-imports+public"
  )
  
  # Handle wildcard suffix
  local suffix_pattern="${REDHAT_SUFFIX:-redhat-*}"
  
  if [[ "$suffix_pattern" == "redhat-*" ]]; then
    # Try common redhat suffixes
    for suffix_num in 00001 00002 00003 00004 00005 0001 0002 0003 0004 0005; do
      local test_version="${version}.redhat-${suffix_num}"
      
      for repo_url in "${repos[@]}"; do
        local test_url="${repo_url}/${group_id//.//}/${artifact_id}/${test_version}/${artifact_id}-${test_version}.pom"
        
        if curl -s -f -m "$PARALLEL_TIMEOUT" -I "$test_url" > /dev/null 2>&1; then
          found=true
          found_version="$test_version"
          repository=$(echo "$repo_url" | sed 's|.*/||')
          break 2
        fi
      done
    done
  else
    # Exact suffix match
    local redhat_version="${version}.${suffix_pattern}"
    
    for repo_url in "${repos[@]}"; do
      local test_url="${repo_url}/${group_id//.//}/${artifact_id}/${redhat_version}/${artifact_id}-${redhat_version}.pom"
      
      if curl -s -f -m "$PARALLEL_TIMEOUT" -I "$test_url" > /dev/null 2>&1; then
        found=true
        found_version="$redhat_version"
        repository=$(echo "$repo_url" | sed 's|.*/||')
        break
      fi
    done
  fi
  
  # Cache the result if cache_manager is available
  if declare -f cache_productization_status &>/dev/null; then
    if [[ "$found" == "true" ]]; then
      cache_productization_status "$gav" "$suffix_pattern" "true" "$found_version" "$repository" 2>/dev/null || true
    else
      cache_productization_status "$gav" "$suffix_pattern" "false" "" "" 2>/dev/null || true
    fi
  fi
  
  # Write result to temporary files (thread-safe with unique worker files)
  if [[ "$found" == "true" ]]; then
    echo "$group_id:$artifact_id:$found_version" >> "$output_dir/productized.${worker_id}.tmp"
  else
    echo "$gav" >> "$output_dir/pending.${worker_id}.tmp"
  fi
}

# Parallel productization check
# Args: deps_file redhat_suffix output_dir max_workers
# Returns: Creates productized.txt and pending.txt in output_dir
parallel_productization_check() {
  local deps_file="$1"
  local redhat_suffix="$2"
  local output_dir="$3"
  local max_workers="${4:-$MAX_PARALLEL_WORKERS}"
  
  export REDHAT_SUFFIX="$redhat_suffix"
  export PARALLEL_TIMEOUT
  
  # Clean up old temporary files
  rm -f "$output_dir"/productized.*.tmp "$output_dir"/pending.*.tmp
  
  # Process in parallel
  parallel_process_file parallel_productization_worker "$max_workers" "$deps_file" "$output_dir"
  
  # Consolidate results from worker files
  : > "$output_dir/productized.txt"
  : > "$output_dir/pending.txt"
  
  # Merge productized results
  if ls "$output_dir"/productized.*.tmp 1> /dev/null 2>&1; then
    cat "$output_dir"/productized.*.tmp | sort -u > "$output_dir/productized.txt"
    rm -f "$output_dir"/productized.*.tmp
  fi
  
  # Merge pending results
  if ls "$output_dir"/pending.*.tmp 1> /dev/null 2>&1; then
    cat "$output_dir"/pending.*.tmp | sort -u > "$output_dir/pending.txt"
    rm -f "$output_dir"/pending.*.tmp
  fi
  
  local productized_count pending_count
  productized_count=$(wc -l < "$output_dir/productized.txt" 2>/dev/null | tr -d ' ' || echo "0")
  pending_count=$(wc -l < "$output_dir/pending.txt" 2>/dev/null | tr -d ' ' || echo "0")
  
  echo "[INFO] Productization check complete:" >&2
  echo "[INFO]   Already productized: $productized_count" >&2
  echo "[INFO]   Pending productization: $pending_count" >&2
  
  # Return counts
  echo "$productized_count:$pending_count"
}

# Parallel SCM resolution worker
# Args: gav output_dir worker_id
parallel_scm_worker() {
  local gav="$1"
  local output_dir="$2"
  local worker_id="$3"
  
  local group_id artifact_id version
  group_id="$(echo "$gav" | cut -d: -f1)"
  artifact_id="$(echo "$gav" | cut -d: -f2)"
  version="$(echo "$gav" | cut -d: -f3)"
  
  # Check cache first if cache_manager is available
  if declare -f get_cached_scm &>/dev/null; then
    if cached_scm=$(get_cached_scm "$gav" 2>/dev/null); then
      echo "$cached_scm" > "$output_dir/scm.${worker_id}.tmp"
      echo "$gav" >> "$output_dir/resolved.${worker_id}.tmp"
      return 0
    fi
  fi
  
  # Resolve SCM (requires resolve_scm function from scm_resolver.sh)
  if declare -f resolve_scm &>/dev/null; then
    local scm_data
    if scm_data=$(resolve_scm "$group_id" "$artifact_id" "$version" 2>&1); then
      echo "$scm_data" > "$output_dir/scm.${worker_id}.tmp"
      echo "$gav" >> "$output_dir/resolved.${worker_id}.tmp"
      
      # Cache the result if cache_manager is available
      if declare -f cache_scm &>/dev/null; then
        local scm_url scm_revision scm_source
        scm_url="$(echo "$scm_data" | awk -F= '/^SCM_URL=/{print substr($0,9)}')"
        scm_revision="$(echo "$scm_data" | awk -F= '/^SCM_REVISION=/{print substr($0,14)}')"
        scm_source="$(echo "$scm_data" | awk -F= '/^SCM_SOURCE=/{print substr($0,12)}')"
        cache_scm "$gav" "$scm_url" "$scm_revision" "$scm_source" 2>/dev/null || true
      fi
    else
      echo "$gav" >> "$output_dir/unresolved.${worker_id}.tmp"
    fi
  else
    echo "[WARN] resolve_scm function not available" >&2
    echo "$gav" >> "$output_dir/unresolved.${worker_id}.tmp"
  fi
}

# Parallel SCM resolution
# Args: deps_file output_dir max_workers
# Returns: Creates resolved.txt and unresolved.txt in output_dir
parallel_scm_resolution() {
  local deps_file="$1"
  local output_dir="$2"
  local max_workers="${3:-$MAX_PARALLEL_WORKERS}"
  
  # Clean up old temporary files
  rm -f "$output_dir"/scm.*.tmp "$output_dir"/resolved.*.tmp "$output_dir"/unresolved.*.tmp
  
  # Process in parallel
  parallel_process_file parallel_scm_worker "$max_workers" "$deps_file" "$output_dir"
  
  # Consolidate results
  : > "$output_dir/resolved.txt"
  : > "$output_dir/unresolved.txt"
  
  if ls "$output_dir"/resolved.*.tmp 1> /dev/null 2>&1; then
    cat "$output_dir"/resolved.*.tmp | sort -u > "$output_dir/resolved.txt"
    rm -f "$output_dir"/resolved.*.tmp
  fi
  
  if ls "$output_dir"/unresolved.*.tmp 1> /dev/null 2>&1; then
    cat "$output_dir"/unresolved.*.tmp | sort -u > "$output_dir/unresolved.txt"
    rm -f "$output_dir"/unresolved.*.tmp
  fi
  
  # Clean up SCM temp files
  rm -f "$output_dir"/scm.*.tmp
  
  local resolved_count unresolved_count
  resolved_count=$(wc -l < "$output_dir/resolved.txt" 2>/dev/null | tr -d ' ' || echo "0")
  unresolved_count=$(wc -l < "$output_dir/unresolved.txt" 2>/dev/null | tr -d ' ' || echo "0")
  
  echo "[INFO] SCM resolution complete:" >&2
  echo "[INFO]   Resolved: $resolved_count" >&2
  echo "[INFO]   Unresolved: $unresolved_count" >&2
}

# Batch process with retry logic
# Args: worker_function item max_retries
batch_process_with_retry() {
  local worker_function="$1"
  local item="$2"
  local max_retries="${3:-$PARALLEL_RETRY_COUNT}"
  
  local attempt=0
  local success=false
  
  while [[ $attempt -lt $max_retries ]] && [[ "$success" == "false" ]]; do
    attempt=$((attempt + 1))
    
    if "$worker_function" "$item"; then
      success=true
    else
      if [[ $attempt -lt $max_retries ]]; then
        sleep 1
      fi
    fi
  done
  
  [[ "$success" == "true" ]]
}

# Progress reporter for long-running parallel operations
# Args: total_items progress_file
show_parallel_progress() {
  local total_items="$1"
  local progress_file="$2"
  
  while [[ -f "$progress_file" ]]; do
    local processed
    processed=$(cat "$progress_file" 2>/dev/null || echo "0")
    
    if [[ $processed -gt 0 ]] && [[ $total_items -gt 0 ]]; then
      local progress_pct=$((processed * 100 / total_items))
      printf "\r[%3d%%] Processing %d/%d    " "$progress_pct" "$processed" "$total_items" >&2
    fi
    
    sleep 1
  done
  
  printf "\r%-80s\r" "" >&2
}

# Export functions for use in other scripts
export -f parallel_process_file
export -f parallel_productization_worker
export -f parallel_productization_check
export -f parallel_scm_worker
export -f parallel_scm_resolution
export -f batch_process_with_retry
export -f show_parallel_progress