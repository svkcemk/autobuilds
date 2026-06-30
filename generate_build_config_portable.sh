#!/bin/bash
set -euo pipefail

CONFIG_FILE="build-config.yaml"
OUTPUT_DIR="./generated-configs"
ARTIFACT_FILE=""
declare -a ARTIFACTS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

show_usage() {
  cat <<'USAGE'
Portable build-config generator

Usage:
  ./generate_build_config_portable.sh [OPTIONS]

Options:
  -a, --artifact GAV       Maven artifact in groupId:artifactId:version format
                           Can be repeated multiple times
  -f, --artifact-file FILE File containing one GAV per line
  -c, --config FILE        Config file (default: build-config.yaml)
  -o, --output DIR         Output directory (default: ./generated-configs)
  -h, --help               Show this help message

Examples:
  ./generate_build_config_portable.sh \
    --artifact org.apache.camel.quarkus:camel-quarkus-google-pubsub:3.33.0 \
    --artifact org.apache.camel.quarkus:camel-quarkus-jira:3.33.0 \
    --output ./out

  ./generate_build_config_portable.sh \
    --artifact-file ./artifacts.txt \
    --output ./out
USAGE
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a|--artifact)
        ARTIFACTS+=("$2")
        shift 2
        ;;
      -f|--artifact-file)
        ARTIFACT_FILE="$2"
        shift 2
        ;;
      -c|--config)
        CONFIG_FILE="$2"
        shift 2
        ;;
      -o|--output)
        OUTPUT_DIR="$2"
        shift 2
        ;;
      -h|--help)
        show_usage
        ;;
      *)
        log_error "Unknown option: $1"
        show_usage
        ;;
    esac
  done
}

install_yq_if_possible() {
  if command -v yq >/dev/null 2>&1; then
    return 0
  fi

  log_warn "yq not found. Attempting installation..."

  if command -v brew >/dev/null 2>&1; then
    brew install yq && return 0
  fi

  if command -v pip3 >/dev/null 2>&1; then
    pip3 install yq && return 0
  fi

  log_error "Could not install yq automatically. Install it manually and retry."
  exit 1
}

check_prerequisites() {
  log_info "Checking prerequisites..."

  command -v bash >/dev/null 2>&1 || { log_error "bash is required"; exit 1; }
  command -v curl >/dev/null 2>&1 || { log_error "curl is required"; exit 1; }
  command -v python3 >/dev/null 2>&1 || { log_error "python3 is required"; exit 1; }
  command -v mvn >/dev/null 2>&1 || { log_error "mvn is required"; exit 1; }

  install_yq_if_possible

  if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
  fi

  log_success "All prerequisites met"
}

load_artifacts_from_file() {
  if [[ -z "$ARTIFACT_FILE" ]]; then
    return 0
  fi

  if [[ ! -f "$ARTIFACT_FILE" ]]; then
    log_error "Artifact file not found: $ARTIFACT_FILE"
    exit 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(echo "$line" | sed 's/#.*$//' | xargs)"
    [[ -z "$line" ]] && continue
    ARTIFACTS+=("$line")
  done < "$ARTIFACT_FILE"
}

validate_gav() {
  local gav="$1"
  [[ "$gav" =~ ^[^:]+:[^:]+:[^:]+$ ]]
}

