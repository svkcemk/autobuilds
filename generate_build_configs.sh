#!/usr/bin/env bash
# Unified Build Config Generator
# Consolidates all generation scripts into one with feature flags
# Part of the PNC Build Config Generator project

set -euo pipefail

# Script version
VERSION="2.0.0"

# Default configuration
CONFIG_FILE="build-config.yaml"
OUTPUT_DIR="./output"
INPUT_ARTIFACT=""
INPUT_BOM=""
ROOT_ARTIFACTS_FILE=""
EXCLUDE_GROUPS=""
REDHAT_SUFFIX=""
WORK_DIR=""
TEMP_POM=""
UNRESOLVED_FILE=""
ENV_DB_FILE="${ENV_DB_FILE:-./env-database.json}"
VERBOSE="${VERBOSE:-false}"
DRY_RUN=false

# Feature flags (can be overridden by CLI or config)
ENABLE_PNC_INTEGRATION=true
ENABLE_ENV_AUTOSELECT=true
ENABLE_BUILD_SCRIPT_REUSE=true
ENABLE_TOPOLOGICAL_SORT=true
ENABLE_PRODUCTIZATION_CHECK=false
OUTPUT_FORMAT="both"  # individual, combined, or both
LEGACY_MODE=""  # v1, v2, v3 for compatibility

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_verbose() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo -e "${BLUE}[VERBOSE]${NC} $1" >&2
  fi
}

# Show usage
show_usage() {
  cat <<'USAGE'
Unified Build Config Generator v2.0.0

Generate PNC build configurations for Maven artifacts and their dependencies.

Usage:
  ./generate_build_configs.sh [OPTIONS]

Input Options:
  -a, --artifact GAV              Single artifact (groupId:artifactId:version)
  -b, --bom GAV                   BOM for dependency management
  -r, --root-artifacts FILE       File with multiple artifacts (one per line)

Configuration:
  -c, --config FILE               Config file (default: build-config.yaml)
  -o, --output DIR                Output directory (default: ./output)

Feature Flags:
  --no-pnc-integration            Disable PNC queries via bacon CLI
  --no-env-autoselect             Disable environment auto-selection
  --no-build-script-reuse         Disable build script reuse
  --no-topological-sort           Disable topological sorting
  --check-productization          Check if deps already have .redhat versions
  --redhat-suffix SUFFIX          RedHat suffix for productization check
                                  (e.g., redhat-00001)

Output Format:
  --format FORMAT                 Output format: individual|combined|both
                                  (default: both)

Filtering:
  -e, --exclude-groups CSV        Comma-separated groups to exclude
  -i, --include-artifacts PATTERN Include patterns (from config)

Behavior:
  --dry-run                       Show what would be done without executing
  --verbose                       Verbose output
  --parallel N                    Parallel processing (N workers) [NOT IMPLEMENTED]

Compatibility:
  --legacy-mode MODE              Emulate old script: v1|v2|v3

Other:
  -h, --help                      Show this help
  -v, --version                   Show version

Examples:
  # Generate configs for single artifact
  ./generate_build_configs.sh -a com.google.guava:guava:33.0.0

  # Generate with BOM
  ./generate_build_configs.sh -a org.apache.camel:camel-kafka:4.18.1 \
    -b org.apache.camel:camel-bom:4.18.1

  # Generate from file
  ./generate_build_configs.sh -r artifacts.txt -o ./my-output

  # Dry run with verbose
  ./generate_build_configs.sh -a com.google.gson:gson:2.10.1 \
    --dry-run --verbose

  # Disable PNC integration
  ./generate_build_configs.sh -a com.google.guava:guava:33.0.0 \
    --no-pnc-integration

  # Only individual configs (no combined YAML)
  ./generate_build_configs.sh -a com.google.guava:guava:33.0.0 \
    --format individual

Documentation:
  See README.md for detailed documentation
  See SCRIPT_CONSOLIDATION_ANALYSIS.md for consolidation details

USAGE
  exit 0
}

# Show version
show_version() {
  echo "Unified Build Config Generator v${VERSION}"
  exit 0
}

