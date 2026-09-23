#!/usr/bin/env bash
# AI-Enhanced Build Metadata Resolution
# Produces deterministic metadata overrides for environment/build script selection
# Part of the AI-Assisted Productization Tool

set -euo pipefail

TRAINING_DATA_FILE="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/lib/ai/ai-build-metadata-training.jsonl"

artifact_pattern_matches() {
  local pattern="$1"
  local value="$2"

  if [[ "$pattern" == "*" || -z "$pattern" ]]; then
    return 0
  fi

  [[ "$value" == $pattern ]]
}

lookup_training_metadata() {
  local group_id="$1"
  local artifact_id="$2"
  local scm_url="$3"

  [[ -f "$TRAINING_DATA_FILE" ]] || return 1

  python3 - "$TRAINING_DATA_FILE" "$group_id" "$artifact_id" "$scm_url" <<'PY'
import json
import sys
from pathlib import Path
from fnmatch import fnmatch

path = Path(sys.argv[1])
group_id = sys.argv[2]
artifact_id = sys.argv[3]
scm_url = sys.argv[4]

for raw in path.read_text().splitlines():
    raw = raw.strip()
    if not raw:
        continue
    try:
        row = json.loads(raw)
    except Exception:
        continue

    row_group = row.get("groupId", "")
    row_artifact_pattern = row.get("artifactIdPattern", "*")
    row_scm_pattern = row.get("scmUrlPattern", "")

    if row_group != group_id:
        continue
    if not fnmatch(artifact_id, row_artifact_pattern):
        continue
    if row_scm_pattern and row_scm_pattern != scm_url:
        continue

    print(f"BUILD_SCRIPT={row.get('buildScript', '')}")
    print(f"BUILD_TYPE={row.get('buildType', 'MVN')}")
    print(f"ENVIRONMENT_ID={row.get('environmentId', '')}")
    ap = row.get('alignmentParameters', [])
    print(f"ALIGNMENT_PARAMETERS={' '.join(ap) if isinstance(ap, list) else ap}")
    print(f"CONFIDENCE={row.get('confidence', 'medium')}")
    print(f"REASON={row.get('reason', 'Matched training data')}")
    print("SOURCE=training-data")
    sys.exit(0)

sys.exit(1)
PY
}

# Resolve build metadata using training lookup first, then lightweight heuristics.
# Args: group_id artifact_id version scm_url config_file
# Returns:
#   BUILD_SCRIPT=...
#   BUILD_TYPE=...
#   ENVIRONMENT_ID=...
#   CONFIDENCE=high|medium|low
#   REASON=...
#   SOURCE=ai|training-data
ai_resolve_build_metadata() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"
  local scm_url="$4"
  local config_file="$5"

  local training_match=""
  training_match="$(lookup_training_metadata "$group_id" "$artifact_id" "$scm_url" 2>/dev/null || true)"
  if [[ -n "$training_match" ]]; then
    echo "$training_match"
    return 0
  fi

  # Use pre-exported defaults when available (set once in generate_build_configs.sh)
  # to avoid 3 yq subprocess forks per artifact.
  local default_script default_build_type default_env_id
  default_script="${_AI_DEFAULT_BUILD_SCRIPT:-$(yq -r '.buildConfigGeneratorConfig.defaultValues.buildScript // "mvn -DskipTests clean deploy"' "$config_file" 2>/dev/null || echo "mvn -DskipTests clean deploy")}"
  default_build_type="${_AI_DEFAULT_BUILD_TYPE:-$(yq -r '.buildConfigGeneratorConfig.defaultValues.buildType // "MVN"' "$config_file" 2>/dev/null || echo "MVN")}"
  default_env_id="${_AI_DEFAULT_ENV_ID:-$(yq -r '.buildConfigGeneratorConfig.defaultValues.environmentId // "316"' "$config_file" 2>/dev/null || echo "316")}"

  local build_script="$default_script"
  local build_type="$default_build_type"
  local environment_id="$default_env_id"
  local confidence="medium"
  local reason="Fallback AI metadata based on default Maven Java library profile"

  if [[ "$group_id" == "io.netty" ]] || [[ "$artifact_id" == *"native"* ]] || [[ "$artifact_id" == *"epoll"* ]] || [[ "$artifact_id" == *"kqueue"* ]]; then
    environment_id="$default_env_id"
    build_script="mvn -DskipTests clean deploy"
    confidence="medium"
    reason="Netty/native-style artifact detected; keeping standard Maven build script and default environment"
  fi

  if [[ "$artifact_id" == *"annotations"* ]] || [[ "$artifact_id" == "jspecify" ]] || [[ "$artifact_id" == "reactive-streams" ]]; then
    environment_id="$default_env_id"
    build_script="mvn -DskipTests clean deploy"
    confidence="high"
    reason="Annotation/API-only Java library detected; standard Maven deploy profile is appropriate"
  fi

  if [[ "$group_id" == "org.apache.httpcomponents.core5" ]]; then
    environment_id="$default_env_id"
    build_script="mvn -DskipTests clean deploy"
    confidence="high"
    reason="Apache HttpComponents Core artifact detected; standard Maven deploy profile is appropriate"
  fi

  if [[ "$group_id" == "com.google.errorprone" ]]; then
    environment_id="$default_env_id"
    build_script="mvn -DskipTests clean deploy"
    confidence="medium"
    reason="Error Prone artifact detected; using standard Maven deploy profile for current workflow"
  fi

  echo "BUILD_SCRIPT=$build_script"
  echo "BUILD_TYPE=$build_type"
  echo "ENVIRONMENT_ID=$environment_id"
  echo "CONFIDENCE=$confidence"
  echo "REASON=$reason"
  echo "SOURCE=ai"
}