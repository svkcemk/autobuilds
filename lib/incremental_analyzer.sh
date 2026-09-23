#!/usr/bin/env bash
# Incremental Analysis Library
# Provides fingerprint-based change detection for dependency analysis
# Part of the PNC Build Config Generator performance optimization

set -euo pipefail

# Source cache manager if available
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/cache_manager.sh" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/cache_manager.sh"
fi

# Generate fingerprint for input configuration
# Args: input_type input_value [bom_gav] [config_file]
# Returns: SHA256 fingerprint
generate_fingerprint() {
  local input_type="$1"
  local input_value="$2"
  local bom_gav="${3:-}"
  local config_file="${4:-}"
  
  local fingerprint_data="$input_type:$input_value:$bom_gav"
  
  # Include config file content in fingerprint if it exists
  if [[ -n "$config_file" ]] && [[ -f "$config_file" ]]; then
    local config_hash
    config_hash=$(sha256sum "$config_file" 2>/dev/null | cut -d' ' -f1 || echo "")
    fingerprint_data="$fingerprint_data:$config_hash"
  fi
  
  # For file input, include file content hash
  if [[ "$input_type" == "file" ]] && [[ -f "$input_value" ]]; then
    local file_hash
    file_hash=$(sha256sum "$input_value" 2>/dev/null | cut -d' ' -f1 || echo "")
    fingerprint_data="$fingerprint_data:$file_hash"
  fi
  
  echo "$fingerprint_data" | sha256sum | cut -d' ' -f1
}

# Check if analysis is up-to-date
# Args: output_dir fingerprint
# Returns: 0 if current, 1 if outdated or missing
is_analysis_current() {
  local output_dir="$1"
  local fingerprint="$2"
  
  local fp_file="$output_dir/.fingerprint"
  
  # Check if fingerprint file exists
  [[ -f "$fp_file" ]] || return 1
  
  # Check if required output files exist
  [[ -f "$output_dir/all-dependencies.txt" ]] || return 1
  [[ -f "$output_dir/dependency-edges.txt" ]] || return 1
  
  # Compare fingerprints
  local cached_fp
  cached_fp=$(cat "$fp_file" 2>/dev/null || echo "")
  [[ "$cached_fp" == "$fingerprint" ]]
}

# Save fingerprint
# Args: output_dir fingerprint
save_fingerprint() {
  local output_dir="$1"
  local fingerprint="$2"
  
  mkdir -p "$output_dir"
  echo "$fingerprint" > "$output_dir/.fingerprint"
  
  # Save metadata
  cat > "$output_dir/.fingerprint.meta" <<EOF
{
  "fingerprint": "$fingerprint",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "hostname": "$(hostname)",
  "user": "$(whoami)"
}
EOF
}

# Get fingerprint metadata
# Args: output_dir
# Returns: JSON metadata
get_fingerprint_metadata() {
  local output_dir="$1"
  local meta_file="$output_dir/.fingerprint.meta"
  
  if [[ -f "$meta_file" ]]; then
    cat "$meta_file"
  else
    echo "{}"
  fi
}

# Check if any input files have changed
# Args: output_dir input_files...
# Returns: 0 if changed, 1 if unchanged
have_inputs_changed() {
  local output_dir="$1"
  shift
  local input_files=("$@")
  
  local changes_file="$output_dir/.input_changes"
  
  # If no previous state, consider changed
  [[ -f "$changes_file" ]] || return 0
  
  # Check each input file
  for file in "${input_files[@]}"; do
    [[ -f "$file" ]] || continue
    
    local current_hash
    current_hash=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1 || echo "")
    
    local cached_hash
    cached_hash=$(grep "^$file:" "$changes_file" 2>/dev/null | cut -d: -f2 || echo "")
    
    if [[ "$current_hash" != "$cached_hash" ]]; then
      return 0  # Changed
    fi
  done
  
  return 1  # Unchanged
}

# Save input file hashes
# Args: output_dir input_files...
save_input_hashes() {
  local output_dir="$1"
  shift
  local input_files=("$@")
  
  local changes_file="$output_dir/.input_changes"
  
  > "$changes_file"
  for file in "${input_files[@]}"; do
    [[ -f "$file" ]] || continue
    
    local file_hash
    file_hash=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1 || echo "")
    echo "$file:$file_hash" >> "$changes_file"
  done
}

