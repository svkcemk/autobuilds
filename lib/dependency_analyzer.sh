#!/usr/bin/env bash
# Dependency Analysis Library
# Shared library for Maven dependency resolution, filtering, and topological sorting
# Part of the PNC Build Config Generator consolidation effort

set -euo pipefail

# Analyze dependencies from various input sources
# Args: input_type (artifact|bom|file) input_value output_dir config_file
# Returns: Creates dependency files in output_dir
analyze_dependencies() {
  local input_type="$1"
  local input_value="$2"
  local output_dir="$3"
  local config_file="$4"
  
  # Prepare workspace
  mkdir -p "$output_dir"
  local work_dir
  work_dir="$(mktemp -d)"
  
  # BOM detection disabled - causes hangs with Maven resolution
  # TODO: Re-enable with proper timeout handling or use explicit --bom flag
  
  # Standard Maven resolution for non-BOM artifacts
  local temp_pom="$work_dir/pom.xml"
  case "$input_type" in
    artifact)
      generate_pom_for_artifact "$input_value" "$temp_pom"
      ;;
    bom)
      generate_pom_for_bom "$input_value" "$temp_pom"
      ;;
    file)
      generate_pom_for_file "$input_value" "$temp_pom"
      ;;
    *)
      echo "ERROR: Unknown input type: $input_type" >&2
      rm -rf "$work_dir"
      return 1
      ;;
  esac
  
  # Resolve dependency tree with Maven
  local tree_file="$work_dir/dependency-tree.txt"
  # Run Maven with timeout using background process (macOS compatible)
  mvn -f "$temp_pom" dependency:tree -DoutputType=text -Dverbose -Dscope=compile > "$tree_file" 2>&1 &
  local mvn_pid=$!
  local timeout=60
  local elapsed=0
  
  while kill -0 $mvn_pid 2>/dev/null && [[ $elapsed -lt $timeout ]]; do
    sleep 1
    elapsed=$((elapsed + 1))
  done
  
  if kill -0 $mvn_pid 2>/dev/null; then
    echo "[ERROR] Maven dependency:tree timed out after ${timeout}s - killing process" >&2
    kill -9 $mvn_pid 2>/dev/null
    rm -rf "$work_dir"
    return 1
  fi
  
  wait $mvn_pid
  local mvn_exit=$?
  
  if [[ $mvn_exit -ne 0 ]]; then
    echo "ERROR: Maven dependency resolution failed" >&2
    rm -rf "$work_dir"
    return 1
  fi
  
  # Copy full tree to output
  cp "$tree_file" "$output_dir/all-dependencies.txt"
  
  # Clean up
  rm -rf "$work_dir"
  
  return 0
}

# Generate POM for single artifact
generate_pom_for_artifact() {
  local gav="$1"
  local output_file="$2"
  
  local group_id artifact_id version
  group_id="$(echo "$gav" | cut -d: -f1)"
  artifact_id="$(echo "$gav" | cut -d: -f2)"
  version="$(echo "$gav" | cut -d: -f3)"
  
  cat > "$output_file" <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>local.temp</groupId>
  <artifactId>dependency-analyzer</artifactId>
  <version>1.0.0</version>
  <dependencies>
    <dependency>
      <groupId>${group_id}</groupId>
      <artifactId>${artifact_id}</artifactId>
      <version>${version}</version>
    </dependency>
  </dependencies>
</project>
EOF
}

# Generate POM with BOM import
generate_pom_for_bom() {
  local bom_gav="$1"
  local output_file="$2"
  
  local bom_group bom_artifact bom_version
  bom_group="$(echo "$bom_gav" | cut -d: -f1)"
  bom_artifact="$(echo "$bom_gav" | cut -d: -f2)"
  bom_version="$(echo "$bom_gav" | cut -d: -f3)"
  
  cat > "$output_file" <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>local.temp</groupId>
  <artifactId>dependency-analyzer</artifactId>
  <version>1.0.0</version>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>${bom_group}</groupId>
        <artifactId>${bom_artifact}</artifactId>
        <version>${bom_version}</version>
        <type>pom</type>
        <scope>import</scope>
      </dependency>
    </dependencies>
  </dependencyManagement>
</project>
EOF
}

