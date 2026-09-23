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
DIRECT_ARTIFACTS=false
EXCLUDE_GROUPS=""
REDHAT_SUFFIX=""
WORK_DIR=""
TEMP_POM=""
UNRESOLVED_FILE=""
AI_REVIEW_FILE=""
AI_OVERRIDES_FILE=""
ENV_DB_FILE="${ENV_DB_FILE:-./env-database.json}"
VERBOSE="${VERBOSE:-false}"
DRY_RUN=false

# Feature flags (can be overridden by CLI or config)
ENABLE_PNC_INTEGRATION=true
ENABLE_ENV_AUTOSELECT=true
ENABLE_BUILD_SCRIPT_REUSE=true
ENABLE_TOPOLOGICAL_SORT=true
ENABLE_PRODUCTIZATION_CHECK=false
ENABLE_AI_ASSISTANT=true
ENABLE_BOM_EXPANSION=false
ENABLE_CACHE=true   # Enable persistent caching
ENABLE_INCREMENTAL=true  # Enable incremental processing
FORCE_FULL_REPROCESS=false  # Force full reprocessing (ignore incremental state)
OUTPUT_FORMAT="both"  # individual, combined, or both
LEGACY_MODE=""  # v1, v2, v3 for compatibility
# Auto-detect logical CPU count; fall back to 4 if detection fails
PARALLEL_WORKERS=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
MAX_PARALLEL_WORKERS=20  # Maximum parallel workers for productization checks

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

