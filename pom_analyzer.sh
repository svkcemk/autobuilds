#!/usr/bin/env bash
# pom_analyzer.sh - Extract build requirements from Maven POM files
# Usage: ./pom_analyzer.sh <pom-url-or-file>

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
Extract build requirements from Maven POM files.

Usage:
  ./pom_analyzer.sh <pom-url-or-file>
  ./pom_analyzer.sh <groupId> <artifactId> <version>

Options:
  -h, --help             Show help
  -v, --verbose          Verbose output

Examples:
  ./pom_analyzer.sh pom.xml
  ./pom_analyzer.sh https://repo1.maven.org/.../pom.xml
  ./pom_analyzer.sh org.apache.camel camel-core 3.20.0
  
Output:
  JSON object with extracted requirements:
  {
    "java_version": "11",
    "maven_version": "3.6.3",
    "gradle_version": null,
    "has_nodejs": false,
    "has_gradle": false,
    "build_tool": "maven",
    "source": "pom.xml"
  }
USAGE
  exit 0
}

VERBOSE=false

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) show_usage ;;
      -v|--verbose) VERBOSE=true; shift ;;
      *) break ;;
    esac
  done
}

log_verbose() {
  if [[ "$VERBOSE" == "true" ]]; then
    log_info "$1"
  fi
}

# Construct Maven Central POM URL from GAV
construct_pom_url() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"
  
  local group_path
  group_path="$(echo "$group_id" | tr '.' '/')"
  
  echo "https://repo1.maven.org/maven2/${group_path}/${artifact_id}/${version}/${artifact_id}-${version}.pom"
}

# Fetch POM content from URL or file
fetch_pom_content() {
  local source="$1"
  
  if [[ -f "$source" ]]; then
    log_verbose "Reading POM from file: $source"
    cat "$source"
  elif [[ "$source" =~ ^https?:// ]]; then
    log_verbose "Fetching POM from URL: $source"
    if ! curl -fsSL "$source" 2>/dev/null; then
      log_error "Failed to fetch POM from $source"
      return 1
    fi
  else
    log_error "Invalid POM source: $source"
    return 1
  fi
}

# Extract parent POM coordinates from POM content
extract_parent_pom() {
  local pom_content="$1"
  
  # Check if parent exists
  if ! echo "$pom_content" | grep -q "<parent>"; then
    return 1
  fi
  
  # Extract parent section
  local parent_section
  parent_section="$(echo "$pom_content" | sed -n '/<parent>/,/<\/parent>/p')"
  
  # Extract groupId, artifactId, version
  local parent_group parent_artifact parent_version
  parent_group="$(echo "$parent_section" | grep -oE '<groupId>[^<]+' | sed 's/<groupId>//' | head -1)"
  parent_artifact="$(echo "$parent_section" | grep -oE '<artifactId>[^<]+' | sed 's/<artifactId>//' | head -1)"
  parent_version="$(echo "$parent_section" | grep -oE '<version>[^<]+' | sed 's/<version>//' | head -1)"
  
  if [[ -n "$parent_group" && -n "$parent_artifact" && -n "$parent_version" ]]; then
    echo "$parent_group:$parent_artifact:$parent_version"
    return 0
  fi
  
  return 1
}

# Recursively fetch all parent POMs and merge their properties
fetch_effective_pom() {
  local pom_content="$1"
  local max_depth="${2:-3}"
  local current_depth="${3:-0}"
  
  # Stop if max depth reached
  if [[ $current_depth -ge $max_depth ]]; then
    echo "$pom_content"
    return 0
  fi
  
  # Try to extract parent POM coordinates
  local parent_gav
  if ! parent_gav="$(extract_parent_pom "$pom_content")"; then
    # No parent, return current content
    echo "$pom_content"
    return 0
  fi
  
  log_verbose "Found parent POM: $parent_gav (depth: $current_depth)"
  
  # Construct parent POM URL
  local parent_group parent_artifact parent_version
  parent_group="$(echo "$parent_gav" | cut -d: -f1)"
  parent_artifact="$(echo "$parent_gav" | cut -d: -f2)"
  parent_version="$(echo "$parent_gav" | cut -d: -f3)"
  
  local parent_group_path
  parent_group_path="$(echo "$parent_group" | tr '.' '/')"
  local parent_url="https://repo1.maven.org/maven2/${parent_group_path}/${parent_artifact}/${parent_version}/${parent_artifact}-${parent_version}.pom"
  
  # Fetch parent POM
  local parent_content
  if ! parent_content="$(curl -fsSL "$parent_url" 2>/dev/null)"; then
    log_verbose "Failed to fetch parent POM from $parent_url"
    echo "$pom_content"
    return 0
  fi
  
  log_verbose "Successfully fetched parent POM"
  
  # Recursively fetch grandparent
  parent_content="$(fetch_effective_pom "$parent_content" "$max_depth" $((current_depth + 1)))"
  
  # Merge: append parent properties to child (child properties take precedence in lookups)
  local merged_content="$pom_content"$'\n'"<!-- PARENT PROPERTIES -->"$'\n'"$parent_content"
  
  echo "$merged_content"
}

# Resolve Maven property variables in a value
resolve_property() {
  local value="$1"
  local pom_content="$2"
  local max_iterations="${3:-10}"
  
  # If value doesn't contain ${...}, return as-is
  if [[ ! "$value" =~ \$\{[^}]+\} ]]; then
    echo "$value"
    return 0
  fi
  
  local iteration=0
  local resolved_value="$value"
  
  # Keep resolving until no more variables or max iterations reached
  while [[ "$resolved_value" =~ \$\{[^}]+\} ]] && [[ $iteration -lt $max_iterations ]]; do
    # Extract property name from ${property.name}
    local prop_name
    prop_name="$(echo "$resolved_value" | grep -oE '\$\{[^}]+\}' | head -1 | sed 's/\${\([^}]*\)}/\1/')"
    
    # Look up property value in POM (search from top, so child properties override parent)
    local prop_value
    prop_value="$(echo "$pom_content" | grep -oE "<${prop_name}>[^<]+" | sed "s/<${prop_name}>//" | head -1 || true)"
    
    if [[ -n "$prop_value" ]]; then
      # Replace the variable with its value
      resolved_value="${resolved_value//\$\{${prop_name}\}/${prop_value}}"
    else
      # Property not found, stop resolving
      break
    fi
    
    iteration=$((iteration + 1))
  done
  
  echo "$resolved_value"
}

