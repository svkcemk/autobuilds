#!/usr/bin/env bash
# env_selector.sh - Select optimal build environment based on requirements
# Usage: ./env_selector.sh <env-database.json> <requirements.json>

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

show_usage() {
  cat <<'USAGE'
Select optimal build environment based on project requirements.

Usage:
  ./env_selector.sh <env-database.json> <requirements.json>
  ./env_selector.sh -d <env-database.json> -j <java-version> [-m <maven-version>]

Options:
  -d, --database FILE    Environment database JSON file
  -j, --java VERSION     Java version requirement
  -m, --maven VERSION    Maven version requirement (optional)
  -g, --gradle VERSION   Gradle version requirement (optional)
  -n, --nodejs           Requires Node.js support
  -f, --fallback ID      Fallback environment ID if no match found
  -v, --verbose          Verbose output
  -h, --help             Show help

Examples:
  ./env_selector.sh env-database.json requirements.json
  ./env_selector.sh -d env-database.json -j 11 -m 3.6.3
  ./env_selector.sh -d env-database.json -j 17 --verbose

Output:
  JSON object with selected environment:
  {
    "id": "456",
    "name": "OpenJDK 11.0; Mvn 3.6.3",
    "score": 180,
    "reason": "Exact JDK and Maven match",
    "deprecated": false,
    "replacement_id": null
  }

Scoring Algorithm:
  +100  Exact JDK version match
  +50   JDK major version match
  +30   Exact Maven version match
  +15   Maven major version match
  +20   Gradle version match (if required)
  +10   Node.js support (if required)
  -50   Deprecated environment
  -100  Hidden environment
USAGE
  exit 0
}

# Default values
ENV_DATABASE=""
REQUIREMENTS_FILE=""
JAVA_VERSION=""
MAVEN_VERSION=""
GRADLE_VERSION=""
NEEDS_NODEJS=false
FALLBACK_ID="316"
VERBOSE=false

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--database) ENV_DATABASE="$2"; shift 2 ;;
      -j|--java) JAVA_VERSION="$2"; shift 2 ;;
      -m|--maven) MAVEN_VERSION="$2"; shift 2 ;;
      -g|--gradle) GRADLE_VERSION="$2"; shift 2 ;;
      -n|--nodejs) NEEDS_NODEJS=true; shift ;;
      -f|--fallback) FALLBACK_ID="$2"; shift 2 ;;
      -v|--verbose) VERBOSE=true; shift ;;
      -h|--help) show_usage ;;
      *)
        if [[ -z "$ENV_DATABASE" ]]; then
          ENV_DATABASE="$1"
          shift
        elif [[ -z "$REQUIREMENTS_FILE" ]]; then
          REQUIREMENTS_FILE="$1"
          shift
        else
          log_error "Unknown option: $1"
          show_usage
        fi
        ;;
    esac
  done
}

log_verbose() {
  if [[ "$VERBOSE" == "true" ]]; then
    log_info "$1"
  fi
}

# Check prerequisites
check_prerequisites() {
  if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required but not installed"
    exit 1
  fi

  if [[ ! -f "$ENV_DATABASE" ]]; then
    log_error "Environment database not found: $ENV_DATABASE"
    exit 1
  fi

  if ! jq empty "$ENV_DATABASE" 2>/dev/null; then
    log_error "Invalid JSON in environment database: $ENV_DATABASE"
    exit 1
  fi
}

# Load requirements from JSON file
load_requirements() {
  if [[ -n "$REQUIREMENTS_FILE" ]] && [[ -f "$REQUIREMENTS_FILE" ]]; then
    log_verbose "Loading requirements from $REQUIREMENTS_FILE"
    
    JAVA_VERSION="$(jq -r '.java_version // ""' "$REQUIREMENTS_FILE")"
    MAVEN_VERSION="$(jq -r '.maven_version // ""' "$REQUIREMENTS_FILE")"
    GRADLE_VERSION="$(jq -r '.gradle_version // ""' "$REQUIREMENTS_FILE")"
    
    local has_nodejs
    has_nodejs="$(jq -r '.has_nodejs // false' "$REQUIREMENTS_FILE")"
    if [[ "$has_nodejs" == "true" ]]; then
      NEEDS_NODEJS=true
    fi
  fi
}