# Generate POM from file with multiple artifacts
generate_pom_for_file() {
  local artifacts_file="$1"
  local output_file="$2"
  
  cat > "$output_file" <<'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>local.temp</groupId>
  <artifactId>dependency-analyzer</artifactId>
  <version>1.0.0</version>
  <dependencies>
EOF
  
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and empty lines
    line="$(echo "$line" | sed 's/#.*$//' | xargs)"
    [[ -z "$line" ]] && continue
    
    local group_id artifact_id version
    group_id="$(echo "$line" | cut -d: -f1)"
    artifact_id="$(echo "$line" | cut -d: -f2)"
    version="$(echo "$line" | cut -d: -f3)"
    
    cat >> "$output_file" <<EOF
    <dependency>
      <groupId>${group_id}</groupId>
      <artifactId>${artifact_id}</artifactId>
      <version>${version}</version>
    </dependency>
EOF
  done < "$artifacts_file"
  
  cat >> "$output_file" <<'EOF'
  </dependencies>
</project>
EOF
}

# Filter dependencies based on include/exclude patterns
# Args: tree_file root_artifacts_file exclude_groups output_deps_file output_edges_file
filter_dependencies() {
  local tree_file="$1"
  local root_artifacts_file="$2"
  local exclude_groups="$3"
  local output_deps_file="$4"
  local output_edges_file="$5"
  
  python3 - "$tree_file" "$root_artifacts_file" "$output_deps_file" "$output_edges_file" "$exclude_groups" <<'PY'
import re
import sys
from pathlib import Path

tree_file = Path(sys.argv[1])
roots_file = Path(sys.argv[2])
deps_out = Path(sys.argv[3])
edges_out = Path(sys.argv[4])
exclude_groups = {x.strip() for x in sys.argv[5].split(",") if x.strip()}

# Load root artifacts
roots = set()
if roots_file.exists():
    roots = {line.strip() for line in roots_file.read_text().splitlines() if line.strip()}

# Parse dependency tree
artifact_re = re.compile(r'([A-Za-z0-9_.\-]+):([A-Za-z0-9_.\-]+):([A-Za-z0-9_.\-]+)(?::([A-Za-z0-9_.\-]+))?:([A-Za-z0-9_.\-]+):([A-Za-z0-9_.\-]+)')
stack = []
deps = set()
edges = set()

for raw in tree_file.read_text().splitlines():
    # Remove Maven INFO prefix
    line = raw[7:] if raw.startswith('[INFO] ') else raw
    
    # Skip empty lines and Maven output
    if not line.strip():
        continue
    if line.startswith('--- ') or line.startswith('BUILD ') or line.startswith('Scanning for projects'):
        continue
    
    # Skip omitted dependencies
    if 'omitted for duplicate' in line or 'omitted for conflict' in line or 'omitted for cycle' in line:
        continue

    # Extract artifact coordinates
    match = artifact_re.search(line)
    if not match:
        continue

    group, artifact, packaging, classifier, version, scope = match.groups()
    gav = f"{group}:{artifact}:{version}"

    # Calculate depth from tree structure
    prefix = line[:match.start()]
    depth = prefix.count('|  ')
    if '+-' in prefix or '\\-' in prefix:
        depth += 1
    elif prefix.strip():
        depth = 1
    else:
        depth = 0

    # Maintain stack for parent tracking
    while len(stack) > depth:
        stack.pop()

    parent = stack[-1] if stack else None
    
    # Adjust stack
    if len(stack) < depth:
        stack.extend([None] * (depth - len(stack)))
    if len(stack) == depth:
        stack.append(gav)
    else:
        stack[depth] = gav

    # Skip root artifacts
    if gav in roots:
        continue
    
    # Skip excluded groups
    if group in exclude_groups:
        continue

    # Add to dependencies
    deps.add(gav)
    
    # Add edge if parent exists and is not root/excluded
    if parent and parent not in roots:
        parent_group = parent.split(':', 1)[0]
        if parent_group not in exclude_groups:
            edges.add((parent, gav))

# Write output
deps_out.write_text("".join(f"{x}\n" for x in sorted(deps)))
edges_out.write_text("".join(f"{a} {b}\n" for a, b in sorted(edges)))
PY
}

# Perform topological sort on dependencies
# Args: deps_file edges_file output_file
topological_sort() {
  local deps_file="$1"
  local edges_file="$2"
  local output_file="$3"
  
  python3 - "$deps_file" "$edges_file" "$output_file" <<'PY'
import sys
from pathlib import Path
from collections import defaultdict, deque

deps_file = Path(sys.argv[1])
edges_file = Path(sys.argv[2])
output_file = Path(sys.argv[3])

# Load all nodes
nodes = [line.strip() for line in deps_file.read_text().splitlines() if line.strip()]
node_set = set(nodes)

# Build adjacency list and calculate in-degrees
adj = defaultdict(set)
indegree = {n: 0 for n in nodes}

for line in edges_file.read_text().splitlines():
    line = line.strip()
    if not line:
        continue
    parts = line.split(" ", 1)
    if len(parts) != 2:
        continue
    a, b = parts
    if a in node_set and b in node_set and b not in adj[a]:
        adj[a].add(b)
        indegree[b] += 1

# Kahn's algorithm for topological sort
queue = deque(sorted([n for n in nodes if indegree[n] == 0]))
ordered = []

while queue:
    n = queue.popleft()
    ordered.append(n)
    for m in sorted(adj[n]):
        indegree[m] -= 1
        if indegree[m] == 0:
            queue.append(m)

# Add any remaining nodes (cycles or disconnected)
if len(ordered) != len(nodes):
    ordered.extend(sorted(set(nodes) - set(ordered)))

# Write output
output_file.write_text("\n".join(ordered) + "\n")
PY
}