# Cleanup on exit
cleanup() {
  [[ -n "${TEMP_POM:-}" && -f "${TEMP_POM:-}" ]] && rm -f "$TEMP_POM"
  [[ -n "${WORK_DIR:-}" && -d "${WORK_DIR:-}" ]] && rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a|--artifact) INPUT_ARTIFACT="$2"; shift 2 ;;
      -b|--bom) INPUT_BOM="$2"; shift 2 ;;
      -r|--root-artifacts) ROOT_ARTIFACTS_FILE="$2"; shift 2 ;;
      -e|--exclude-groups) EXCLUDE_GROUPS="$2"; shift 2 ;;
      -c|--config) CONFIG_FILE="$2"; shift 2 ;;
      -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
      --no-pnc-integration) ENABLE_PNC_INTEGRATION=false; shift ;;
      --no-env-autoselect) ENABLE_ENV_AUTOSELECT=false; shift ;;
      --no-build-script-reuse) ENABLE_BUILD_SCRIPT_REUSE=false; shift ;;
      --no-topological-sort) ENABLE_TOPOLOGICAL_SORT=false; shift ;;
      --check-productization) ENABLE_PRODUCTIZATION_CHECK=true; shift ;;
      --redhat-suffix) 
        if [[ ! "$2" =~ ^redhat- ]]; then
          log_error "Invalid --redhat-suffix: must be in format 'redhat-XXXX' or 'redhat-*' for wildcard (e.g., redhat-00001, redhat-0001, redhat-*)"
          exit 1
        fi
        REDHAT_SUFFIX="$2"
        shift 2
        ;;
      --format) OUTPUT_FORMAT="$2"; shift 2 ;;
      --dry-run) DRY_RUN=true; shift ;;
      --verbose) VERBOSE=true; shift ;;
      --legacy-mode) LEGACY_MODE="$2"; shift 2 ;;
      -h|--help) show_usage ;;
      -v|--version) show_version ;;
      *) log_error "Unknown option: $1"; show_usage ;;
    esac
  done
}

# Check prerequisites
check_prerequisites() {
  local missing=()
  
  command -v bash >/dev/null 2>&1 || missing+=("bash")
  command -v curl >/dev/null 2>&1 || missing+=("curl")
  command -v python3 >/dev/null 2>&1 || missing+=("python3")
  command -v mvn >/dev/null 2>&1 || missing+=("mvn")
  command -v yq >/dev/null 2>&1 || missing+=("yq")
  
  if [[ "$ENABLE_ENV_AUTOSELECT" == "true" ]]; then
    command -v jq >/dev/null 2>&1 || missing+=("jq (required for env auto-selection)")
  fi
  
  if [[ "$ENABLE_PNC_INTEGRATION" == "true" ]]; then
    command -v bacon >/dev/null 2>&1 || {
      log_warn "bacon CLI not found. PNC integration will be disabled."
      ENABLE_PNC_INTEGRATION=false
    }
  fi
  
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required tools: ${missing[*]}"
    exit 1
  fi
  
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
  fi
  
  # Initialize environment database if auto-selection enabled
  if [[ "$ENABLE_ENV_AUTOSELECT" == "true" && ! -f "$ENV_DB_FILE" ]]; then
    log_info "Generating environment database from env.txt..."
    if [[ -f "env.txt" && -f "env_parser.sh" ]]; then
      ./env_parser.sh -i env.txt -o "$ENV_DB_FILE" >/dev/null 2>&1 || {
        log_warn "Failed to generate environment database. Auto-selection disabled."
        ENABLE_ENV_AUTOSELECT=false
      }
    else
      log_warn "env.txt or env_parser.sh not found. Auto-selection disabled."
      ENABLE_ENV_AUTOSELECT=false
    fi
  fi
  
  # Source shared libraries
  local lib_dir="$(dirname "$0")/lib"
  if [[ -f "$lib_dir/scm_resolver.sh" ]]; then
    source "$lib_dir/scm_resolver.sh"
  else
    log_error "Required library not found: $lib_dir/scm_resolver.sh"
    exit 1
  fi
  
  if [[ -f "$lib_dir/dependency_analyzer.sh" ]]; then
    source "$lib_dir/dependency_analyzer.sh"
  else
    log_error "Required library not found: $lib_dir/dependency_analyzer.sh"
    exit 1
  fi
  
  if [[ -f "$lib_dir/config_generator.sh" ]]; then
    source "$lib_dir/config_generator.sh"
  else
    log_error "Required library not found: $lib_dir/config_generator.sh"
    exit 1
  fi
}

