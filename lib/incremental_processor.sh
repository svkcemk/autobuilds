#!/usr/bin/env bash
# Incremental Processor Library
# Provides incremental processing to skip unchanged artifacts
# Part of Phase 1: Performance Optimization

set -euo pipefail

# State directory for tracking processed artifacts
STATE_DIR=".state"
STATE_DB="processed-artifacts.db"
DEPENDENCY_GRAPH="dependency-graph.json"
LAST_RUN_INFO="last-run.json"

# Initialize state directory
init_state_dir() {
  local output_dir="$1"
  
  mkdir -p "$output_dir/$STATE_DIR"
  
  # Initialize SQLite database if not exists
  local db_file="$output_dir/$STATE_DIR/$STATE_DB"
  if [[ ! -f "$db_file" ]]; then
    sqlite3 "$db_file" <<'SQL'
CREATE TABLE IF NOT EXISTS processed_artifacts (
  gav TEXT PRIMARY KEY,
  version TEXT NOT NULL,
  processed_at TEXT NOT NULL,
  config_hash TEXT NOT NULL,
  scm_url TEXT,
  scm_revision TEXT,
  productized INTEGER DEFAULT 0,
  productized_version TEXT,
  build_config_generated INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_processed_at ON processed_artifacts(processed_at);
CREATE INDEX IF NOT EXISTS idx_productized ON processed_artifacts(productized);
CREATE INDEX IF NOT EXISTS idx_config_hash ON processed_artifacts(config_hash);
SQL
  fi
}

# Generate configuration hash for change detection
# Args: config_file bom_gav exclude_groups
generate_config_hash() {
  local config_file="$1"
  local bom_gav="${2:-}"
  local exclude_groups="${3:-}"
  
  local config_content=""
  
  # Include config file content
  if [[ -f "$config_file" ]]; then
    config_content+=$(cat "$config_file")
  fi
  
  # Include BOM GAV
  config_content+="BOM:$bom_gav"
  
  # Include exclude groups
  config_content+="EXCLUDE:$exclude_groups"
  
  # Generate SHA256 hash
  echo -n "$config_content" | shasum -a 256 | awk '{print $1}'
}

# Check if artifact needs reprocessing
# Args: output_dir gav config_hash
needs_reprocessing() {
  local output_dir="$1"
  local gav="$2"
  local config_hash="$3"
  
  local db_file="$output_dir/$STATE_DIR/$STATE_DB"
  
  [[ ! -f "$db_file" ]] && return 0
  
  # Query database for artifact
  local stored_hash
  stored_hash=$(sqlite3 "$db_file" "SELECT config_hash FROM processed_artifacts WHERE gav='$gav' LIMIT 1;" 2>/dev/null || echo "")
  
  # If not found or hash differs, needs reprocessing
  [[ -z "$stored_hash" || "$stored_hash" != "$config_hash" ]] && return 0
  
  return 1
}

# Mark artifact as processed
# Args: output_dir gav config_hash scm_url scm_revision productized productized_version
mark_artifact_processed() {
  local output_dir="$1"
  local gav="$2"
  local config_hash="$3"
  local scm_url="${4:-}"
  local scm_revision="${5:-}"
  local productized="${6:-0}"
  local productized_version="${7:-}"
  
  local db_file="$output_dir/$STATE_DIR/$STATE_DB"
  local version
  version=$(echo "$gav" | cut -d: -f3)
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  sqlite3 "$db_file" <<SQL
INSERT OR REPLACE INTO processed_artifacts 
  (gav, version, processed_at, config_hash, scm_url, scm_revision, productized, productized_version, build_config_generated)
VALUES 
  ('$gav', '$version', '$timestamp', '$config_hash', '$scm_url', '$scm_revision', $productized, '$productized_version', 1);
SQL
}

# Get list of artifacts that need reprocessing
# Args: output_dir artifacts_file config_hash
get_artifacts_to_process() {
  local output_dir="$1"
  local artifacts_file="$2"
  local config_hash="$3"
  
  init_state_dir "$output_dir"
  
  local to_process_file="$output_dir/$STATE_DIR/to-process.txt"
  local skipped_file="$output_dir/$STATE_DIR/skipped.txt"
  
  : > "$to_process_file"
  : > "$skipped_file"
  
  local total=0
  local to_process=0
  local skipped=0
  
  while IFS= read -r gav || [[ -n "$gav" ]]; do
    [[ -z "$gav" ]] && continue
    total=$((total + 1))
    
    if needs_reprocessing "$output_dir" "$gav" "$config_hash"; then
      echo "$gav" >> "$to_process_file"
      to_process=$((to_process + 1))
    else
      echo "$gav" >> "$skipped_file"
      skipped=$((skipped + 1))
    fi
  done < "$artifacts_file"
  
  echo "[INFO] Incremental processing analysis:" >&2
  echo "[INFO]   Total artifacts: $total" >&2
  echo "[INFO]   Need processing: $to_process" >&2
  echo "[INFO]   Skipped (unchanged): $skipped" >&2
  
  # Return path to file with artifacts to process
  echo "$to_process_file"
}

# Save last run information
# Args: output_dir config_hash artifact_count
save_last_run_info() {
  local output_dir="$1"
  local config_hash="$2"
  local artifact_count="$3"
  
  local info_file="$output_dir/$STATE_DIR/$LAST_RUN_INFO"
  
  cat > "$info_file" <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "config_hash": "$config_hash",
  "artifact_count": $artifact_count,
  "version": "1.0"
}
EOF
}