# Extract unique dependencies from tree (without filtering)
# Args: tree_file output_file
extract_unique_dependencies() {
  local tree_file="$1"
  local output_file="$2"
  
  python3 - "$tree_file" "$output_file" <<'PY'
import re
import sys
from pathlib import Path

tree_file = Path(sys.argv[1])
output_file = Path(sys.argv[2])

artifact_re = re.compile(r'([A-Za-z0-9_.\-]+):([A-Za-z0-9_.\-]+):([A-Za-z0-9_.\-]+)(?::([A-Za-z0-9_.\-]+))?:([A-Za-z0-9_.\-]+):([A-Za-z0-9_.\-]+)')
deps = set()

for raw in tree_file.read_text().splitlines():
    line = raw[7:] if raw.startswith('[INFO] ') else raw
    
    if not line.strip():
        continue
    if 'omitted for duplicate' in line or 'omitted for conflict' in line or 'omitted for cycle' in line:
        continue
    
    match = artifact_re.search(line)
    if not match:
        continue
    
    group, artifact, packaging, classifier, version, scope = match.groups()
    gav = f"{group}:{artifact}:{version}"
    deps.add(gav)

output_file.write_text("\n".join(sorted(deps)) + "\n")
PY
}

# Count dependencies by group
# Args: deps_file
count_by_group() {
  local deps_file="$1"
  
  python3 - "$deps_file" <<'PY'
import sys
from pathlib import Path
from collections import Counter

deps_file = Path(sys.argv[1])
groups = Counter()

for line in deps_file.read_text().splitlines():
    line = line.strip()
    if not line:
        continue
    group = line.split(':', 1)[0]
    groups[group] += 1

print("Dependencies by Group:")
print("-" * 50)
for group, count in groups.most_common():
    print(f"{group:40s} {count:5d}")
print("-" * 50)
print(f"{'Total Groups:':40s} {len(groups):5d}")
print(f"{'Total Dependencies:':40s} {sum(groups.values()):5d}")
PY
}

# Validate GAV format
validate_gav() {
  local gav="$1"
  [[ "$gav" =~ ^[^:]+:[^:]+:[^:]+$ ]]
}

# Load root artifacts from file
# Args: artifacts_file output_file
load_root_artifacts() {
  local artifacts_file="$1"
  local output_file="$2"
  
  : > "$output_file"
  
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Remove comments and trim
    line="$(echo "$line" | sed 's/#.*$//' | xargs)"
    [[ -z "$line" ]] && continue
    
    # Validate GAV format
    if ! validate_gav "$line"; then
      echo "ERROR: Invalid GAV format: $line" >&2
      return 1
    fi
    
    echo "$line" >> "$output_file"
  done < "$artifacts_file"
  
  # Remove duplicates and sort
  sort -u "$output_file" -o "$output_file"
}

# Get dependency statistics
# Args: deps_file edges_file
get_dependency_stats() {
  local deps_file="$1"
  local edges_file="$2"
  
  local total_deps total_edges
  total_deps="$(wc -l < "$deps_file" | tr -d ' ')"
  total_edges="$(wc -l < "$edges_file" | tr -d ' ')"
  
  echo "Total Dependencies: $total_deps"
  echo "Total Edges: $total_edges"
  
  # Calculate average dependencies per artifact
  if [[ "$total_deps" -gt 0 ]]; then
    local avg
    avg="$(echo "scale=2; $total_edges / $total_deps" | bc)"
    echo "Average Dependencies per Artifact: $avg"
  fi
}