# Validate inputs
validate_inputs() {
  if [[ -n "$INPUT_ARTIFACT" ]] && ! validate_gav "$INPUT_ARTIFACT"; then
    log_error "Invalid --artifact GAV: $INPUT_ARTIFACT"
    exit 1
  fi

  if [[ -n "$INPUT_BOM" ]] && ! validate_gav "$INPUT_BOM"; then
    log_error "Invalid --bom GAV: $INPUT_BOM"
    exit 1
  fi

  if [[ -z "$INPUT_ARTIFACT" && -z "$ROOT_ARTIFACTS_FILE" ]]; then
    log_error "Provide --artifact or --root-artifacts"
    exit 1
  fi

  if [[ -n "$ROOT_ARTIFACTS_FILE" && ! -f "$ROOT_ARTIFACTS_FILE" ]]; then
    log_error "Root artifacts file not found: $ROOT_ARTIFACTS_FILE"
    exit 1
  fi
  
  if [[ "$OUTPUT_FORMAT" != "individual" && "$OUTPUT_FORMAT" != "combined" && "$OUTPUT_FORMAT" != "both" ]]; then
    log_error "Invalid --format: $OUTPUT_FORMAT (must be: individual, combined, or both)"
    exit 1
  fi
}

# Prepare workspace
prepare_workspace() {
  mkdir -p "$OUTPUT_DIR/build-configs"
  : > "$OUTPUT_DIR/root-artifacts.txt"
  : > "$OUTPUT_DIR/all-dependencies.txt"
  : > "$OUTPUT_DIR/third-party-dependencies.txt"
  : > "$OUTPUT_DIR/dependency-edges.txt"
  : > "$OUTPUT_DIR/unresolved-artifacts.txt"
  UNRESOLVED_FILE="$OUTPUT_DIR/unresolved-artifacts.txt"
  WORK_DIR="$(mktemp -d)"
}

# Load effective exclude groups
load_effective_exclude_groups() {
  local config_groups cli_groups merged
  config_groups="$(yq -r '.dependencyResolutionConfig.excludeGroups // [] | join(",")' "$CONFIG_FILE" 2>/dev/null || true)"
  cli_groups="$EXCLUDE_GROUPS"
  merged="$(printf '%s\n%s\n' "$cli_groups" "$config_groups" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d' | sort -u | paste -sd, -)"
  EXCLUDE_GROUPS="$merged"
  log_verbose "Effective exclude groups: $EXCLUDE_GROUPS"
}