normalise_artifacts() {
  if [[ ${#ARTIFACTS[@]} -eq 0 ]]; then
    log_error "No artifacts provided. Use --artifact or --artifact-file."
    exit 1
  fi

  local tmp_file
  tmp_file="$(mktemp)"

  for gav in "${ARTIFACTS[@]}"; do
    if ! validate_gav "$gav"; then
      log_error "Invalid GAV format: $gav"
      log_error "Expected: groupId:artifactId:version"
      rm -f "$tmp_file"
      exit 1
    fi
    echo "$gav" >> "$tmp_file"
  done

  ARTIFACTS=()
  while IFS= read -r gav || [[ -n "$gav" ]]; do
    [[ -z "$gav" ]] && continue
    ARTIFACTS+=("$gav")
  done < <(sort -u "$tmp_file")
  rm -f "$tmp_file"

  log_success "Loaded ${#ARTIFACTS[@]} unique artifact(s)"
}

get_default_value() {
  local query="$1"
  local fallback="$2"
  local value
  value="$(yq -r "$query // \"\"" "$CONFIG_FILE" 2>/dev/null || true)"
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "$fallback"
  else
    echo "$value"
  fi
}

fetch_scm_from_maven() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"

  local group_path
  group_path="$(echo "$group_id" | tr '.' '/')"
  local pom_url="https://repo1.maven.org/maven2/${group_path}/${artifact_id}/${version}/${artifact_id}-${version}.pom"

  local pom_content
  pom_content="$(curl -fsSL "$pom_url" 2>/dev/null || true)"

  if [[ -z "$pom_content" ]]; then
    return 1
  fi

  local scm_url
  scm_url="$(echo "$pom_content" | grep -oE '<connection>[^<]+' | head -1 | sed 's/<connection>//' | sed 's#^scm:git:##' | sed 's#^scm:git://##' | sed 's#^scm:svn:##')"

  local scm_tag
  scm_tag="$(echo "$pom_content" | grep -oE '<tag>[^<]+' | head -1 | sed 's/<tag>//')"

  if [[ -z "$scm_tag" ]]; then
    scm_tag="$(echo "$pom_content" | grep -oE '<revision>[^<]+' | head -1 | sed 's/<revision>//')"
  fi

  [[ -z "$scm_tag" ]] && scm_tag="$version"

  if [[ -n "$scm_url" ]]; then
    echo "SCM_URL=$scm_url"
    echo "SCM_REVISION=$scm_tag"
    return 0
  fi

  return 1
}

resolve_metadata() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"

  local default_env
  default_env="$(get_default_value '.buildConfigGeneratorConfig.defaultValues.environmentName' 'OpenJDK 11.0; Mvn 3.5.4')"

  local default_script
  default_script="$(get_default_value '.buildConfigGeneratorConfig.defaultValues.buildScript' 'mvn -Dmaven.test.skip=true -Dartifactory.staging.skip=true -DskipNexusStagingDeployMojo=true clean deploy')"

  local default_build_type
  default_build_type="$(get_default_value '.buildConfigGeneratorConfig.defaultValues.buildType' 'MVN')"

  local scm_url=""
  local scm_revision="$version"

  local scm_data
  scm_data="$(fetch_scm_from_maven "$group_id" "$artifact_id" "$version" || true)"

  if [[ -n "$scm_data" ]]; then
    scm_url="$(echo "$scm_data" | awk -F= '/^SCM_URL=/{print substr($0,9)}')"
    local resolved_revision
    resolved_revision="$(echo "$scm_data" | awk -F= '/^SCM_REVISION=/{print substr($0,14)}')"
    [[ -n "$resolved_revision" ]] && scm_revision="$resolved_revision"
  fi

  if [[ -z "$scm_url" ]]; then
    scm_url="https://github.com/placeholder/${artifact_id}.git"
  fi

  echo "SCM_URL=$scm_url"
  echo "SCM_REVISION=$scm_revision"
  echo "BUILD_SCRIPT=$default_script"
  echo "BUILD_TYPE=$default_build_type"
  echo "ENVIRONMENT=$default_env"
}

prepare_output() {
  mkdir -p "$OUTPUT_DIR/build-configs"
  : > "$OUTPUT_DIR/all-dependencies.txt"
  : > "$OUTPUT_DIR/filtered-dependencies.txt"
}

generate_yaml_for_artifact() {
  local gav="$1"

  local group_id artifact_id version
  group_id="$(echo "$gav" | cut -d: -f1)"
  artifact_id="$(echo "$gav" | cut -d: -f2)"
  version="$(echo "$gav" | cut -d: -f3)"

  echo "$gav" >> "$OUTPUT_DIR/all-dependencies.txt"
  echo "$gav" >> "$OUTPUT_DIR/filtered-dependencies.txt"

  local metadata
  metadata="$(resolve_metadata "$group_id" "$artifact_id" "$version")"

  local scm_url scm_revision build_script build_type environment
  scm_url="$(echo "$metadata" | awk -F= '/^SCM_URL=/{print substr($0,9)}')"
  scm_revision="$(echo "$metadata" | awk -F= '/^SCM_REVISION=/{print substr($0,14)}')"
  build_script="$(echo "$metadata" | awk -F= '/^BUILD_SCRIPT=/{print substr($0,14)}')"
  build_type="$(echo "$metadata" | awk -F= '/^BUILD_TYPE=/{print substr($0,12)}')"
  environment="$(echo "$metadata" | awk -F= '/^ENVIRONMENT=/{print substr($0,13)}')"

  local config_name="${group_id}_${artifact_id}-${version}"
  local config_file="$OUTPUT_DIR/build-configs/${config_name}.yaml"

  cat > "$config_file" <<YAML
name: $config_name
description: Auto-generated build config for $gav
scmRepository:
  url: $scm_url
  revision: $scm_revision
buildScript: $build_script
environment:
  name: $environment
buildType: $build_type
YAML
}

generate_pig_config() {
  local pig_file="$OUTPUT_DIR/pig-config.yaml"
  if yq -e '.buildConfigGeneratorConfig.pigTemplate' "$CONFIG_FILE" >/dev/null 2>&1; then
    yq -r '.buildConfigGeneratorConfig.pigTemplate' "$CONFIG_FILE" > "$pig_file"
  else
    cat > "$pig_file" <<'YAML'
product:
  name: Generated Product
  abbreviation: generated-product
version: 1.0.0
milestone: DR1
YAML
  fi
}

generate_report() {
  local report_file="$OUTPUT_DIR/build-report.txt"
  local total_deps
  total_deps="$(wc -l < "$OUTPUT_DIR/all-dependencies.txt" | tr -d ' ')"
  local filtered_deps
  filtered_deps="$(wc -l < "$OUTPUT_DIR/filtered-dependencies.txt" | tr -d ' ')"
  local configs
  configs="$(find "$OUTPUT_DIR/build-configs" -name '*.yaml' | wc -l | tr -d ' ')"

  cat > "$report_file" <<REPORT
================================================================================
Portable Build Config Generation Report
================================================================================
Generated: $(date)
Config File: $CONFIG_FILE

Summary:
--------
Total Artifacts Provided: $total_deps
Artifacts After Normalisation: $filtered_deps
Build Configs Generated: $configs

Output Directory: $OUTPUT_DIR

Files Generated:
----------------
- all-dependencies.txt: All requested artifacts
- filtered-dependencies.txt: Normalised unique artifacts
- build-configs/: Individual build configuration YAML files
- pig-config.yaml: Product Integration Group configuration
- build-report.txt: This report

Notes:
------
- SCM URLs are resolved from Maven Central POM when available
- Placeholder SCM URLs are used when SCM metadata is unavailable
- This workflow does not require bob or bacon for generation
================================================================================
REPORT
}

main() {
  parse_args "$@"
  check_prerequisites
  load_artifacts_from_file
  normalise_artifacts
  prepare_output

  for gav in "${ARTIFACTS[@]}"; do
    log_info "Generating config for $gav"
    generate_yaml_for_artifact "$gav"
  done

  generate_pig_config
  generate_report

  log_success "Done. Output written to $OUTPUT_DIR"
}

main "$@"