# Get last run information
# Args: output_dir
get_last_run_info() {
  local output_dir="$1"
  local info_file="$output_dir/$STATE_DIR/$LAST_RUN_INFO"
  
  [[ ! -f "$info_file" ]] && return 1
  
  cat "$info_file"
}

# Get processed artifact statistics
# Args: output_dir
get_processed_stats() {
  local output_dir="$1"
  local db_file="$output_dir/$STATE_DIR/$STATE_DB"
  
  [[ ! -f "$db_file" ]] && return 1
  
  local total_processed productized_count non_productized_count
  total_processed=$(sqlite3 "$db_file" "SELECT COUNT(*) FROM processed_artifacts;" 2>/dev/null || echo "0")
  productized_count=$(sqlite3 "$db_file" "SELECT COUNT(*) FROM processed_artifacts WHERE productized=1;" 2>/dev/null || echo "0")
  non_productized_count=$(sqlite3 "$db_file" "SELECT COUNT(*) FROM processed_artifacts WHERE productized=0;" 2>/dev/null || echo "0")
  
  cat <<EOF
Processed Artifacts Statistics
==============================
Total Processed: $total_processed
  - Productized: $productized_count
  - Non-productized: $non_productized_count

Database: $db_file
EOF
}

# Clear state (force full reprocessing)
# Args: output_dir
clear_state() {
  local output_dir="$1"
  
  echo "[INFO] Clearing incremental processing state..." >&2
  rm -rf "$output_dir/$STATE_DIR"
  echo "[INFO] State cleared. Next run will be a full reprocessing." >&2
}

# Export processed artifacts to file
# Args: output_dir output_file
export_processed_artifacts() {
  local output_dir="$1"
  local output_file="$2"
  local db_file="$output_dir/$STATE_DIR/$STATE_DB"
  
  [[ ! -f "$db_file" ]] && return 1
  
  sqlite3 -header -csv "$db_file" "SELECT * FROM processed_artifacts ORDER BY processed_at DESC;" > "$output_file"
  echo "[INFO] Exported processed artifacts to: $output_file" >&2
}

# Query processed artifacts
# Args: output_dir query_type [query_value]
# query_type: all|productized|non-productized|by-date|by-gav
query_processed_artifacts() {
  local output_dir="$1"
  local query_type="$2"
  local query_value="${3:-}"
  local db_file="$output_dir/$STATE_DIR/$STATE_DB"
  
  [[ ! -f "$db_file" ]] && return 1
  
  case "$query_type" in
    all)
      sqlite3 -header -column "$db_file" "SELECT gav, processed_at, productized FROM processed_artifacts ORDER BY processed_at DESC;"
      ;;
    productized)
      sqlite3 -header -column "$db_file" "SELECT gav, productized_version, processed_at FROM processed_artifacts WHERE productized=1 ORDER BY processed_at DESC;"
      ;;
    non-productized)
      sqlite3 -header -column "$db_file" "SELECT gav, processed_at FROM processed_artifacts WHERE productized=0 ORDER BY processed_at DESC;"
      ;;
    by-date)
      [[ -z "$query_value" ]] && query_value=$(date -u +"%Y-%m-%d")
      sqlite3 -header -column "$db_file" "SELECT gav, processed_at, productized FROM processed_artifacts WHERE processed_at LIKE '${query_value}%' ORDER BY processed_at DESC;"
      ;;
    by-gav)
      [[ -z "$query_value" ]] && return 1
      sqlite3 -header -column "$db_file" "SELECT * FROM processed_artifacts WHERE gav LIKE '%${query_value}%';"
      ;;
    *)
      echo "[ERROR] Unknown query type: $query_type" >&2
      return 1
      ;;
  esac
}