# Normalize Java version (remove 1. prefix)
normalize_java_version() {
  local version="$1"
  if [[ "$version" =~ ^1\.([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "$version"
  fi
}

# Get Java major version
get_java_major() {
  local version="$1"
  version="$(normalize_java_version "$version")"
  echo "$version" | cut -d. -f1
}

# Get Maven major version
get_maven_major() {
  local version="$1"
  echo "$version" | cut -d. -f1
}

# Select best environment using scoring algorithm
select_environment() {
  log_verbose "Selecting environment for: Java=$JAVA_VERSION, Maven=$MAVEN_VERSION, Gradle=$GRADLE_VERSION, NodeJS=$NEEDS_NODEJS"
  
  local java_normalized java_major maven_major
  java_normalized="$(normalize_java_version "$JAVA_VERSION")"
  java_major="$(get_java_major "$java_normalized")"
  maven_major="$(get_maven_major "$MAVEN_VERSION")"
  
  log_verbose "Normalized: Java=$java_normalized (major=$java_major), Maven major=$maven_major"
  
  # Score and rank environments
  local result
  result="$(jq --arg jv "$java_normalized" \
               --arg jm "$java_major" \
               --arg mv "$MAVEN_VERSION" \
               --arg mm "$maven_major" \
               --arg gv "$GRADLE_VERSION" \
               --argjson needs_node "$NEEDS_NODEJS" \
    '
    map(
      . as $env |
      (
        # Base score
        0 +
        
        # JDK scoring
        (if ($env.attributes.JDK // "") == $jv then 100
         elif ($env.attributes.JDK // "") != "" and (($env.attributes.JDK // "") | split(".")[0]) == $jm then 50
         else 0 end) +
        
        # Maven scoring
        (if ($env.attributes.MAVEN // "") == $mv then 30
         elif $mv != "" and ($env.attributes.MAVEN // "") != "" and (($env.attributes.MAVEN // "") | split(".")[0]) == $mm then 15
         elif ($env.attributes.MAVEN // "") != "" then 10
         else 0 end) +
        
        # Gradle scoring
        (if $gv != "" and ($env.attributes.GRADLE // "") == $gv then 20
         elif $gv != "" and ($env.attributes.GRADLE // "") != "" then 10
         else 0 end) +
        
        # Node.js scoring
        (if $needs_node and ($env.attributes.NODEJS // "") != "" then 10
         else 0 end) +
        
        # Penalties
        (if $env.deprecated then -50 else 0 end) +
        (if $env.hidden then -100 else 0 end)
      ) as $score |
      
      # Determine reason
      (
        if ($env.attributes.JDK // "") == $jv and ($env.attributes.MAVEN // "") == $mv then
          "Exact JDK and Maven match"
        elif ($env.attributes.JDK // "") == $jv then
          "Exact JDK match"
        elif ($env.attributes.JDK // "") != "" and (($env.attributes.JDK // "") | split(".")[0]) == $jm then
          "JDK major version match"
        elif ($env.attributes.MAVEN // "") == $mv then
          "Maven version match"
        else
          "Best available match"
        end
      ) as $reason |
      
      $env + {
        score: $score,
        reason: $reason
      }
    ) |
    sort_by(-.score) |
    .[0]
  ' "$ENV_DATABASE")"
  
  echo "$result"
}

# Get environment by ID (fallback)
get_environment_by_id() {
  local env_id="$1"
  
  jq --arg id "$env_id" '
    .[] | select(.id == $id) | . + {
      score: 0,
      reason: "Fallback environment"
    }
  ' "$ENV_DATABASE"
}

# Handle deprecated environment
check_deprecated() {
  local env="$1"
  
  local is_deprecated
  is_deprecated="$(echo "$env" | jq -r '.deprecated')"
  
  if [[ "$is_deprecated" == "true" ]]; then
    local env_id env_name replacement_id
    env_id="$(echo "$env" | jq -r '.id')"
    env_name="$(echo "$env" | jq -r '.name')"
    replacement_id="$(echo "$env" | jq -r '.attributes.DEPRECATION_REPLACEMENT // ""')"
    
    log_warn "Selected environment is deprecated: ID $env_id ($env_name)"
    
    if [[ -n "$replacement_id" && "$replacement_id" != "null" ]]; then
      log_warn "Recommended replacement: Environment ID $replacement_id"
      
      # Add replacement info to output
      echo "$env" | jq --arg rid "$replacement_id" '. + {replacement_id: $rid}'
      return 0
    fi
  fi
  
  echo "$env"
}

# Format output
format_output() {
  local env="$1"
  
  local env_id env_name score reason deprecated replacement_id
  env_id="$(echo "$env" | jq -r '.id')"
  env_name="$(echo "$env" | jq -r '.name')"
  score="$(echo "$env" | jq -r '.score')"
  reason="$(echo "$env" | jq -r '.reason')"
  deprecated="$(echo "$env" | jq -r '.deprecated')"
  replacement_id="$(echo "$env" | jq -r '.replacement_id // null')"
  
  log_verbose "Selected: ID $env_id ($env_name) with score $score"
  log_verbose "Reason: $reason"
  
  # Output JSON
  jq -n \
    --arg id "$env_id" \
    --arg name "$env_name" \
    --argjson score "$score" \
    --arg reason "$reason" \
    --argjson deprecated "$deprecated" \
    --arg replacement "$replacement_id" \
    '{
      id: $id,
      name: $name,
      score: $score,
      reason: $reason,
      deprecated: $deprecated,
      replacement_id: (if $replacement == "null" then null else $replacement end)
    }'
}

# Main execution
main() {
  parse_args "$@"
  
  if [[ -z "$ENV_DATABASE" ]]; then
    log_error "Environment database not specified"
    show_usage
  fi
  
  check_prerequisites
  load_requirements
  
  if [[ -z "$JAVA_VERSION" ]]; then
    log_warn "No Java version specified, using fallback environment ID $FALLBACK_ID"
    local fallback_env
    fallback_env="$(get_environment_by_id "$FALLBACK_ID")"
    
    if [[ -z "$fallback_env" || "$fallback_env" == "null" ]]; then
      log_error "Fallback environment not found: ID $FALLBACK_ID"
      exit 1
    fi
    
    format_output "$fallback_env"
    return 0
  fi
  
  local selected_env
  selected_env="$(select_environment)"
  
  if [[ -z "$selected_env" || "$selected_env" == "null" ]]; then
    log_warn "No suitable environment found, using fallback ID $FALLBACK_ID"
    selected_env="$(get_environment_by_id "$FALLBACK_ID")"
  fi
  
  # Check for deprecation and add replacement info
  selected_env="$(check_deprecated "$selected_env")"
  
  # Format and output result
  format_output "$selected_env"
}

main "$@"