# Main workflow
main() {
  log_info "Unified Build Config Generator v${VERSION}"
  
  parse_args "$@"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY RUN MODE - No changes will be made"
  fi
  
  check_prerequisites
  validate_inputs
  
  log_info "Configuration:"
  log_info "  Config File: $CONFIG_FILE"
  log_info "  Output Dir: $OUTPUT_DIR"
  log_info "  PNC Integration: $ENABLE_PNC_INTEGRATION"
  log_info "  Env Auto-Select: $ENABLE_ENV_AUTOSELECT"
  log_info "  Build Script Reuse: $ENABLE_BUILD_SCRIPT_REUSE"
  log_info "  Topological Sort: $ENABLE_TOPOLOGICAL_SORT"
  log_info "  Productization Check: $ENABLE_PRODUCTIZATION_CHECK"
  log_info "  Output Format: $OUTPUT_FORMAT"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry run complete. No files were created."
    exit 0
  fi
  
  prepare_workspace
  load_effective_exclude_groups
  
  # Load root artifacts
  log_info "Loading root artifacts..."
  if [[ -n "$INPUT_ARTIFACT" ]]; then
    echo "$INPUT_ARTIFACT" >> "$OUTPUT_DIR/root-artifacts.txt"
  fi
  if [[ -n "$ROOT_ARTIFACTS_FILE" ]]; then
    load_root_artifacts "$ROOT_ARTIFACTS_FILE" "$OUTPUT_DIR/root-artifacts.txt"
  fi
  
  # Analyze dependencies
  log_info "Analyzing dependencies..."
  local input_type input_value
  if [[ -n "$INPUT_ARTIFACT" ]] && [[ -z "$ROOT_ARTIFACTS_FILE" ]]; then
    # Single artifact - use artifact type for BOM detection
    input_type="artifact"
    input_value="$INPUT_ARTIFACT"
  else
    # Multiple artifacts from file
    input_type="file"
    input_value="$OUTPUT_DIR/root-artifacts.txt"
  fi
  analyze_dependencies "$input_type" "$input_value" "$OUTPUT_DIR" "$CONFIG_FILE"
  
  # Filter third-party dependencies
  log_info "Filtering third-party dependencies..."
  filter_dependencies \
    "$OUTPUT_DIR/all-dependencies.txt" \
    "$OUTPUT_DIR/root-artifacts.txt" \
    "$EXCLUDE_GROUPS" \
    "$OUTPUT_DIR/third-party-dependencies.txt" \
    "$OUTPUT_DIR/dependency-edges.txt"
  
  # Topological sort if enabled
  if [[ "$ENABLE_TOPOLOGICAL_SORT" == "true" ]]; then
    log_info "Performing topological sort..."
    topological_sort \
      "$OUTPUT_DIR/third-party-dependencies.txt" \
      "$OUTPUT_DIR/dependency-edges.txt" \
      "$OUTPUT_DIR/third-party-dependencies-sorted.txt"
    mv "$OUTPUT_DIR/third-party-dependencies-sorted.txt" "$OUTPUT_DIR/third-party-dependencies.txt"
  fi
  
  # Check productization status if enabled
  if [[ "$ENABLE_PRODUCTIZATION_CHECK" == "true" ]]; then
    log_info "Checking productization status..."
    
    # Use provided suffix or try to extract from root version
    local suffix="$REDHAT_SUFFIX"
    if [[ -z "$suffix" ]]; then
      local root_version
      root_version="$(head -1 "$OUTPUT_DIR/root-artifacts.txt" | cut -d: -f3)"
      suffix="$(echo "$root_version" | grep -o 'redhat-[0-9]*' || echo "")"
    fi
    
    if [[ -z "$suffix" ]]; then
      log_warn "No --redhat-suffix provided and root version has no .redhat suffix"
      log_warn "Skipping productization check. Use --redhat-suffix to specify (e.g., redhat-00001)"
    else
      log_info "Using RedHat suffix: $suffix"
      local prod_stats
      prod_stats="$(check_productization \
        "$OUTPUT_DIR/third-party-dependencies.txt" \
        "$suffix" \
        "$OUTPUT_DIR" \
        "$VERBOSE")"
      
      # Stats are returned as "build_from_source:pending_productized"
      local build_from_source pending_productized
      build_from_source="$(echo "$prod_stats" | cut -d: -f1)"
      pending_productized="$(echo "$prod_stats" | cut -d: -f2)"
      
      log_info "Productization Summary:"
      log_info "  Already productized (.redhat): $build_from_source"
      log_info "  Need to be built: $pending_productized"
    fi
  fi
  
  # Generate individual configs if requested
  if [[ "$OUTPUT_FORMAT" == "individual" || "$OUTPUT_FORMAT" == "both" ]]; then
    log_info "Generating individual build configs..."
    generate_individual_configs
  fi
  
  # Generate combined YAML if requested
  if [[ "$OUTPUT_FORMAT" == "combined" || "$OUTPUT_FORMAT" == "both" ]]; then
    log_info "Generating combined YAML..."
    generate_combined_yaml_wrapper
  fi
  
  # Generate PIG config
  log_info "Generating PIG config..."
  generate_pig_config "$CONFIG_FILE" "$OUTPUT_DIR/pig-config.yaml"
  
  # Generate report
  log_info "Generating build report..."
  generate_build_report "$OUTPUT_DIR" "$CONFIG_FILE"
  
  log_success "Done! Output written to $OUTPUT_DIR"
  log_info "Summary:"
  cat "$OUTPUT_DIR/build-report.txt"
}

