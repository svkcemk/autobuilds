#!/usr/bin/env bash
# Config Generation Library
# Shared library for generating PNC build configurations
# Part of the PNC Build Config Generator consolidation effort

set -euo pipefail

# Generate individual build config in JSON format
# Args: name project description scm_url scm_revision build_type environment_id build_script output_file
generate_build_config() {
  local name="$1"
  local project="$2"
  local description="$3"
  local scm_url="$4"
  local scm_revision="$5"
  local build_type="$6"
  local environment_id="$7"
  local build_script="$8"
  local output_file="$9"
  
  python3 - "$output_file" "$name" "$project" "$description" "$scm_url" "$scm_revision" "$build_type" "$environment_id" "$build_script" <<'PY'
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
data = {
    "name": sys.argv[2],
    "project": sys.argv[3],
    "description": sys.argv[4],
    "scmUrl": sys.argv[5],
    "scmRevision": sys.argv[6],
    "buildType": sys.argv[7],
    "environmentId": int(sys.argv[8]),
    "buildScript": sys.argv[9],
}
out.write_text(json.dumps(data, indent=2) + "\n")
PY
}

# Generate combined YAML with topological sorting
# Args: deps_file edges_file configs_dir output_file product_config default_build_config
generate_combined_yaml() {
  local deps_file="$1"
  local edges_file="$2"
  local configs_dir="$3"
  local output_file="$4"
  local product_name="$5"
  local product_abbreviation="$6"
  local product_stage="$7"
  local version="$8"
  local milestone="$9"
  local group="${10}"
  local release_file="${11}"
  local release_dir="${12}"
  local default_build_type="${13}"
  local default_environment_id="${14}"
  local default_build_script="${15}"
  
  python3 - "$deps_file" "$edges_file" "$configs_dir" "$output_file" "$product_name" "$product_abbreviation" "$product_stage" "$version" "$milestone" "$group" "$release_file" "$release_dir" "$default_build_type" "$default_environment_id" "$default_build_script" <<'PY'
import sys
from pathlib import Path
from collections import defaultdict, deque
import json

deps_file = Path(sys.argv[1])
edges_file = Path(sys.argv[2])
configs_dir = Path(sys.argv[3])
out_file = Path(sys.argv[4])
product_name = sys.argv[5]
product_abbreviation = sys.argv[6]
product_stage = sys.argv[7]
version = sys.argv[8]
milestone = sys.argv[9]
group = sys.argv[10]
release_file = sys.argv[11]
release_dir = sys.argv[12]
default_build_type = sys.argv[13]
default_environment_id = int(sys.argv[14])
default_build_script = sys.argv[15]

# Load nodes
nodes = [line.strip() for line in deps_file.read_text().splitlines() if line.strip()]
node_set = set(nodes)

# Build adjacency list
adj = defaultdict(set)
indegree = {n: 0 for n in nodes}
reverse = defaultdict(set)

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
        reverse[b].add(a)
        indegree[b] += 1

# Topological sort
queue = deque(sorted([n for n in nodes if indegree[n] == 0]))
ordered = []
while queue:
    n = queue.popleft()
    ordered.append(n)
    for m in sorted(adj[n]):
        indegree[m] -= 1
        if indegree[m] == 0:
            queue.append(m)

# Add remaining nodes
if len(ordered) != len(nodes):
    ordered.extend(sorted(set(nodes) - set(ordered)))

def load_json(path):
    return json.loads(path.read_text())

# Build result structure
result = {
    "product": {
        "name": product_name,
        "abbreviation": product_abbreviation,
        "stage": product_stage,
    },
    "version": version,
    "milestone": milestone,
    "group": group,
    "defaultBuildParameters": {
        "buildType": default_build_type,
        "environmentId": default_environment_id,
        "buildScript": default_build_script,
    },
    "builds": [],
    "outputPrefixes": {
        "releaseFile": release_file,
        "releaseDir": release_dir,
    },
    "flow": {
        "repositoryGeneration": {"strategy": "IGNORE"},
        "licensesGeneration": {"strategy": "IGNORE"},
        "javadocGeneration": {"strategy": "IGNORE"},
        "sourcesGeneration": {"strategy": "IGNORE"},
    },
}

# Add builds in topological order
for gav in ordered:
    group_id, artifact_id, artifact_version = gav.split(":")
    name = f"{group_id}_{artifact_id}_{artifact_version}"
    cfg_file = configs_dir / f"{name}.yaml.json"
    
    if not cfg_file.exists():
        continue
    
    data = load_json(cfg_file)
    
    # Add dependencies
    deps = sorted(f"{p.split(':')[0]}_{p.split(':')[1]}_{p.split(':')[2]}" for p in reverse.get(gav, set()))
    if deps:
        data["dependencies"] = deps
    
    result["builds"].append(data)

# Custom YAML emitter (preserves formatting)
def emit_scalar(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    text = str(value)
    if text == "" or any(ch in text for ch in [":", "#", "{", "}", "[", "]", ",", "&", "*", "?", "|", ">", "%", "@", "`", '"', "'"]) or text.strip() != text:
        return json.dumps(text)
    return text

def dump_yaml(obj, indent=0):
    lines = []
    prefix = " " * indent
    if isinstance(obj, dict):
        for key, value in obj.items():
            if isinstance(value, (dict, list)):
                lines.append(f"{prefix}{key}:")
                lines.extend(dump_yaml(value, indent + 2))
            elif isinstance(value, str) and "\n" in value:
                lines.append(f"{prefix}{key}: |")
                for line in value.splitlines():
                    lines.append(" " * (indent + 2) + line)
            else:
                lines.append(f"{prefix}{key}: {emit_scalar(value)}")
    elif isinstance(obj, list):
        for item in obj:
            if isinstance(item, dict):
                first = True
                for key, value in item.items():
                    item_prefix = f"{prefix}- " if first else " " * (indent + 2)
                    if isinstance(value, (dict, list)):
                        lines.append(f"{item_prefix}{key}:")
                        lines.extend(dump_yaml(value, indent + 4))
                    elif isinstance(value, str) and "\n" in value:
                        lines.append(f"{item_prefix}{key}: |")
                        for line in value.splitlines():
                            lines.append(" " * (indent + 4) + line)
                    else:
                        lines.append(f"{item_prefix}{key}: {emit_scalar(value)}")
                    first = False
            elif isinstance(item, list):
                lines.append(f"{prefix}-")
                lines.extend(dump_yaml(item, indent + 2))
            elif isinstance(item, str) and "\n" in item:
                lines.append(f"{prefix}- |")
                for line in item.splitlines():
                    lines.append(" " * (indent + 2) + line)
            else:
                lines.append(f"{prefix}- {emit_scalar(item)}")
    return lines

out_file.write_text("\n".join(dump_yaml(result)) + "\n")
PY
}

# Generate PIG config from template
# Args: config_file output_file
generate_pig_config() {
  local config_file="$1"
  local output_file="$2"
  
  if command -v yq >/dev/null 2>&1 && yq -e '.buildConfigGeneratorConfig.pigTemplate' "$config_file" >/dev/null 2>&1; then
    yq -r '.buildConfigGeneratorConfig.pigTemplate' "$config_file" > "$output_file"
  else
    # Default PIG config
    cat > "$output_file" <<'YAML'
product:
  name: Generated Product
  abbreviation: generated-product
  stage: GA
version: 1.0.0
milestone: DR1
group: generated-third-party-group
outputPrefixes:
  releaseFile: generated-third-party
  releaseDir: generated-third-party
flow:
  repositoryGeneration:
    strategy: IGNORE
  licensesGeneration:
    strategy: IGNORE
  javadocGeneration:
    strategy: IGNORE
  sourcesGeneration:
    strategy: IGNORE
YAML
  fi
}

# Query PNC for existing build configs via bacon CLI
# Args: group_id artifact_id current_version
# Returns: JSON config or empty string
query_pnc_build_config() {
  local group_id="$1"
  local artifact_id="$2"
  local current_version="$3"
  
  # Check if bacon CLI is available
  if ! command -v bacon >/dev/null 2>&1; then
    return 1
  fi
  
  # Convert groupId dots to hyphens for PNC naming convention
  local pnc_group
  pnc_group="$(echo "$group_id" | tr '.' '-')"
  
  # Search pattern: groupId-artifactId-*
  local search_pattern="${pnc_group}-${artifact_id}*"
  
  # Query PNC via bacon CLI
  local pnc_configs
  if ! pnc_configs="$(bacon pnc build-config list --query="name=like=${search_pattern}" -o 2>/dev/null)"; then
    return 1
  fi
  
  # Check if we got any results
  if [[ -z "$pnc_configs" || "$pnc_configs" == "[]" ]]; then
    return 1
  fi
  
  # Parse JSON and find most recent non-current version
  local best_config
  best_config="$(echo "$pnc_configs" | jq -r --arg current_ver "$current_version" '
    map(select(.name | test("'"$pnc_group"'-'"$artifact_id"'-")))
    | map(select(.name | test("-'"$current_version"'($|-AUTOBUILD)") | not))
    | sort_by(.modificationTime) | reverse | .[0] // empty
  ' 2>/dev/null || echo "")"
  
  if [[ -n "$best_config" && "$best_config" != "null" ]]; then
    echo "$best_config"
    return 0
  fi
  
  return 1
}

# Search for existing build config from previous versions (local files)
# Args: group_id artifact_id current_version search_dirs
# Returns: Path to config file or empty string
find_previous_build_config_local() {
  local group_id="$1"
  local artifact_id="$2"
  local current_version="$3"
  local search_dirs="$4"
  
  # If no search directories provided, return
  if [[ -z "$search_dirs" ]]; then
    return 1
  fi
  
  # Search pattern: groupId_artifactId_*.yaml.json
  local search_pattern="${group_id}_${artifact_id}_*.yaml.json"
  local found_config=""
  
  # Search in each directory
  IFS=',' read -ra DIRS <<< "$search_dirs"
  for dir in "${DIRS[@]}"; do
    dir="$(echo "$dir" | xargs)"  # trim whitespace
    [[ -z "$dir" || ! -d "$dir" ]] && continue
    
    # Find matching configs, sort by version (newest first)
    while IFS= read -r config_file; do
      [[ -z "$config_file" ]] && continue
      
      # Extract version from filename
      local file_version
      file_version="$(basename "$config_file" | sed "s/${group_id}_${artifact_id}_//;s/.yaml.json$//")"
      
      # Skip if it's the same version
      [[ "$file_version" == "$current_version" ]] && continue
      
      # Found a previous version
      found_config="$config_file"
      break 2
    done < <(find "$dir" -name "$search_pattern" -type f 2>/dev/null | sort -V -r)
  done
  
  if [[ -n "$found_config" ]]; then
    echo "$found_config"
    return 0
  fi
  
  return 1
}

# Resolve build metadata (script, type, environment) with reuse logic
# Args: group_id artifact_id version config_file
# Returns: BUILD_SCRIPT=... BUILD_TYPE=... ENVIRONMENT_ID=...
resolve_build_metadata() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"
  local config_file="$4"
  
  # Get defaults from config
  local default_script default_build_type default_env_id
  default_script="$(yq -r '.buildConfigGeneratorConfig.defaultValues.buildScript // "mvn -DskipTests clean deploy"' "$config_file" 2>/dev/null || echo "mvn -DskipTests clean deploy")"
  default_build_type="$(yq -r '.buildConfigGeneratorConfig.defaultValues.buildType // "MVN"' "$config_file" 2>/dev/null || echo "MVN")"
  default_env_id="$(yq -r '.buildConfigGeneratorConfig.defaultValues.environmentId // "316"' "$config_file" 2>/dev/null || echo "316")"
  
  # Check if build script reuse is enabled
  local reuse_enabled
  reuse_enabled="$(yq -r '.buildConfigGeneratorConfig.buildScriptReuse.enabled // false' "$config_file" 2>/dev/null || echo "false")"
  
  if [[ "$reuse_enabled" == "true" ]]; then
    local previous_config=""
    local pnc_config=""
    
    # First try PNC if enabled
    if [[ "$(yq -r '.buildConfigGeneratorConfig.buildScriptReuse.pnc.enabled // false' "$config_file" 2>/dev/null || echo "false")" == "true" ]]; then
      pnc_config="$(query_pnc_build_config "$group_id" "$artifact_id" "$version")"
      if [[ -n "$pnc_config" ]]; then
        previous_config="pnc"
      fi
    fi
    
    # Fall back to local search if PNC didn't find anything
    if [[ -z "$previous_config" ]]; then
      local search_dirs
      search_dirs="$(yq -r '.buildConfigGeneratorConfig.buildScriptReuse.searchDirectories // [] | join(",")' "$config_file" 2>/dev/null || echo "")"
      previous_config="$(find_previous_build_config_local "$group_id" "$artifact_id" "$version" "$search_dirs")"
    fi
    
    # Extract metadata from previous config
    if [[ -n "$previous_config" ]]; then
      local prev_script prev_type prev_env_id
      
      if [[ "$previous_config" == "pnc" ]]; then
        # Extract from PNC JSON
        prev_script="$(echo "$pnc_config" | jq -r '.buildScript // ""' 2>/dev/null || echo "")"
        prev_type="$(echo "$pnc_config" | jq -r '.buildType // ""' 2>/dev/null || echo "")"
        prev_env_id="$(echo "$pnc_config" | jq -r '.environment.id // ""' 2>/dev/null || echo "")"
      else
        # Extract from local file
        prev_script="$(jq -r '.buildScript // ""' "$previous_config" 2>/dev/null || echo "")"
        prev_type="$(jq -r '.buildType // ""' "$previous_config" 2>/dev/null || echo "")"
        prev_env_id="$(jq -r '.environmentId // ""' "$previous_config" 2>/dev/null || echo "")"
      fi
      
      # Use previous values if they exist
      [[ -n "$prev_script" ]] && default_script="$prev_script"
      [[ -n "$prev_type" ]] && default_build_type="$prev_type"
      
      # Optionally reuse environment ID
      local reuse_env_id
      reuse_env_id="$(yq -r '.buildConfigGeneratorConfig.buildScriptReuse.reuseEnvironmentId // false' "$config_file" 2>/dev/null || echo "false")"
      if [[ "$reuse_env_id" == "true" && -n "$prev_env_id" && "$prev_env_id" != "null" ]]; then
        default_env_id="$prev_env_id"
      fi
    fi
  fi
  
  echo "BUILD_SCRIPT=$default_script"
  echo "BUILD_TYPE=$default_build_type"
  echo "ENVIRONMENT_ID=$default_env_id"
}