# Merge results from incremental run with previous run
# Args: output_dir new_results_file
merge_incremental_results() {
  local output_dir="$1"
  local new_results_file="$2"
  local db_file="$output_dir/$STATE_DIR/$STATE_DB"
  
  [[ ! -f "$db_file" ]] && return 0
  
  # Get previously processed artifacts that weren't reprocessed
  local previous_results="$output_dir/$STATE_DIR/previous-results.txt"
  sqlite3 "$db_file" "SELECT gav FROM processed_artifacts;" > "$previous_results"
  
  # Merge with new results (remove duplicates, keep new results)
  local merged_file="$output_dir/$STATE_DIR/merged-results.txt"
  cat "$new_results_file" "$previous_results" | sort -u > "$merged_file"
  
  echo "[INFO] Merged incremental results with previous run" >&2
  echo "$merged_file"
}

# Get dependency graph for incremental updates
# Args: output_dir
get_dependency_graph() {
  local output_dir="$1"
  local graph_file="$output_dir/$STATE_DIR/$DEPENDENCY_GRAPH"
  
  [[ ! -f "$graph_file" ]] && return 1
  
  cat "$graph_file"
}

# Save dependency graph
# Args: output_dir edges_file
save_dependency_graph() {
  local output_dir="$1"
  local edges_file="$2"
  local graph_file="$output_dir/$STATE_DIR/$DEPENDENCY_GRAPH"
  
  # Convert edges to JSON format
  python3 - "$edges_file" "$graph_file" <<'PY'
import sys
import json
from pathlib import Path

edges_file = Path(sys.argv[1])
graph_file = Path(sys.argv[2])

graph = {}

for line in edges_file.read_text().splitlines():
    line = line.strip()
    if not line:
        continue
    parts = line.split(" ", 1)
    if len(parts) != 2:
        continue
    parent, child = parts
    
    if parent not in graph:
        graph[parent] = []
    graph[parent].append(child)

graph_file.write_text(json.dumps(graph, indent=2))
PY
  
  echo "[INFO] Saved dependency graph to: $graph_file" >&2
}

# Find artifacts affected by changes (transitive dependents)
# Args: output_dir changed_artifacts_file
find_affected_artifacts() {
  local output_dir="$1"
  local changed_artifacts_file="$2"
  local graph_file="$output_dir/$STATE_DIR/$DEPENDENCY_GRAPH"
  
  [[ ! -f "$graph_file" ]] && return 1
  
  local affected_file="$output_dir/$STATE_DIR/affected-artifacts.txt"
  
  python3 - "$changed_artifacts_file" "$graph_file" "$affected_file" <<'PY'
import sys
import json
from pathlib import Path

changed_file = Path(sys.argv[1])
graph_file = Path(sys.argv[2])
affected_file = Path(sys.argv[3])

# Load changed artifacts
changed = set(changed_file.read_text().splitlines())

# Load dependency graph
graph = json.loads(graph_file.read_text())

# Find all transitive dependents
affected = set(changed)
queue = list(changed)

while queue:
    artifact = queue.pop(0)
    
    # Find all artifacts that depend on this one
    for parent, children in graph.items():
        if artifact in children and parent not in affected:
            affected.add(parent)
            queue.append(parent)

# Write affected artifacts
affected_file.write_text('\n'.join(sorted(affected)) + '\n')
PY
  
  echo "[INFO] Found affected artifacts (including transitive dependents)" >&2
  echo "$affected_file"
}

# Export functions for use in other scripts
export -f init_state_dir
export -f generate_config_hash
export -f needs_reprocessing
export -f mark_artifact_processed
export -f get_artifacts_to_process
export -f save_last_run_info
export -f get_last_run_info
export -f get_processed_stats
export -f clear_state
export -f export_processed_artifacts
export -f query_processed_artifacts
export -f merge_incremental_results
export -f get_dependency_graph
export -f save_dependency_graph
export -f find_affected_artifacts