# Incremental dependency analysis wrapper
# Args: input_type input_value output_dir config_file [bom_gav]
# Returns: 0 if analysis performed (or skipped), 1 on error
analyze_dependencies_incremental() {
  local input_type="$1"
  local input_value="$2"
  local output_dir="$3"
  local config_file="$4"
  local bom_gav="${5:-}"
  
  # Generate fingerprint
  local fingerprint
  fingerprint=$(generate_fingerprint "$input_type" "$input_value" "$bom_gav" "$config_file")
  
  # Check if analysis is current
  if is_analysis_current "$output_dir" "$fingerprint"; then
    local metadata
    metadata=$(get_fingerprint_metadata "$output_dir")
    local timestamp
    timestamp=$(echo "$metadata" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    
    echo "[INFO] Dependencies unchanged (fingerprint match)" >&2
    echo "[INFO] Using cached analysis from $timestamp" >&2
    return 0
  fi
  
  # Perform full analysis
  echo "[INFO] Dependencies changed or no cache, performing full analysis" >&2
  
  # Source dependency_analyzer if not already loaded
  if ! declare -f analyze_dependencies > /dev/null 2>&1; then
    local analyzer_path
    analyzer_path="$(dirname "${BASH_SOURCE[0]}")/dependency_analyzer.sh"
    if [[ -f "$analyzer_path" ]]; then
      source "$analyzer_path"
    else
      echo "[ERROR] dependency_analyzer.sh not found" >&2
      return 1
    fi
  fi
  
  # Run analysis
  if analyze_dependencies "$input_type" "$input_value" "$output_dir" "$config_file"; then
    # Save fingerprint on success
    save_fingerprint "$output_dir" "$fingerprint"
    
    # Save input file hashes
    local input_files=()
    [[ -f "$config_file" ]] && input_files+=("$config_file")
    [[ "$input_type" == "file" ]] && [[ -f "$input_value" ]] && input_files+=("$input_value")
    
    if [[ ${#input_files[@]} -gt 0 ]]; then
      save_input_hashes "$output_dir" "${input_files[@]}"
    fi
    
    return 0
  else
    echo "[ERROR] Dependency analysis failed" >&2
    return 1
  fi
}

# Force re-analysis by removing fingerprint
# Args: output_dir
force_reanalysis() {
  local output_dir="$1"
  
  rm -f "$output_dir/.fingerprint" "$output_dir/.fingerprint.meta" "$output_dir/.input_changes"
  echo "[INFO] Forced re-analysis (removed fingerprint)" >&2
}

# Show analysis status
# Args: output_dir
show_analysis_status() {
  local output_dir="$1"
  
  if [[ ! -f "$output_dir/.fingerprint" ]]; then
    echo "Status: No previous analysis"
    return 1
  fi
  
  local metadata
  metadata=$(get_fingerprint_metadata "$output_dir")
  
  local fingerprint
  fingerprint=$(cat "$output_dir/.fingerprint" 2>/dev/null || echo "unknown")
  
  local timestamp
  timestamp=$(echo "$metadata" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
  
  local user
  user=$(echo "$metadata" | grep -o '"user":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
  
  echo "Status: Analysis cached"
  echo "  Fingerprint: $fingerprint"
  echo "  Timestamp: $timestamp"
  echo "  User: $user"
  
  # Check if output files exist
  local files_ok=true
  for file in all-dependencies.txt dependency-edges.txt; do
    if [[ ! -f "$output_dir/$file" ]]; then
      echo "  Warning: Missing $file"
      files_ok=false
    fi
  done
  
  if [[ "$files_ok" == "true" ]]; then
    echo "  Output files: OK"
  else
    echo "  Output files: INCOMPLETE"
  fi
}

# Compare two fingerprints
# Args: output_dir1 output_dir2
# Returns: 0 if same, 1 if different
compare_fingerprints() {
  local output_dir1="$1"
  local output_dir2="$2"
  
  local fp1
  fp1=$(cat "$output_dir1/.fingerprint" 2>/dev/null || echo "")
  
  local fp2
  fp2=$(cat "$output_dir2/.fingerprint" 2>/dev/null || echo "")
  
  if [[ -z "$fp1" ]] || [[ -z "$fp2" ]]; then
    echo "Cannot compare: missing fingerprint(s)"
    return 1
  fi
  
  if [[ "$fp1" == "$fp2" ]]; then
    echo "Fingerprints match: $fp1"
    return 0
  else
    echo "Fingerprints differ:"
    echo "  Dir 1: $fp1"
    echo "  Dir 2: $fp2"
    return 1
  fi
}