# Check productization status of dependencies
# Checks if dependencies have .redhat versions in Indy (already productized)
# Args: deps_file redhat_suffix output_dir verbose
# Returns: Creates build-from-source.txt and pending-productized.txt
check_productization() {
  local deps_file="$1"
  local redhat_suffix="$2"
  local output_dir="$3"
  local verbose="${4:-false}"
  
  [[ "$verbose" == "true" ]] && echo "[VERBOSE] Checking productization status with suffix: $redhat_suffix" >&2
  
  if [[ -z "$redhat_suffix" ]]; then
    echo "[WARN] No redhat suffix provided, skipping productization check" >&2
    return 0
  fi
  
  local build_from_source=0
  local pending_productized=0
  local total_deps
  total_deps=$(grep -c ":" "$deps_file" || echo "0")
  
  echo "[INFO] Checking productization for $total_deps dependencies (using parallel checks)..." >&2
  
  > "$output_dir/build-from-source.txt"
  > "$output_dir/pending-productized.txt"
  
  local temp_dir
  temp_dir=$(mktemp -d)
  local max_parallel=10
  local current=0
  
  # Process dependencies in parallel batches
  while IFS=: read -r dep_group dep_artifact dep_version; do
    [[ -z "$dep_group" ]] && continue
    
    current=$((current + 1))
    
    # Launch parallel check
    (
      local found=false
      local found_version=""
      
      # Handle wildcard suffix (redhat-*)
      if [[ "$redhat_suffix" == "redhat-*" ]]; then
        # Try common redhat suffixes in order (both 4-digit and 5-digit formats)
        for suffix_num in 00001 00002 00003 00004 00005 0001 0002 0003 0004 0005; do
          local test_version="${dep_version}.redhat-${suffix_num}"
          local test_url="https://indy.corp.redhat.com/api/content/maven/hosted/pnc-builds/${dep_group//.//}/${dep_artifact}/${test_version}/${dep_artifact}-${test_version}.pom"
          
          if curl -s -f -m 5 -I "$test_url" > /dev/null 2>&1; then
            found=true
            found_version="$test_version"
            break
          fi
        done
      else
        # Exact suffix match
        local redhat_version="${dep_version}.${redhat_suffix}"
        local indy_url="https://indy.corp.redhat.com/api/content/maven/hosted/pnc-builds/${dep_group//.//}/${dep_artifact}/${redhat_version}/${dep_artifact}-${redhat_version}.pom"
        
        if curl -s -f -m 5 -I "$indy_url" > /dev/null 2>&1; then
          found=true
          found_version="$redhat_version"
        fi
      fi
      
      if [[ "$found" == "true" ]]; then
        echo "${dep_group}:${dep_artifact}:${found_version}" >> "$temp_dir/productized.txt"
      else
        echo "${dep_group}:${dep_artifact}:${dep_version}" >> "$temp_dir/pending.txt"
      fi
    ) &
    
    # Limit parallel processes
    if [[ $((current % max_parallel)) -eq 0 ]]; then
      wait
      echo "[INFO] Progress: $current/$total_deps dependencies checked..." >&2
    fi
  done < "$deps_file"
  
  # Wait for remaining processes
  wait
  
  # Consolidate results
  [[ -f "$temp_dir/productized.txt" ]] && cat "$temp_dir/productized.txt" >> "$output_dir/build-from-source.txt"
  [[ -f "$temp_dir/pending.txt" ]] && cat "$temp_dir/pending.txt" >> "$output_dir/pending-productized.txt"
  
  build_from_source=$(wc -l < "$output_dir/build-from-source.txt" 2>/dev/null || echo "0")
  pending_productized=$(wc -l < "$output_dir/pending-productized.txt" 2>/dev/null || echo "0")
  
  rm -rf "$temp_dir"
  
  echo "[INFO] Productization check complete:" >&2
  echo "[INFO]   Build-from-source: $build_from_source (already productized)" >&2
  echo "[INFO]   Pending productized: $pending_productized (need to be built)" >&2
  
  # Display summary lists
  if [[ $build_from_source -gt 0 ]]; then
    echo "" >&2
    echo "[INFO] Already Productized (first 10):" >&2
    head -10 "$output_dir/build-from-source.txt" | while read -r line; do
      echo "[INFO]   ✓ $line" >&2
    done
    [[ $build_from_source -gt 10 ]] && echo "[INFO]   ... and $((build_from_source - 10)) more (see build-from-source.txt)" >&2
  fi
  
  if [[ $pending_productized -gt 0 ]]; then
    echo "" >&2
    echo "[INFO] Pending Productization (first 10):" >&2
    head -10 "$output_dir/pending-productized.txt" | while read -r line; do
      echo "[INFO]   ✗ $line" >&2
    done
    [[ $pending_productized -gt 10 ]] && echo "[INFO]   ... and $((pending_productized - 10)) more (see pending-productized.txt)" >&2
  fi
  echo "" >&2
  
  # Return counts via stdout for caller to capture
  echo "$build_from_source:$pending_productized"
}