# Check for PNC hanging issues and warn user
check_pnc_hanging_warning() {
  if [[ "$ENABLE_PNC_INTEGRATION" == "true" && "${SKIP_PNC_QUERIES:-false}" != "true" ]]; then
    if command -v bacon &> /dev/null; then
      log_warn "PNC Integration is enabled. This may cause hanging issues with some artifacts."
      log_warn "If the script hangs, press Ctrl+C and use one of these workarounds:"
      log_warn "  1. SKIP_PNC_QUERIES=true ./generate_build_configs.sh [options]"
      log_warn "  2. ./generate_build_configs.sh --no-pnc-integration [options]"
      log_warn "  3. Use test-config.yaml: -c test-config.yaml"
      echo ""
      sleep 2  # Give user time to read the warning
    fi
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
      --direct-artifacts           Productize the supplied artifacts only; do not resolve transitives

Configuration:
  -c, --config FILE               Config file (default: build-config.yaml)
  -o, --output DIR                Output directory (default: ./output)

Feature Flags:
  --no-pnc-integration            Disable PNC queries via bacon CLI
  --no-env-autoselect             Disable environment auto-selection
  --no-build-script-reuse         Disable build script reuse
  --no-topological-sort           Disable topological sorting
  --check-productization          Check if deps already have .redhat versions
  --expand-bom                    Expand BOM to include all managed dependencies
  --redhat-suffix SUFFIX          RedHat suffix for productization check
                                  (e.g., redhat-00001)
  --enable-ai-assistant           Enable AI-powered SCM resolution (default: on)
  --no-ai-assistant               Disable AI-powered SCM resolution

Performance:
  --use-cache                     Enable persistent caching (faster reruns)
  --clear-cache                   Clear all caches before running
  --cache-dir DIR                 Cache directory (default: ~/.bob/cache)
  --incremental                   Enable incremental processing (skip unchanged)
  --force-full                    Force full reprocessing (ignore incremental state)
  --max-parallel N                Max parallel workers for checks (default: 20)

Output Format:
  --format FORMAT                 Output format: individual|combined|both
                                  (default: both)

Filtering:
  -e, --exclude-groups CSV        Comma-separated groups to exclude
  -i, --include-artifacts PATTERN Include patterns (from config)

Behavior:
  --dry-run                       Show what would be done without executing
  --verbose                       Verbose output
  --parallel N                    Parallel processing (N workers, default: 1)

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
      --direct-artifacts) DIRECT_ARTIFACTS=true; shift ;;
      -e|--exclude-groups) EXCLUDE_GROUPS="$2"; shift 2 ;;
      -c|--config) CONFIG_FILE="$2"; shift 2 ;;
      -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
      --no-pnc-integration) ENABLE_PNC_INTEGRATION=false; shift ;;
      --no-env-autoselect) ENABLE_ENV_AUTOSELECT=false; shift ;;
      --no-build-script-reuse) ENABLE_BUILD_SCRIPT_REUSE=false; shift ;;
      --no-topological-sort) ENABLE_TOPOLOGICAL_SORT=false; shift ;;
      --check-productization) ENABLE_PRODUCTIZATION_CHECK=true; shift ;;
      --enable-ai-assistant) ENABLE_AI_ASSISTANT=true; shift ;;
      --no-ai-assistant) ENABLE_AI_ASSISTANT=false; shift ;;
      --expand-bom) ENABLE_BOM_EXPANSION=true; shift ;;
      --use-cache) ENABLE_CACHE=true; shift ;;
      --clear-cache) 
        if [[ -f "lib/cache_manager.sh" ]]; then
          source lib/cache_manager.sh
          clear_all_caches
        fi
        exit 0
        ;;
      --cache-dir) CACHE_DIR="$2"; export CACHE_DIR; shift 2 ;;
      --incremental) ENABLE_INCREMENTAL=true; shift ;;
      --force-full) FORCE_FULL_REPROCESS=true; ENABLE_INCREMENTAL=false; shift ;;
      --max-parallel)
        if [[ "$2" =~ ^[0-9]+$ ]] && [[ "$2" -gt 0 ]]; then
          MAX_PARALLEL_WORKERS="$2"
        else
          log_error "Invalid --max-parallel value: must be a positive integer"
          exit 1
        fi
        shift 2
        ;;
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
      --parallel) 
        if [[ "$2" =~ ^[0-9]+$ ]] && [[ "$2" -gt 0 ]]; then
          PARALLEL_WORKERS="$2"
        else
          log_error "Invalid --parallel value: must be a positive integer"
          exit 1
        fi
        shift 2
        ;;
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
  
  # Source cache manager if caching is enabled
  if [[ "$ENABLE_CACHE" == "true" && -f "$lib_dir/cache_manager.sh" ]]; then
    source "$lib_dir/cache_manager.sh"
    init_cache
    log_verbose "Cache manager loaded and initialized"
  fi
  
  # Source parallel processor if parallel workers > 1
  if [[ "$PARALLEL_WORKERS" -gt 1 || "$MAX_PARALLEL_WORKERS" -gt 1 ]] && [[ -f "$lib_dir/parallel_processor.sh" ]]; then
    source "$lib_dir/parallel_processor.sh"
    export MAX_PARALLEL_WORKERS
    log_verbose "Parallel processor loaded (max workers: $MAX_PARALLEL_WORKERS)"
  fi
  
  # Source incremental processor if incremental is enabled
  if [[ "$ENABLE_INCREMENTAL" == "true" && -f "$lib_dir/incremental_processor.sh" ]]; then
    source "$lib_dir/incremental_processor.sh"
    log_verbose "Incremental processor loaded"
  fi
  
  # Source standard SCM resolver first
  if [[ -f "$lib_dir/scm_resolver.sh" ]]; then
    source "$lib_dir/scm_resolver.sh"
    log_verbose "Loaded standard SCM resolver"
  else
    log_error "Required library not found: $lib_dir/scm_resolver.sh"
    exit 1
  fi
  
  # Source AI-enhanced resolver if enabled
  if [[ "$ENABLE_AI_ASSISTANT" == "true" && -f "$lib_dir/ai/ai_scm_resolver.sh" ]]; then
    # Preserve original resolve_scm function
    eval "$(declare -f resolve_scm | sed '1s/resolve_scm/resolve_scm_original/')"
    source "$lib_dir/ai/ai_scm_resolver.sh"
    log_verbose "AI-enhanced SCM resolver enabled"
    # Override resolve_scm with AI-enhanced version
    resolve_scm() {
      ai_enhanced_resolve_scm "$@"
    }
  fi

  if [[ "$ENABLE_AI_ASSISTANT" == "true" && -f "$lib_dir/ai/ai_build_metadata_resolver.sh" ]]; then
    source "$lib_dir/ai/ai_build_metadata_resolver.sh"
    log_verbose "AI-enhanced build metadata resolver enabled"
  fi

  # Pre-export config defaults once so ai_resolve_build_metadata skips per-artifact yq calls
  export _AI_DEFAULT_BUILD_SCRIPT
  export _AI_DEFAULT_BUILD_TYPE
  export _AI_DEFAULT_ENV_ID
  _AI_DEFAULT_BUILD_SCRIPT="$(yq -r '.buildConfigGeneratorConfig.defaultValues.buildScript // "mvn clean deploy -B -DskipTests -Dgpg.skip=true -Dmaven.javadoc.skip=true -Denforcer.skip=true -DskipNexusStagingDeployMojo=true"' "$CONFIG_FILE" 2>/dev/null || echo "mvn clean deploy -B -DskipTests -Dgpg.skip=true -Dmaven.javadoc.skip=true -Denforcer.skip=true -DskipNexusStagingDeployMojo=true")"
  _AI_DEFAULT_BUILD_TYPE="$(yq -r '.buildConfigGeneratorConfig.defaultValues.buildType // "MVN"' "$CONFIG_FILE" 2>/dev/null || echo "MVN")"
  _AI_DEFAULT_ENV_ID="$(yq -r '.buildConfigGeneratorConfig.defaultValues.environmentId // "660"' "$CONFIG_FILE" 2>/dev/null || echo "660")"
  log_verbose "Pre-loaded config defaults: buildType=$_AI_DEFAULT_BUILD_TYPE envId=$_AI_DEFAULT_ENV_ID"
  
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

  # Allow BOM-only input when BOM expansion is enabled
  if [[ -z "$INPUT_ARTIFACT" && -z "$ROOT_ARTIFACTS_FILE" ]]; then
    if [[ "$ENABLE_BOM_EXPANSION" == "true" && -n "$INPUT_BOM" ]]; then
      # BOM expansion mode - valid
      :
    else
      log_error "Provide --artifact or --root-artifacts (or use --expand-bom with --bom)"
      exit 1
    fi
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
  # Clean output directory to avoid mixing old and new results
  if [[ -d "$OUTPUT_DIR/build-configs" ]]; then
    rm -f "$OUTPUT_DIR/build-configs"/*.json 2>/dev/null || true
  fi
  mkdir -p "$OUTPUT_DIR/build-configs"
  
  # Clean/create output files
  : > "$OUTPUT_DIR/root-artifacts.txt"
  : > "$OUTPUT_DIR/all-dependencies.txt"
  : > "$OUTPUT_DIR/third-party-dependencies.txt"
  : > "$OUTPUT_DIR/dependency-edges.txt"
  : > "$OUTPUT_DIR/unresolved-artifacts.txt"
  : > "$OUTPUT_DIR/ai-metadata-review.txt"
  printf '[]\n' > "$OUTPUT_DIR/ai-build-metadata-overrides.json"
  
  # Remove old combined outputs
  rm -f "$OUTPUT_DIR/combined-build-configs.yaml" 2>/dev/null || true
  rm -f "$OUTPUT_DIR/pig-config.yaml" 2>/dev/null || true
  rm -f "$OUTPUT_DIR/build-report.txt" 2>/dev/null || true
  
  UNRESOLVED_FILE="$OUTPUT_DIR/unresolved-artifacts.txt"
  AI_REVIEW_FILE="$OUTPUT_DIR/ai-metadata-review.txt"
  AI_OVERRIDES_FILE="$OUTPUT_DIR/ai-build-metadata-overrides.json"
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
  log_info "  Direct Artifacts: $DIRECT_ARTIFACTS"
  log_info "  Output Format: $OUTPUT_FORMAT"
  log_info "  Caching: $ENABLE_CACHE"
  log_info "  Incremental: $ENABLE_INCREMENTAL"
  log_info "  Parallel Workers: $PARALLEL_WORKERS"
  log_info "  Max Parallel (checks): $MAX_PARALLEL_WORKERS"
  
  # Check for PNC hanging issues and warn user
  check_pnc_hanging_warning
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry run complete. No files were created."
    exit 0
  fi
  
  prepare_workspace
  load_effective_exclude_groups
  
  # Initialize incremental processing if enabled
  local config_hash=""
  if [[ "$ENABLE_INCREMENTAL" == "true" ]]; then
    if declare -f init_state_dir &>/dev/null; then
      init_state_dir "$OUTPUT_DIR"
      config_hash=$(generate_config_hash "$CONFIG_FILE" "$INPUT_BOM" "$EXCLUDE_GROUPS")
      log_info "Incremental processing enabled (config hash: ${config_hash:0:8}...)"
      
      # Check if force full reprocess
      if [[ "$FORCE_FULL_REPROCESS" == "true" ]]; then
        log_info "Force full reprocessing requested, clearing state..."
        clear_state "$OUTPUT_DIR"
      fi
    else
      log_warn "Incremental processor not loaded, disabling incremental mode"
      ENABLE_INCREMENTAL=false
    fi
  fi
  
  # Load root artifacts
  log_info "Loading root artifacts..."
  if [[ -n "$INPUT_ARTIFACT" ]]; then
    echo "$INPUT_ARTIFACT" >> "$OUTPUT_DIR/root-artifacts.txt"
  fi
  if [[ -n "$ROOT_ARTIFACTS_FILE" ]]; then
    load_root_artifacts "$ROOT_ARTIFACTS_FILE" "$OUTPUT_DIR/root-artifacts.txt"
  fi
  
  # Expand BOM if requested
  if [[ "$ENABLE_BOM_EXPANSION" == "true" && -n "$INPUT_BOM" ]]; then
    log_info "Expanding BOM to include all managed dependencies..."
    local bom_deps_file="$OUTPUT_DIR/bom-expanded-deps.txt"
    if expand_bom_dependencies "$INPUT_BOM" "$bom_deps_file"; then
      local bom_count
      bom_count=$(wc -l < "$bom_deps_file" | tr -d ' ')
      log_info "Extracted $bom_count artifacts from BOM"
      log_info "Skipping transitive dependency resolution (BOM artifacts are already managed versions)"
      
      # For BOM expansion: skip Maven dependency resolution entirely
      # Treat BOM artifacts as the final list to build
      : > "$OUTPUT_DIR/root-artifacts.txt"
      cp "$bom_deps_file" "$OUTPUT_DIR/all-dependencies.txt"
      
      # Apply exclude groups filter to BOM artifacts
      log_info "Filtering BOM artifacts by exclude groups: $EXCLUDE_GROUPS"
      if [[ -n "$EXCLUDE_GROUPS" ]]; then
        python3 - "$bom_deps_file" "$OUTPUT_DIR/third-party-dependencies.txt" "$EXCLUDE_GROUPS" <<'PY'
import sys
from pathlib import Path

input_file = Path(sys.argv[1])
output_file = Path(sys.argv[2])
exclude_groups = {x.strip() for x in sys.argv[3].split(",") if x.strip()}

filtered = []
for line in input_file.read_text().splitlines():
    line = line.strip()
    if not line:
        continue
    group = line.split(':', 1)[0]
    if group not in exclude_groups:
        filtered.append(line)

output_file.write_text('\n'.join(filtered) + '\n' if filtered else '')
print(f"[INFO] Filtered {len(filtered)} third-party artifacts from {input_file.stat().st_size // 50} total BOM artifacts", file=sys.stderr)
PY
      else
        cp "$bom_deps_file" "$OUTPUT_DIR/third-party-dependencies.txt"
      fi
      
      : > "$OUTPUT_DIR/dependency-edges.txt"
      
      # Skip to config generation
      if [[ "$ENABLE_TOPOLOGICAL_SORT" == "true" ]]; then
        log_info "Performing topological sort..."
        sort "$OUTPUT_DIR/third-party-dependencies.txt" -o "$OUTPUT_DIR/third-party-dependencies.txt"
      fi
      
      log_info "Generating individual build configs..."
      generate_individual_configs
      
      if [[ "$OUTPUT_FORMAT" == "combined" || "$OUTPUT_FORMAT" == "both" ]]; then
        log_info "Generating combined YAML..."
        generate_combined_yaml_wrapper
      fi
      
      if [[ "$OUTPUT_FORMAT" == "combined" || "$OUTPUT_FORMAT" == "both" ]]; then
        log_info "Generating PIG config..."
        generate_pig_config "$CONFIG_FILE" "$OUTPUT_DIR/pig-config.yaml"
      fi
      
      log_info "Generating build report..."
      generate_build_report "$OUTPUT_DIR" "$CONFIG_FILE"
      
      log_success "Done! Output written to $OUTPUT_DIR"
      exit 0
    else
      log_warn "Failed to expand BOM, continuing with existing root artifacts"
    fi
  fi
  
  if [[ "$DIRECT_ARTIFACTS" == "true" ]]; then
    log_info "Using supplied artifacts directly; skipping transitive dependency resolution..."
    cp "$OUTPUT_DIR/root-artifacts.txt" "$OUTPUT_DIR/all-dependencies.txt"
    cp "$OUTPUT_DIR/root-artifacts.txt" "$OUTPUT_DIR/third-party-dependencies.txt"
    : > "$OUTPUT_DIR/dependency-edges.txt"
  else
    # Analyze dependencies
    log_info "Analyzing dependencies..."
    local input_type input_value
    
    # For BOM expansion, use BOM artifacts file
    if [[ "$ENABLE_BOM_EXPANSION" == "true" && -f "$OUTPUT_DIR/bom-artifacts.txt" ]]; then
      input_type="file"
      input_value="$OUTPUT_DIR/bom-artifacts.txt"
    elif [[ -n "$INPUT_ARTIFACT" ]] && [[ -z "$ROOT_ARTIFACTS_FILE" ]]; then
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
    
    # For BOM expansion, use original root artifacts (before BOM expansion) for filtering
    local filter_root_file="$OUTPUT_DIR/root-artifacts.txt"
    if [[ "$ENABLE_BOM_EXPANSION" == "true" && -f "$OUTPUT_DIR/root-artifacts-original.txt" ]]; then
      filter_root_file="$OUTPUT_DIR/root-artifacts-original.txt"
      log_info "Using original root artifacts for filtering (BOM expansion mode)"
    fi
    
    filter_dependencies \
      "$OUTPUT_DIR/all-dependencies.txt" \
      "$filter_root_file" \
      "$EXCLUDE_GROUPS" \
      "$OUTPUT_DIR/third-party-dependencies.txt" \
      "$OUTPUT_DIR/dependency-edges.txt"
  fi
  
  # Apply incremental filtering if enabled
  if [[ "$ENABLE_INCREMENTAL" == "true" ]] && declare -f get_artifacts_to_process &>/dev/null; then
    log_info "Applying incremental filtering..."
    local to_process_file
    to_process_file=$(get_artifacts_to_process "$OUTPUT_DIR" "$OUTPUT_DIR/third-party-dependencies.txt" "$config_hash")
    
    # Replace third-party dependencies with filtered list
    cp "$to_process_file" "$OUTPUT_DIR/third-party-dependencies.txt"
  fi
  
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
      cp "$OUTPUT_DIR/pending-productized.txt" "$OUTPUT_DIR/third-party-dependencies.txt"
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
  
  # Save incremental processing state
  if [[ "$ENABLE_INCREMENTAL" == "true" ]] && declare -f save_last_run_info &>/dev/null; then
    local artifact_count
    artifact_count=$(wc -l < "$OUTPUT_DIR/third-party-dependencies.txt" 2>/dev/null | tr -d ' ' || echo "0")
    save_last_run_info "$OUTPUT_DIR" "$config_hash" "$artifact_count"
    
    # Save dependency graph for future incremental updates
    if declare -f save_dependency_graph &>/dev/null && [[ -f "$OUTPUT_DIR/dependency-edges.txt" ]]; then
      save_dependency_graph "$OUTPUT_DIR" "$OUTPUT_DIR/dependency-edges.txt"
    fi
  fi
  
  # Display cache statistics if caching is enabled
  if [[ "$ENABLE_CACHE" == "true" ]] && declare -f get_cache_stats &>/dev/null; then
    echo ""
    log_info "Cache Statistics:"
    get_cache_stats | sed 's/^/  /'
  fi
  
  log_success "Done! Output written to $OUTPUT_DIR"
  log_info "Summary:"
  cat "$OUTPUT_DIR/build-report.txt"
}

# Process a single artifact (for parallel execution)
process_single_artifact() {
  local gav="$1"
  local total_count="$2"
  local show_progress="${3:-false}"
  
  local group_id artifact_id version
  group_id="$(echo "$gav" | cut -d: -f1)"
  artifact_id="$(echo "$gav" | cut -d: -f2)"
  version="$(echo "$gav" | cut -d: -f3)"
    
  # Resolve SCM with source tracking. Reuse prior PNC build metadata first.
  local scm_data scm_source="" previous_pnc_config=""
  local pnc_build_script="" pnc_environment_id=""
  previous_pnc_config="$(query_pnc_build_config "$group_id" "$artifact_id" "$version" 2>/dev/null || true)"
  if [[ -n "$previous_pnc_config" && "$previous_pnc_config" != "null" ]]; then
    scm_data="SCM_URL=$(echo "$previous_pnc_config" | jq -r '.scmRepository.internalUrl // empty')
SCM_REVISION=$(echo "$previous_pnc_config" | jq -r '.scmRevision // empty')"
    scm_source="Previous PNC build"
    # Also capture build script and environment from the PNC config
    pnc_build_script="$(echo "$previous_pnc_config" | jq -r '.buildScript // empty' 2>/dev/null | sed '/^[[:space:]]*#/d' | tr '\n' ' ' | sed 's/[[:space:]]*$//' || true)"
    pnc_environment_id="$(echo "$previous_pnc_config" | jq -r '.environment.id // empty' 2>/dev/null || true)"
  elif scm_data="$(resolve_scm "$group_id" "$artifact_id" "$version" 2>&1)"; then
    scm_source=$(echo "$scm_data" | grep -o "Source: [^$]*" | head -1 || echo "")
  else
    if [[ "$show_progress" == "true" ]]; then
      printf "\r%-80s\r" "" >&2
    fi
    echo "[WARN] Failed to resolve SCM for $gav" >&2
    # Thread-safe append to unresolved file (macOS compatible)
    {
      # Simple lock using mkdir (atomic operation)
      while ! mkdir "$UNRESOLVED_FILE.lock" 2>/dev/null; do
        sleep 0.01
      done
      echo "$gav" >> "$UNRESOLVED_FILE"
      rmdir "$UNRESOLVED_FILE.lock"
    }
    return 1
  fi
  
  local scm_url scm_revision
  scm_url="$(echo "$scm_data" | awk -F= '/^SCM_URL=/{print substr($0,9)}')"
  scm_revision="$(echo "$scm_data" | awk -F= '/^SCM_REVISION=/{print substr($0,14)}')"
  if [[ -z "$scm_source" ]]; then
    scm_source="$(echo "$scm_data" | awk -F= '/^SCM_SOURCE=/{print substr($0,12)}')"
  fi
  
  # Check for productized version
  local productized_status="Unknown"
  if [[ "$ENABLE_PRODUCTIZATION_CHECK" == "true" ]]; then
    if curl -fsSL --max-time 2 -I "https://repo1.maven.org/maven2/$(echo "$group_id" | tr '.' '/')/${artifact_id}/${version}.redhat-00001/${artifact_id}-${version}.redhat-00001.pom" 2>/dev/null | grep -q "200 OK"; then
      productized_status="✓ Available"
    else
      productized_status="✗ Not available"
    fi
  fi
  
  # Show status
  if [[ "$show_progress" == "true" ]]; then
    printf "\r%-80s\r" "" >&2
  fi
  echo "[INFO] ✓ $gav" >&2
  echo "[INFO]   ├─ Source: $scm_source" >&2
  if [[ "$ENABLE_PRODUCTIZATION_CHECK" == "true" ]]; then
    echo "[INFO]   └─ Productized: $productized_status" >&2
  fi
  
  # Resolve build metadata — start from defaults
  local metadata
  metadata="$(resolve_build_metadata "$group_id" "$artifact_id" "$version" "$CONFIG_FILE")"

  local build_script build_type environment_id alignment_parameters
  build_script="$(echo "$metadata" | awk -F= '/^BUILD_SCRIPT=/{print substr($0,14)}')"
  build_type="$(echo "$metadata" | awk -F= '/^BUILD_TYPE=/{print substr($0,12)}')"
  environment_id="$(echo "$metadata" | awk -F= '/^ENVIRONMENT_ID=/{print substr($0,16)}')"
  alignment_parameters="$(echo "$metadata" | awk -F= '/^ALIGNMENT_PARAMETERS=/{print substr($0,22)}')"

  # If the PNC config had a real build script and env, prefer those over defaults.
  # Upgrade deprecated env IDs to their active replacements (bash 3 compatible).
  _upgrade_env_id() {
    case "$1" in
      316)  echo 1663 ;;  # OpenJDK 17 RHEL8 Mvn 3.6.3 -> Mvn 3.9.11
      564)  echo 1593 ;;  # OpenJDK 1.8 RHEL8 Mvn 3.9.5 (deprecated id) -> active id
      445)  echo 435  ;;  # OpenJDK 11 Mvn 3.5.4 -> Mvn 3.6.3
      456)  echo 435  ;;  # OpenJDK 11 Mvn 3.6.3 (deprecated) -> active
      1493) echo 660  ;;  # OpenJDK 1.8 Mvn 3.3.9 -> Mvn 3.6.3
      807)  echo 1663 ;;  # OpenJDK 17 RHEL8 Mvn 3.9.1 Nodejs18 (deprecated) -> Java17 RHEL8 Mvn 3.9.11
      1007) echo 1663 ;;  # OpenJDK 17 RHEL9 Mvn 3.9.1 Nodejs20 (deprecated) -> Java17 RHEL8 Mvn 3.9.11
      *)    echo "$1" ;;
    esac
  }
  if [[ -n "$pnc_build_script" ]]; then
    build_script="$pnc_build_script"
    echo "[INFO]   ├─ Build script: PNC" >&2
  fi
  if [[ -n "$pnc_environment_id" && "$pnc_environment_id" =~ ^[0-9]+$ ]]; then
    local upgraded_env
    upgraded_env="$(_upgrade_env_id "$pnc_environment_id")"
    environment_id="$upgraded_env"
    if [[ "$upgraded_env" != "$pnc_environment_id" ]]; then
      echo "[INFO]   ├─ Environment: PNC id=$pnc_environment_id -> upgraded to $upgraded_env" >&2
    else
      echo "[INFO]   ├─ Environment: PNC (id=$pnc_environment_id)" >&2
    fi
  fi

  local ai_metadata="" ai_build_script="" ai_build_type="" ai_environment_id="" ai_alignment_parameters="" ai_confidence="" ai_reason="" ai_source=""
  local baseline_build_script="$build_script" baseline_build_type="$build_type" baseline_environment_id="$environment_id"
  local use_ai_metadata="false"

  # Always run the AI resolver — it checks training data and harvest for per-artifact overrides.
  if [[ "$ENABLE_AI_ASSISTANT" == "true" ]] && declare -F ai_resolve_build_metadata >/dev/null 2>&1; then
    ai_metadata="$(ai_resolve_build_metadata "$group_id" "$artifact_id" "$version" "$scm_url" "$CONFIG_FILE" 2>/dev/null || true)"
    if [[ -n "$ai_metadata" ]]; then
      ai_build_script="$(echo "$ai_metadata" | awk -F= '/^BUILD_SCRIPT=/{print substr($0,14)}')"
      ai_build_type="$(echo "$ai_metadata" | awk -F= '/^BUILD_TYPE=/{print substr($0,12)}')"
      ai_environment_id="$(echo "$ai_metadata" | awk -F= '/^ENVIRONMENT_ID=/{print substr($0,16)}')"
      ai_alignment_parameters="$(echo "$ai_metadata" | awk -F= '/^ALIGNMENT_PARAMETERS=/{print substr($0,22)}')"
      ai_confidence="$(echo "$ai_metadata" | awk -F= '/^CONFIDENCE=/{print substr($0,12)}')"
      ai_reason="$(echo "$ai_metadata" | awk -F= '/^REASON=/{print substr($0,8)}')"
      ai_source="$(echo "$ai_metadata" | awk -F= '/^SOURCE=/{print substr($0,8)}')"

      if [[ -n "$ai_environment_id" && "$ai_environment_id" =~ ^[0-9]+$ && -n "$ai_build_script" && -n "$ai_build_type" ]]; then
        if [[ "$ai_confidence" == "low" ]]; then
          echo "$gav|$ai_environment_id|$ai_build_type|$ai_build_script|$ai_reason" >> "$AI_REVIEW_FILE"
        else
          # Apply AI values when they differ from the current baseline (including env upgrades)
          build_script="$ai_build_script"
          build_type="$ai_build_type"
          environment_id="$ai_environment_id"
          # AI alignment parameters take precedence over defaults (can be empty to clear)
          [[ -n "$ai_alignment_parameters" ]] && alignment_parameters="$ai_alignment_parameters"
          use_ai_metadata="true"
        fi
      fi
    fi
  fi

  if [[ -z "$environment_id" || ! "$environment_id" =~ ^[0-9]+$ || -z "$build_script" || -z "$build_type" ]]; then
    log_warn "Invalid build metadata for $gav; skipping config generation"
    {
      echo "$gav|invalid-metadata|$environment_id|$build_type|$build_script"
    } >> "$AI_REVIEW_FILE"
    return 0
  fi

  if [[ "$use_ai_metadata" == "true" ]]; then
    python3 - "$AI_OVERRIDES_FILE" "$gav" "$group_id" "$artifact_id" "$version" "$environment_id" "$build_type" "$build_script" "$ai_confidence" "$ai_reason" "$ai_source" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
entry = {
    "gav": sys.argv[2],
    "groupId": sys.argv[3],
    "artifactId": sys.argv[4],
    "version": sys.argv[5],
    "environmentId": int(sys.argv[6]),
    "buildType": sys.argv[7],
    "buildScript": sys.argv[8],
    "confidence": sys.argv[9],
    "reason": sys.argv[10],
    "source": sys.argv[11],
}
data = []
if path.exists():
    try:
        data = json.loads(path.read_text())
    except Exception:
        data = []
data.append(entry)
path.write_text(json.dumps(data, indent=2) + "\n")
PY
  fi
  
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
    "$config_file" \
    "$alignment_parameters"
}

# Generate individual configs (wrapper for library function)
generate_reactor_build_configs() {
  local reactor_builds_json
  reactor_builds_json="$(yq -o=json '.buildConfigGeneratorConfig.reactorBuilds // []' "$CONFIG_FILE")"

  python3 - "$OUTPUT_DIR/build-configs" "$OUTPUT_DIR/reactor-artifact-mappings.txt" "$reactor_builds_json" <<'PY'
import json
import sys
from pathlib import Path

configs_dir = Path(sys.argv[1])
mappings_file = Path(sys.argv[2])
reactors = json.loads(sys.argv[3])
mappings = []
for reactor in reactors:
    config = {
        "name": reactor["name"],
        "project": reactor["project"],
        "description": reactor["description"],
        "scmUrl": reactor["scmUrl"],
        "scmRevision": reactor["scmRevision"],
        "buildType": reactor["buildType"],
        "environmentId": int(reactor["environmentId"]),
        "buildScript": reactor["buildScript"],
    }
    if reactor.get("alignmentParameters"):
        config["alignmentParameters"] = reactor["alignmentParameters"]
    (configs_dir / f'{reactor["name"]}.yaml.json').write_text(json.dumps(config, indent=2) + "\n")
    mappings.extend(f'{artifact}\t{reactor["name"]}' for artifact in reactor.get("artifacts", []))
mappings_file.write_text("\n".join(mappings) + ("\n" if mappings else ""))
PY
}

# Generate individual configs (wrapper for library function)
generate_individual_configs() {
  : > "$UNRESOLVED_FILE"
  generate_reactor_build_configs

  # Build a sorted lookup file of reactor artifacts (bash 3 compatible —
  # avoids declare -A which requires bash 4).
  local _reactor_lookup_file
  _reactor_lookup_file="$(mktemp)"
  if [[ -s "$OUTPUT_DIR/reactor-artifact-mappings.txt" ]]; then
    cut -f1 "$OUTPUT_DIR/reactor-artifact-mappings.txt" | sort > "$_reactor_lookup_file"
  fi

  # Helper: returns true if gav is a reactor artifact (binary search via grep -qxF)
  _is_reactor_artifact() { grep -qxF "$1" "$_reactor_lookup_file" 2>/dev/null; }

  # Count total artifacts for progress tracking
  local total_count
  total_count=$(wc -l < "$OUTPUT_DIR/third-party-dependencies.txt" | tr -d ' ')

  local show_progress="false"
  [[ "$total_count" -gt 10 ]] && show_progress="true"

  if [[ "$PARALLEL_WORKERS" -gt 1 ]]; then
    # Parallel processing
    log_info "Processing $total_count artifacts with $PARALLEL_WORKERS parallel workers..."

    local processed=0

    while IFS= read -r gav || [[ -n "$gav" ]]; do
      [[ -z "$gav" ]] && continue
      _is_reactor_artifact "$gav" && continue

      # Launch background job (continue even if it fails)
      process_single_artifact "$gav" "$total_count" "$show_progress" || true &
      processed=$((processed + 1))

      # Show progress
      if [[ "$show_progress" == "true" ]]; then
        local progress_pct=$((processed * 100 / total_count))
        printf "\r[%3d%%] Processing %d/%d" "$progress_pct" "$processed" "$total_count" >&2
      fi

      # Portable worker throttle: count live child jobs and wait when at limit.
      # 'wait -n' is bash 4+ only; instead we poll the job count.
      while [[ $(jobs -rp | wc -l | tr -d ' ') -ge $PARALLEL_WORKERS ]]; do
        sleep 0.2
      done
    done < "$OUTPUT_DIR/third-party-dependencies.txt"

    # Wait for remaining jobs
    wait

    if [[ "$show_progress" == "true" ]]; then
      printf "\r%-80s\r" "" >&2
    fi
  else
    # Sequential processing
    local current_count=0

    while IFS= read -r gav || [[ -n "$gav" ]]; do
      [[ -z "$gav" ]] && continue
      _is_reactor_artifact "$gav" && continue

      current_count=$((current_count + 1))

      if [[ "$show_progress" == "true" ]]; then
        local progress_pct=$((current_count * 100 / total_count))
        printf "\r[%3d%%] Processing %d/%d: %-60s" "$progress_pct" "$current_count" "$total_count" "$gav" >&2
      fi

      # Continue processing even if individual artifact fails
      process_single_artifact "$gav" "$total_count" "$show_progress" || true
    done < "$OUTPUT_DIR/third-party-dependencies.txt"

    if [[ "$show_progress" == "true" ]]; then
      printf "\r%-80s\r" "" >&2
    fi
  fi

  rm -f "$_reactor_lookup_file"
  
  # Check for unresolved (warn but don't exit - allow combined YAML generation)
  if [[ -s "$UNRESOLVED_FILE" ]]; then
    log_warn "Failed to resolve SCM for $(wc -l < "$UNRESOLVED_FILE" | tr -d ' ') artifacts"
    log_warn "See: $UNRESOLVED_FILE"
    log_warn "Continuing with resolved artifacts..."
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
    "$default_build_script" \
    "$OUTPUT_DIR/reactor-artifact-mappings.txt"
}

# Run main
main "$@"