# Generate individual configs (wrapper for library function)
generate_individual_configs() {
  : > "$UNRESOLVED_FILE"
  
  while IFS= read -r gav || [[ -n "$gav" ]]; do
    [[ -z "$gav" ]] && continue
    
    local group_id artifact_id version
    group_id="$(echo "$gav" | cut -d: -f1)"
    artifact_id="$(echo "$gav" | cut -d: -f2)"
    version="$(echo "$gav" | cut -d: -f3)"
    
    log_verbose "Processing: $gav"
    
    # Resolve SCM
    local scm_data
    if ! scm_data="$(resolve_scm "$group_id" "$artifact_id" "$version")"; then
      log_warn "Failed to resolve SCM for $gav"
      echo "$gav" >> "$UNRESOLVED_FILE"
      continue
    fi
    
    local scm_url scm_revision
    scm_url="$(echo "$scm_data" | awk -F= '/^SCM_URL=/{print substr($0,9)}')"
    scm_revision="$(echo "$scm_data" | awk -F= '/^SCM_REVISION=/{print substr($0,14)}')"
    
    # Resolve build metadata
    local metadata
    metadata="$(resolve_build_metadata "$group_id" "$artifact_id" "$version" "$CONFIG_FILE")"
    
    local build_script build_type environment_id
    build_script="$(echo "$metadata" | awk -F= '/^BUILD_SCRIPT=/{print substr($0,14)}')"
    build_type="$(echo "$metadata" | awk -F= '/^BUILD_TYPE=/{print substr($0,12)}')"
    environment_id="$(echo "$metadata" | awk -F= '/^ENVIRONMENT_ID=/{print substr($0,16)}')"
    
    # Generate config
    local config_name="${group_id}_${artifact_id}_${version}"
    local config_file="$OUTPUT_DIR/build-configs/${config_name}.yaml.json"
    
    generate_build_config \
      "$config_name" \
      "$artifact_id" \
      "Auto-generated build config for $gav" \
      "$scm_url" \
      "$scm_revision" \
      "$build_type" \
      "$environment_id" \
      "$build_script" \
      "$config_file"
    
  done < "$OUTPUT_DIR/third-party-dependencies.txt"
  
  # Check for unresolved
  if [[ -s "$UNRESOLVED_FILE" ]]; then
    log_error "Failed to resolve SCM for $(wc -l < "$UNRESOLVED_FILE" | tr -d ' ') artifacts"
    log_error "See: $UNRESOLVED_FILE"
    exit 1
  fi
}

# Generate combined YAML (wrapper)
generate_combined_yaml_wrapper() {
  local product_name product_abbreviation product_stage version milestone group release_file release_dir
  local default_build_type default_environment_id default_build_script
  
  product_name="$(yq -r '.buildConfigGeneratorConfig.pigTemplate.product.name // "Generated Product"' "$CONFIG_FILE")"
  product_abbreviation="$(yq -r '.buildConfigGeneratorConfig.pigTemplate.product.abbreviation // "generated"' "$CONFIG_FILE")"
  product_stage="$(yq -r '.buildConfigGeneratorConfig.pigTemplate.product.stage // "GA"' "$CONFIG_FILE")"
  version="$(yq -r '.buildConfigGeneratorConfig.pigTemplate.version // "1.0.0"' "$CONFIG_FILE")"
  milestone="$(yq -r '.buildConfigGeneratorConfig.pigTemplate.milestone // "DR1"' "$CONFIG_FILE")"
  group="$(yq -r '.buildConfigGeneratorConfig.pigTemplate.group // "generated-group"' "$CONFIG_FILE")"
  release_file="$(yq -r '.buildConfigGeneratorConfig.pigTemplate.outputPrefixes.releaseFile // "generated"' "$CONFIG_FILE")"
  release_dir="$(yq -r '.buildConfigGeneratorConfig.pigTemplate.outputPrefixes.releaseDir // "generated"' "$CONFIG_FILE")"
  default_build_type="$(yq -r '.buildConfigGeneratorConfig.defaultValues.buildType // "MVN"' "$CONFIG_FILE")"
  default_environment_id="$(yq -r '.buildConfigGeneratorConfig.defaultValues.environmentId // "316"' "$CONFIG_FILE")"
  default_build_script="$(yq -r '.buildConfigGeneratorConfig.defaultValues.buildScript // "mvn -DskipTests clean deploy"' "$CONFIG_FILE")"
  
  generate_combined_yaml \
    "$OUTPUT_DIR/third-party-dependencies.txt" \
    "$OUTPUT_DIR/dependency-edges.txt" \
    "$OUTPUT_DIR/build-configs" \
    "$OUTPUT_DIR/combined-build-configs.yaml" \
    "$product_name" \
    "$product_abbreviation" \
    "$product_stage" \
    "$version" \
    "$milestone" \
    "$group" \
    "$release_file" \
    "$release_dir" \
    "$default_build_type" \
    "$default_environment_id" \
    "$default_build_script"
}

# Run main
main "$@"