# Generate build report
# Args: output_dir config_file
generate_build_report() {
  local output_dir="$1"
  local config_file="$2"
  local report_file="$output_dir/build-report.txt"
  
  local roots third_party configs unresolved
  roots="$(wc -l < "$output_dir/root-artifacts.txt" 2>/dev/null | tr -d ' ' || echo 0)"
  third_party="$(wc -l < "$output_dir/third-party-dependencies.txt" 2>/dev/null | tr -d ' ' || echo 0)"
  configs="$(find "$output_dir/build-configs" -name '*.yaml.json' 2>/dev/null | wc -l | tr -d ' ' || echo 0)"
  unresolved="$(wc -l < "$output_dir/unresolved-artifacts.txt" 2>/dev/null | tr -d ' ' || echo 0)"
  
  cat > "$report_file" <<REPORT
================================================================================
Build Config Generation Report
================================================================================
Generated: $(date)
Config File: $config_file

Summary:
--------
Root Artifacts: $roots
Third-Party Dependencies: $third_party
Individual Build Configs Generated: $configs
Unresolved SCM Artifacts: $unresolved
Combined YAML: $output_dir/combined-build-configs.yaml

Productization Status:
----------------------
$(if [[ -f "$output_dir/build-from-source.txt" ]]; then
  local build_from_source pending_productized
  build_from_source=$(wc -l < "$output_dir/build-from-source.txt" 2>/dev/null | tr -d ' ' || echo "0")
  pending_productized=$(wc -l < "$output_dir/pending-productized.txt" 2>/dev/null | tr -d ' ' || echo "0")
  echo "Already Productized (.redhat): $build_from_source"
  echo "Pending Productization: $pending_productized"
else
  echo "(Productization check not performed)"
fi)

Files Generated:
----------------
- root-artifacts.txt
- all-dependencies.txt
- third-party-dependencies.txt
- dependency-edges.txt
- unresolved-artifacts.txt
- build-configs/*.yaml.json
- combined-build-configs.yaml
- pig-config.yaml
- build-report.txt
$(if [[ -f "$output_dir/build-from-source.txt" ]]; then
  echo "- build-from-source.txt"
  echo "- pending-productized.txt"
fi)
================================================================================
REPORT
}