# Extract Java version from POM
extract_java_version() {
  local pom_content="$1"
  local java_version=""
  
  # Try maven.compiler.source
  java_version="$(echo "$pom_content" | \
    grep -oE '<maven\.compiler\.source>[^<]+' | \
    sed 's/<maven\.compiler\.source>//' | \
    head -1 || true)"
  
  # Fallback to maven.compiler.target
  if [[ -z "$java_version" ]]; then
    java_version="$(echo "$pom_content" | \
      grep -oE '<maven\.compiler\.target>[^<]+' | \
      sed 's/<maven\.compiler\.target>//' | \
      head -1 || true)"
  fi
  
  # Fallback to java.version property
  if [[ -z "$java_version" ]]; then
    java_version="$(echo "$pom_content" | \
      grep -oE '<java\.version>[^<]+' | \
      sed 's/<java\.version>//' | \
      head -1 || true)"
  fi
  
  # Fallback to release property (Java 9+)
  if [[ -z "$java_version" ]]; then
    java_version="$(echo "$pom_content" | \
      grep -oE '<maven\.compiler\.release>[^<]+' | \
      sed 's/<maven\.compiler\.release>//' | \
      head -1 || true)"
  fi
  
  # Resolve property variables if present
  if [[ -n "$java_version" ]]; then
    java_version="$(resolve_property "$java_version" "$pom_content")"
  fi
  
  # Normalize version (remove 1. prefix for old versions)
  if [[ "$java_version" =~ ^1\.([0-9]+) ]]; then
    java_version="${BASH_REMATCH[1]}"
  fi
  
  echo "$java_version"
}

# Extract Maven version from POM
extract_maven_version() {
  local pom_content="$1"
  local maven_version=""
  
  # Try maven.version property
  maven_version="$(echo "$pom_content" | \
    grep -oE '<maven\.version>[^<]+' | \
    sed 's/<maven\.version>//' | \
    head -1 || true)"
  
  # Try maven-enforcer-plugin required version
  if [[ -z "$maven_version" ]]; then
    maven_version="$(echo "$pom_content" | \
      grep -A 10 'maven-enforcer-plugin' | \
      grep -oE '<requireMavenVersion>.*</requireMavenVersion>' | \
      sed 's/<requireMavenVersion>\[//;s/,.*//;s/<\/requireMavenVersion>//' | \
      head -1 || true)"
  fi
  
  echo "$maven_version"
}

