#!/usr/bin/env bash
# env_parser.sh - Parse PNC environment list into structured JSON database
# Usage: ./env_parser.sh [env.txt] [output.json]

set -euo pipefail

# Colors for output
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
Parse PNC environment list into structured JSON database.

Usage:
  ./env_parser.sh [OPTIONS]

Options:
  -i, --input FILE       Input env.txt file (default: env.txt)
  -o, --output FILE      Output JSON file (default: env-database.json)
  -h, --help             Show help

Examples:
  ./env_parser.sh
  ./env_parser.sh -i env.txt -o env-db.json
USAGE
  exit 0
}

# Default values
INPUT_FILE="env.txt"
OUTPUT_FILE="env-database.json"

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -i|--input) INPUT_FILE="$2"; shift 2 ;;
      -o|--output) OUTPUT_FILE="$2"; shift 2 ;;
      -h|--help) show_usage ;;
      *) log_error "Unknown option: $1"; show_usage ;;
    esac
  done
}

# Check prerequisites
check_prerequisites() {
  if ! command -v yq >/dev/null 2>&1; then
    log_error "yq is required but not installed"
    log_info "Install with: brew install yq (macOS) or pip3 install yq"
    exit 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required but not installed"
    log_info "Install with: brew install jq (macOS)"
    exit 1
  fi

  if [[ ! -f "$INPUT_FILE" ]]; then
    log_error "Input file not found: $INPUT_FILE"
    exit 1
  fi
}

# Parse environment list from YAML to JSON
parse_environments() {
  log_info "Parsing environments from $INPUT_FILE..."
  
  # Convert YAML to JSON using yq
  if ! yq -o json "$INPUT_FILE" > "$OUTPUT_FILE.tmp" 2>/dev/null; then
    log_error "Failed to parse YAML. Ensure $INPUT_FILE is valid YAML format."
    rm -f "$OUTPUT_FILE.tmp"
    exit 1
  fi
  
  # Enhance the JSON structure with computed fields
  log_info "Enhancing environment data..."
  
  jq '[
    .[] | 
    . + {
      capabilities: (
        [
          (if .attributes.JDK != null then "java" else empty end),
          (if .attributes.MAVEN != null then "maven" else empty end),
          (if .attributes.GRADLE != null then "gradle" else empty end),
          (if .attributes.NODEJS != null then "nodejs" else empty end),
          (if .attributes.NPM != null then "npm" else empty end),
          (if .attributes.GOLANG != null then "golang" else empty end)
        ]
      ),
      jdk_major: (
        if .attributes.JDK != null then
          (.attributes.JDK | split(".")[0])
        else
          null
        end
      ),
      maven_major: (
        if .attributes.MAVEN != null then
          (.attributes.MAVEN | split(".")[0])
        else
          null
        end
      ),
      is_usable: (
        .deprecated == false and .hidden == false
      )
    }
  ]' "$OUTPUT_FILE.tmp" > "$OUTPUT_FILE"
  
  rm -f "$OUTPUT_FILE.tmp"
  
  # Validate output
  if ! jq empty "$OUTPUT_FILE" 2>/dev/null; then
    log_error "Generated invalid JSON"
    exit 1
  fi
  
  local count
  count="$(jq 'length' "$OUTPUT_FILE")"
  log_success "Parsed $count environments to $OUTPUT_FILE"
}

# Generate statistics
generate_stats() {
  log_info "Generating statistics..."
  
  local total deprecated hidden usable java_envs maven_envs gradle_envs nodejs_envs
  
  total="$(jq 'length' "$OUTPUT_FILE")"
  deprecated="$(jq '[.[] | select(.deprecated == true)] | length' "$OUTPUT_FILE")"
  hidden="$(jq '[.[] | select(.hidden == true)] | length' "$OUTPUT_FILE")"
  usable="$(jq '[.[] | select(.is_usable == true)] | length' "$OUTPUT_FILE")"
  java_envs="$(jq '[.[] | select(.capabilities | contains(["java"]))] | length' "$OUTPUT_FILE")"
  maven_envs="$(jq '[.[] | select(.capabilities | contains(["maven"]))] | length' "$OUTPUT_FILE")"
  gradle_envs="$(jq '[.[] | select(.capabilities | contains(["gradle"]))] | length' "$OUTPUT_FILE")"
  nodejs_envs="$(jq '[.[] | select(.capabilities | contains(["nodejs"]))] | length' "$OUTPUT_FILE")"
  
  cat <<STATS

Environment Database Statistics:
================================
Total Environments:     $total
Deprecated:             $deprecated
Hidden:                 $hidden
Usable (non-deprecated, non-hidden): $usable

By Capability:
  Java (JDK):           $java_envs
  Maven:                $maven_envs
  Gradle:               $gradle_envs
  Node.js:              $nodejs_envs

STATS
}

# Query functions for testing
get_environment_by_id() {
  local env_id="$1"
  jq --arg id "$env_id" '.[] | select(.id == $id)' "$OUTPUT_FILE"
}

list_java_environments() {
  local java_version="${1:-}"
  
  if [[ -z "$java_version" ]]; then
    jq '[.[] | select(.capabilities | contains(["java"])) | {id, name, jdk: .attributes.JDK, maven: .attributes.MAVEN, deprecated}]' "$OUTPUT_FILE"
  else
    jq --arg jv "$java_version" '[.[] | select(.attributes.JDK == $jv) | {id, name, jdk: .attributes.JDK, maven: .attributes.MAVEN, deprecated}]' "$OUTPUT_FILE"
  fi
}

list_usable_environments() {
  jq '[.[] | select(.is_usable == true) | {id, name, capabilities, deprecated, hidden}]' "$OUTPUT_FILE"
}

# Main execution
main() {
  parse_args "$@"
  check_prerequisites
  parse_environments
  generate_stats
  
  log_success "Environment database ready: $OUTPUT_FILE"
  log_info "Use jq to query the database, e.g.:"
  log_info "  jq '.[] | select(.id == \"316\")' $OUTPUT_FILE"
  log_info "  jq '[.[] | select(.is_usable == true)] | length' $OUTPUT_FILE"
}

main "$@"