# Extract Gradle version from POM or gradle wrapper
extract_gradle_version() {
  local pom_content="$1"
  local gradle_version=""
  
  # Check if gradle is mentioned in POM
  if echo "$pom_content" | grep -qi "gradle"; then
    # Try to extract version from properties
    gradle_version="$(echo "$pom_content" | \
      grep -oE '<gradle\.version>[^<]+' | \
      sed 's/<gradle\.version>//' | \
      head -1 || true)"
  fi
  
  echo "$gradle_version"
}

# Check for Node.js requirements
check_nodejs_requirement() {
  local pom_content="$1"
  
  # Check for frontend-maven-plugin
  if echo "$pom_content" | grep -q "frontend-maven-plugin"; then
    echo "true"
    return 0
  fi
  
  # Check for node/npm in properties
  if echo "$pom_content" | grep -qE "<node\.version>|<npm\.version>"; then
    echo "true"
    return 0
  fi
  
  echo "false"
}

# Check for Gradle requirement
check_gradle_requirement() {
  local pom_content="$1"
  
  if echo "$pom_content" | grep -qi "gradle"; then
    echo "true"
  else
    echo "false"
  fi
}

# Determine primary build tool
determine_build_tool() {
  local pom_content="$1"
  local has_gradle="$2"
  
  if [[ "$has_gradle" == "true" ]]; then
    echo "gradle"
  else
    echo "maven"
  fi
}

# Analyze POM and output JSON
analyze_pom() {
  local source="$1"
  
  log_verbose "Analyzing POM: $source"
  
  local pom_content
  if ! pom_content="$(fetch_pom_content "$source")"; then
    # Return empty/null requirements on failure
    cat <<JSON
{
  "java_version": null,
  "maven_version": null,
  "gradle_version": null,
  "has_nodejs": false,
  "has_gradle": false,
  "build_tool": "maven",
  "source": "$source",
  "error": "Failed to fetch POM"
}
JSON
    return 1
  fi
  
  # Fetch effective POM with parent properties merged (up to 3 levels deep)
  log_verbose "Resolving parent POM hierarchy..."
  pom_content="$(fetch_effective_pom "$pom_content" 3 0)"
  
  local java_version maven_version gradle_version has_nodejs has_gradle build_tool
  
  java_version="$(extract_java_version "$pom_content")"
  maven_version="$(extract_maven_version "$pom_content")"
  gradle_version="$(extract_gradle_version "$pom_content")"
  has_nodejs="$(check_nodejs_requirement "$pom_content")"
  has_gradle="$(check_gradle_requirement "$pom_content")"
  build_tool="$(determine_build_tool "$pom_content" "$has_gradle")"
  
  log_verbose "Detected: Java=$java_version, Maven=$maven_version, Gradle=$gradle_version"
  
  # Output JSON
  cat <<JSON
{
  "java_version": $(if [[ -n "$java_version" ]]; then echo "\"$java_version\""; else echo "null"; fi),
  "maven_version": $(if [[ -n "$maven_version" ]]; then echo "\"$maven_version\""; else echo "null"; fi),
  "gradle_version": $(if [[ -n "$gradle_version" ]]; then echo "\"$gradle_version\""; else echo "null"; fi),
  "has_nodejs": $has_nodejs,
  "has_gradle": $has_gradle,
  "build_tool": "$build_tool",
  "source": "$source"
}
JSON
}

# Main execution
main() {
  local initial_args=("$@")
  parse_args "$@"
  
  # Remove parsed flags from args
  set -- "${initial_args[@]}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help|-v|--verbose) shift ;;
      *) break ;;
    esac
  done
  
  if [[ $# -eq 0 ]]; then
    log_error "No POM source provided"
    show_usage
  fi
  
  local source
  
  if [[ $# -eq 3 ]]; then
    # GAV format: groupId artifactId version
    source="$(construct_pom_url "$1" "$2" "$3")"
  elif [[ $# -eq 1 ]]; then
    # URL or file path
    source="$1"
  else
    log_error "Invalid arguments"
    show_usage
  fi
  
  analyze_pom "$source"
}

main "$@"