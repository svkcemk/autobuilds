#!/bin/bash
###############################################################################
# Transitive Build Config Generator for PNC using Bacon CLI (Version 3)
# Fixed: Properly handles whitespace in BOM parsing
# Enhanced: Uses bob CLI to fetch real artifact metadata
###############################################################################

set -e

# Source bacon utilities for helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/bacon_utils.sh" ]; then
    source "$SCRIPT_DIR/bacon_utils.sh"
fi

CONFIG_FILE="build-config.yaml"
OUTPUT_DIR="./generated-configs"
DRY_RUN=false
VERBOSE=false
BOM_GAV=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_verbose() { if [ "$VERBOSE" = true ]; then echo -e "${BLUE}[VERBOSE]${NC} $1"; fi; }

show_usage() {
    cat << USAGE
Transitive Build Config Generator for PNC using Bacon CLI

Usage: $0 [OPTIONS]

Options:
  -c, --config FILE    Config file (default: build-config.yaml)
  -o, --output DIR     Output directory (default: ./generated-configs)
  -b, --bom GAV       BOM to analyze (from config if not specified)
  -d, --dry-run       Show what would be done without executing
  -v, --verbose       Verbose output
  -h, --help          Show this help message
USAGE
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config) CONFIG_FILE="$2"; shift 2 ;;
            -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
            -b|--bom) BOM_GAV="$2"; shift 2 ;;
            -d|--dry-run) DRY_RUN=true; shift ;;
            -v|--verbose) VERBOSE=true; shift ;;
            -h|--help) show_usage ;;
            *) log_error "Unknown option: $1"; show_usage ;;
        esac
    done
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi
    
    if ! command -v yq &> /dev/null; then
        log_warn "yq not found. Installing via pip..."
        pip install yq || { log_error "Failed to install yq"; exit 1; }
    fi
    
    if ! command -v bob &> /dev/null; then
        log_warn "bob CLI not found. Artifact metadata will use defaults."
        log_warn "Install bob from: https://internal.bob.ibm.com/docs/shell/getting-started/install-and-setup"
    elif [ -z "$BOBSHELL_API_KEY" ]; then
        log_warn "BOBSHELL_API_KEY environment variable not set. Bob queries will fail."
        log_warn "Set BOBSHELL_API_KEY to enable bob CLI artifact metadata fetching."
        log_warn "Example: export BOBSHELL_API_KEY='your-api-key-here'"
    else
        log_info "Bob CLI available with authentication configured"
    fi
    
    log_success "All prerequisites met"
}

extract_bom_from_config() {
    if [ -z "$BOM_GAV" ]; then
        log_info "Extracting BOM from config file..."
        BOM_GAV=$(yq -r '.dependencyResolutionConfig.analyzeBOM' "$CONFIG_FILE")
        
        if [ -z "$BOM_GAV" ] || [ "$BOM_GAV" = "null" ]; then
            log_error "No BOM specified"
            exit 1
        fi
        
        log_info "Using BOM: $BOM_GAV"
    fi
}

get_managed_dependencies_from_bom() {
    local bom_gav="$1"
    local output_file="$2"
    
    log_info "Downloading BOM to extract managed dependencies..."
    
    local group_id=$(echo "$bom_gav" | cut -d: -f1)
    local artifact_id=$(echo "$bom_gav" | cut -d: -f2)
    local version=$(echo "$bom_gav" | cut -d: -f3)
    
    local group_path=$(echo "$group_id" | tr '.' '/')
    local bom_url="https://repo1.maven.org/maven2/${group_path}/${artifact_id}/${version}/${artifact_id}-${version}.pom"
    local temp_bom="/tmp/bom-$$.pom"
    
    log_verbose "Downloading from: $bom_url"
    
    if ! curl -sf "$bom_url" -o "$temp_bom"; then
        log_error "Failed to download BOM from $bom_url"
        return 1
    fi
    
    log_success "Downloaded BOM"
    log_info "Extracting managed dependencies from BOM..."
    
    # FIXED: Properly handle whitespace and extract GAV
    grep -A 10 '<dependency>' "$temp_bom" | \
        awk '
            /<groupId>/ {
                gsub(/<\/?groupId>/, "")
                gsub(/^[[:space:]]+|[[:space:]]+$/, "")
                group=$0
            }
            /<artifactId>/ {
                gsub(/<\/?artifactId>/, "")
                gsub(/^[[:space:]]+|[[:space:]]+$/, "")
                artifact=$0
            }
            /<version>/ {
                gsub(/<\/?version>/, "")
                gsub(/^[[:space:]]+|[[:space:]]+$/, "")
                version=$0
                if (group != "" && artifact != "" && version != "" && version !~ /\$\{/) {
                    print group":"artifact":"version
                    group=""
                    artifact=""
                    version=""
                }
            }
        ' > "$output_file"
    
    rm -f "$temp_bom"
    
    local count=$(wc -l < "$output_file" | tr -d ' ')
    log_success "Extracted $count managed dependencies from BOM"
}

analyze_dependencies() {
    log_info "Analyzing dependencies from BOM: $BOM_GAV"
    
    mkdir -p "$OUTPUT_DIR"
    
    local managed_deps="$OUTPUT_DIR/managed-dependencies.txt"
    get_managed_dependencies_from_bom "$BOM_GAV" "$managed_deps"
    
    if [ ! -s "$managed_deps" ]; then
        log_error "No managed dependencies found in BOM"
        exit 1
    fi
    
    cp "$managed_deps" "$OUTPUT_DIR/all-dependencies.txt"
    
    log_success "Found $(wc -l < "$OUTPUT_DIR/all-dependencies.txt" | tr -d ' ') dependencies"
}

filter_dependencies() {
    log_info "Filtering dependencies based on config patterns..."
    
    local all_deps="$OUTPUT_DIR/all-dependencies.txt"
    local filtered_deps="$OUTPUT_DIR/filtered-dependencies.txt"
    
    local include_patterns=$(yq -r '.dependencyResolutionConfig.includeArtifacts[]?' "$CONFIG_FILE" 2>/dev/null || echo "")
    local exclude_patterns=$(yq -r '.dependencyResolutionConfig.excludeArtifacts[]?' "$CONFIG_FILE" 2>/dev/null || echo "")
    
    cp "$all_deps" "$filtered_deps.tmp"
    
    # Apply exclude patterns
    if [ -n "$exclude_patterns" ]; then
        log_verbose "Applying exclude patterns..."
        while IFS= read -r pattern; do
            if [ -n "$pattern" ]; then
                local grep_pattern=$(echo "$pattern" | sed 's/\*/[^:]*/g')
                if grep -v -E "^$grep_pattern$" "$filtered_deps.tmp" > "$filtered_deps.tmp2" 2>/dev/null; then
                    mv "$filtered_deps.tmp2" "$filtered_deps.tmp"
                elif [ -f "$filtered_deps.tmp2" ]; then
                    mv "$filtered_deps.tmp2" "$filtered_deps.tmp"
                fi
            fi
        done <<< "$exclude_patterns"
    fi
    
    # Apply include patterns
    if [ -n "$include_patterns" ]; then
        log_verbose "Applying include patterns..."
        > "$filtered_deps.tmp2"
        while IFS= read -r pattern; do
            if [ -n "$pattern" ]; then
                local grep_pattern=$(echo "$pattern" | sed 's/\*/[^:]*/g')
                grep -E "^$grep_pattern$" "$filtered_deps.tmp" >> "$filtered_deps.tmp2" 2>/dev/null || true
            fi
        done <<< "$include_patterns"
        mv "$filtered_deps.tmp2" "$filtered_deps.tmp"
    fi
    
    sort -u "$filtered_deps.tmp" > "$filtered_deps"
    rm -f "$filtered_deps.tmp" "$filtered_deps.tmp2"
    
    log_success "Filtered to $(wc -l < "$filtered_deps" | tr -d ' ') dependencies to build"
}

# Verify if SCM repository URL is accessible
verify_scm_url() {
    local url="$1"
    
    # Skip verification for placeholder URLs
    if [[ "$url" == *"placeholder"* ]]; then
        log_verbose "Skipping verification for placeholder URL: $url"
        return 1
    fi
    
    log_verbose "Verifying SCM URL: $url"
    
    # Try to access the URL with curl (follow redirects, timeout 10s)
    if curl -sf --max-time 10 -L "$url" > /dev/null 2>&1; then
        log_verbose "✓ SCM URL is accessible: $url"
        return 0
    else
        log_verbose "✗ SCM URL is NOT accessible: $url"
        return 1
    fi
}

# Fetch artifact metadata using bob CLI with retry on URL verification failure
fetch_artifact_metadata_with_bob() {
    local group_id="$1"
    local artifact_id="$2"
    local version="$3"
    local max_retries=2
    local retry_count=0
    
    log_verbose "fetch_artifact_metadata_with_bob called for: $group_id:$artifact_id:$version"
    
    while [ $retry_count -le $max_retries ]; do
        # Try to get artifact info from bob
        if command -v bob &> /dev/null; then
            if [ $retry_count -gt 0 ]; then
                log_warn "Retry attempt $retry_count for $group_id:$artifact_id:$version - previous URL was invalid"
            fi
            
            log_verbose "Bob CLI found, querying for: $group_id:$artifact_id:$version"
            
            # Create a temporary file for bob's response
            local temp_response="/tmp/bob_response_$$.json"
            
            # Query bob for artifact information using prompt mode
            # Ask bob to return structured JSON with the artifact metadata
            local bob_query="For Maven artifact $group_id:$artifact_id:$version, provide the following information in JSON format:
{
  \"scmRepository\": {
    \"url\": \"<git repository URL>\",
    \"revision\": \"<git tag or commit>\"
  },
  \"buildScript\": \"<build command like 'mvn clean deploy -DskipTests'>\",
  \"buildType\": \"<MVN or GRADLE>\",
  \"environment\": {
    \"name\": \"<build environment like 'OpenJDK 11.0; Mvn 3.6.3'>\"
  }
}
Only return the JSON, no other text. Make sure the git repository URL is valid and accessible."
            
            if [ $retry_count -gt 0 ]; then
                bob_query="$bob_query The previous URL was incorrect. Please provide a different, valid git repository URL."
            fi
            
            # Execute bob query with yolo mode and hide intermediary output
            local bob_output=$(bob --yolo --hide-intermediary-output --chat-mode ask "$bob_query" 2>&1)
            local bob_exit_code=$?
            
            log_verbose "Bob command exit code: $bob_exit_code"
            log_verbose "Bob raw output (first 1000 chars): ${bob_output:0:1000}"
            
            if [ $bob_exit_code -eq 0 ] && [ -n "$bob_output" ]; then
                log_verbose "Bob returned data, attempting to parse JSON..."
                
                # Try to extract JSON from bob's response using multiple methods
                # Method 1: Try to extract complete JSON with jq validation
                local json_output=""
                
                # First, try to find JSON block between first { and matching }
                if command -v python3 &> /dev/null; then
                    json_output=$(echo "$bob_output" | python3 -c "
import sys
import json
import re

text = sys.stdin.read()
# Find all potential JSON objects
matches = re.finditer(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}', text)
for match in matches:
    try:
        obj = json.loads(match.group())
        if 'scmRepository' in obj:
            print(json.dumps(obj))
            break
    except:
        continue
" 2>/dev/null)
                fi
                
                # Fallback: Use grep with non-greedy matching if python fails
                if [ -z "$json_output" ]; then
                    # Try to extract JSON more carefully - look for complete object
                    json_output=$(echo "$bob_output" | sed -n '/{/,/}/p' | grep -v '^[[:space:]]*$' | head -20 | tr -d '\n')
                fi
                
                # Validate JSON with jq
                if [ -n "$json_output" ] && echo "$json_output" | jq empty 2>/dev/null; then
                    log_verbose "Successfully extracted and validated JSON"
                else
                    log_verbose "JSON extraction or validation failed, raw output: $bob_output"
                    json_output=""
                fi
                
                if [ -n "$json_output" ]; then
                    # Extract SCM repository URL
                    local scm_url=$(echo "$json_output" | jq -r '.scmRepository.url // empty' 2>/dev/null)
                    
                    # Extract SCM revision/tag
                    local scm_revision=$(echo "$json_output" | jq -r '.scmRepository.revision // empty' 2>/dev/null)
                    
                    # Extract build script
                    local build_script=$(echo "$json_output" | jq -r '.buildScript // empty' 2>/dev/null)
                    
                    # Extract build type
                    local build_type=$(echo "$json_output" | jq -r '.buildType // empty' 2>/dev/null)
                    
                    # Extract environment
                    local environment=$(echo "$json_output" | jq -r '.environment.name // empty' 2>/dev/null)
                    
                    log_verbose "Extracted from bob: scm_url=$scm_url, scm_revision=$scm_revision, build_type=$build_type"
                    
                    # Verify the SCM URL if it's not empty
                    if [ -n "$scm_url" ]; then
                        if verify_scm_url "$scm_url"; then
                            log_verbose "SCM URL verified successfully"
                            # Return the extracted values
                            echo "SCM_URL=$scm_url"
                            echo "SCM_REVISION=$scm_revision"
                            echo "BUILD_SCRIPT=$build_script"
                            echo "BUILD_TYPE=$build_type"
                            echo "ENVIRONMENT=$environment"
                            rm -f "$temp_response"
                            return 0
                        else
                            log_warn "SCM URL verification failed for: $scm_url"
                            retry_count=$((retry_count + 1))
                            if [ $retry_count -le $max_retries ]; then
                                log_info "Will retry with bob CLI to get a valid URL..."
                                sleep 2
                                continue
                            fi
                        fi
                    fi
                else
                    log_verbose "Could not extract JSON from bob's response"
                fi
            else
                log_verbose "Bob query returned no data or failed"
            fi
            
            rm -f "$temp_response"
        else
            log_verbose "Bob CLI not available, falling back to Maven Central POM"
            break
        fi
        
        retry_count=$((retry_count + 1))
    done
    
    # If bob fails or is not available, try fetching from Maven Central POM
    if declare -f fetch_scm_from_maven &> /dev/null; then
        log_verbose "Falling back to Maven Central POM for: $group_id:$artifact_id:$version"
        fetch_scm_from_maven "$group_id" "$artifact_id" "$version"
        echo "BUILD_SCRIPT="
        echo "BUILD_TYPE="
        echo "ENVIRONMENT="
        return 0
    fi
    
    # Return empty values if all methods fail
    echo "SCM_URL="
    echo "SCM_REVISION="
    echo "BUILD_SCRIPT="
    echo "BUILD_TYPE="
    echo "ENVIRONMENT="
    return 1
}

generate_build_configs() {
    log_info "Generating PNC build configs using bob CLI (one config per unique SCM URL)..."
    
    local filtered_deps="$OUTPUT_DIR/filtered-dependencies.txt"
    local configs_dir="$OUTPUT_DIR/build-configs"
    
    mkdir -p "$configs_dir"
    
    if [ ! -s "$filtered_deps" ]; then
        log_warn "No dependencies to generate configs for"
        return
    fi
    
    local count=0
    local total=$(wc -l < "$filtered_deps" | tr -d ' ')
    
    local default_env=$(yq -r '.buildConfigGeneratorConfig.defaultValues.environmentName' "$CONFIG_FILE" 2>/dev/null || echo "OpenJDK 11.0; Mvn 3.5.4")
    local default_script=$(yq -r '.buildConfigGeneratorConfig.defaultValues.buildScript' "$CONFIG_FILE" 2>/dev/null || echo "mvn -DskipTests clean deploy")
    local default_build_type=$(yq -r '.buildConfigGeneratorConfig.defaultValues.buildType' "$CONFIG_FILE" 2>/dev/null || echo "MVN")
    
    log_info "Will process $total dependencies and group by unique SCM URL"
    
    # Associative array to track unique SCM URLs and their metadata
    declare -A scm_url_map
    declare -A scm_revision_map
    declare -A build_script_map
    declare -A build_type_map
    declare -A environment_map
    declare -A artifact_list_map
    declare -A first_group_map
    declare -A first_artifact_map
    declare -A first_version_map
    
    while IFS= read -r dep; do
        count=$((count + 1))
        
        local group_id=$(echo "$dep" | cut -d: -f1)
        local artifact_id=$(echo "$dep" | cut -d: -f2)
        local version=$(echo "$dep" | cut -d: -f3)
        
        if [ "$DRY_RUN" = true ]; then
            log_verbose "Would generate config for: $group_id:$artifact_id:$version"
            continue
        fi
        
        if [ $((count % 10)) -eq 0 ] || [ $count -eq $total ]; then
            log_info "[$count/$total] Processing: $group_id:$artifact_id:$version"
        fi
        
        # Fetch metadata using bob or fallback methods
        log_verbose "Calling fetch_artifact_metadata_with_bob for: $group_id:$artifact_id:$version"
        local metadata=$(fetch_artifact_metadata_with_bob "$group_id" "$artifact_id" "$version")
        log_verbose "Metadata returned: $metadata"
        
        # Parse metadata
        local scm_url=$(echo "$metadata" | grep "^SCM_URL=" | cut -d= -f2-)
        local scm_revision=$(echo "$metadata" | grep "^SCM_REVISION=" | cut -d= -f2-)
        local build_script=$(echo "$metadata" | grep "^BUILD_SCRIPT=" | cut -d= -f2-)
        local build_type=$(echo "$metadata" | grep "^BUILD_TYPE=" | cut -d= -f2-)
        local environment=$(echo "$metadata" | grep "^ENVIRONMENT=" | cut -d= -f2-)
        
        # Apply defaults if values are empty
        if [ -z "$scm_url" ]; then
            scm_url="https://github.com/placeholder/${artifact_id}.git"
            log_verbose "Using placeholder SCM URL for $artifact_id"
        fi
        
        if [ -z "$scm_revision" ]; then
            scm_revision="$version"
        fi
        
        if [ -z "$build_script" ]; then
            build_script="$default_script"
        fi
        
        if [ -z "$build_type" ]; then
            build_type="$default_build_type"
        fi
        
        if [ -z "$environment" ]; then
            environment="$default_env"
        fi
        
        # Apply SCM URL transformations if available
        if declare -f transform_scm_url &> /dev/null; then
            scm_url=$(transform_scm_url "$scm_url" "$CONFIG_FILE")
        fi
        
        # Use SCM URL as key to group artifacts
        local url_key=$(echo "$scm_url" | sed 's/[^a-zA-Z0-9]/_/g')
        
        # Store metadata for this SCM URL (first occurrence wins)
        if [ -z "${scm_url_map[$url_key]}" ]; then
            scm_url_map[$url_key]="$scm_url"
            scm_revision_map[$url_key]="$scm_revision"
            build_script_map[$url_key]="$build_script"
            build_type_map[$url_key]="$build_type"
            environment_map[$url_key]="$environment"
            artifact_list_map[$url_key]="$group_id:$artifact_id:$version"
            # Store the first artifact's GAV for naming
            first_group_map[$url_key]="$group_id"
            first_artifact_map[$url_key]="$artifact_id"
            first_version_map[$url_key]="$version"
            log_verbose "New SCM URL registered: $scm_url"
        else
            # Append artifact to the list for this SCM URL
            artifact_list_map[$url_key]="${artifact_list_map[$url_key]}, $group_id:$artifact_id:$version"
            log_verbose "Added artifact to existing SCM URL: $scm_url"
        fi
        
    done < "$filtered_deps"
    
    # Generate one config per unique SCM URL
    local config_count=0
    log_info "Generating build configs for ${#scm_url_map[@]} unique SCM repositories..."
    
    for url_key in "${!scm_url_map[@]}"; do
        config_count=$((config_count + 1))
        
        local scm_url="${scm_url_map[$url_key]}"
        local scm_revision="${scm_revision_map[$url_key]}"
        local build_script="${build_script_map[$url_key]}"
        local build_type="${build_type_map[$url_key]}"
        local environment="${environment_map[$url_key]}"
        local artifacts="${artifact_list_map[$url_key]}"
        
        # Get the first artifact's GAV for the config name field
        local first_group="${first_group_map[$url_key]}"
        local first_artifact="${first_artifact_map[$url_key]}"
        local first_version="${first_version_map[$url_key]}"
        
        # Extract repository name from SCM URL
        local repo_name=$(basename "$scm_url" .git)
        
        # Create config filename in format: groupid-reponame-version
        local config_filename="${first_group}-${repo_name}-${first_version}"
        local config_file="$configs_dir/${config_filename}.yaml"
        
        # Create config name field in format: groupid_artifactid-version
        local config_name="${first_group}_${first_artifact}-${first_version}"
        
        # Handle duplicate filenames (shouldn't happen with unique SCM URLs, but just in case)
        local suffix=1
        while [ -f "$config_file" ]; do
            config_filename="${first_group}-${repo_name}-${first_version}_${suffix}"
            config_file="$configs_dir/${config_filename}.yaml"
            suffix=$((suffix + 1))
        done
        
        cat > "$config_file" << YAML
name: $config_name
description: Auto-generated build config for $repo_name (artifacts: $artifacts)
scmRepository:
  url: $scm_url
  revision: $scm_revision
buildScript: $build_script
environment:
  name: $environment
buildType: $build_type
YAML
        
        log_verbose "Created config file: $(basename "$config_file") with name: $config_name (covers: $artifacts)"
        
    done < "$filtered_deps"
    
    log_success "Build config generation complete: $config_count configs created for ${#scm_url_map[@]} unique repositories"
    log_info "Total dependencies processed: $count"
}

generate_pig_config() {
    log_info "Generating PIG configuration..."
    
    local pig_file="$OUTPUT_DIR/pig-config.yaml"
    yq -r '.buildConfigGeneratorConfig.pigTemplate' "$CONFIG_FILE" > "$pig_file" 2>/dev/null || {
        log_warn "No PIG template in config"
        return
    }
    
    log_success "Generated PIG config: $pig_file"
}

generate_report() {
    log_info "Generating summary report..."
    
    local report_file="$OUTPUT_DIR/build-report.txt"
    local total_deps=$(wc -l < "$OUTPUT_DIR/all-dependencies.txt" 2>/dev/null | tr -d ' ' || echo "0")
    local filtered_deps=$(wc -l < "$OUTPUT_DIR/filtered-dependencies.txt" 2>/dev/null | tr -d ' ' || echo "0")
    local configs=$(find "$OUTPUT_DIR/build-configs" -name "*.yaml" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    
    cat > "$report_file" << REPORT
================================================================================
Transitive Build Config Generation Report
================================================================================
Generated: $(date)
Config File: $CONFIG_FILE
BOM Analyzed: $BOM_GAV

Summary:
--------
Total Dependencies Found: $total_deps
Dependencies After Filtering: $filtered_deps
Build Configs Generated: $configs

Output Directory: $OUTPUT_DIR

Files Generated:
----------------
- managed-dependencies.txt: Dependencies managed by the BOM
- all-dependencies.txt: Complete list of dependencies
- filtered-dependencies.txt: Dependencies after include/exclude filtering
- build-configs/: Individual PNC build configurations ($configs files)
- pig-config.yaml: Product Integration Group configuration
- build-report.txt: This report

Next Steps:
-----------
1. Review the generated build configs in: $OUTPUT_DIR/build-configs/
2. Update SCM URLs in the configs with actual repository locations
3. Use bacon CLI to create builds in PNC
4. Create build group and trigger builds

For more information: https://project-ncl.github.io/bacon/
================================================================================
REPORT
    
    cat "$report_file"
    log_success "Report saved to: $report_file"
}

main() {
    echo "================================================================================"
    echo "  Transitive Build Config Generator for PNC (v3 - Fixed)"
    echo "================================================================================"
    echo ""
    
    parse_args "$@"
    check_prerequisites
    mkdir -p "$OUTPUT_DIR"
    
    extract_bom_from_config
    analyze_dependencies
    filter_dependencies
    
    if [ "$DRY_RUN" = false ]; then
        generate_build_configs
        generate_pig_config
    else
        log_info "Dry run mode - skipping build config generation"
    fi
    
    generate_report
    
    echo ""
    log_success "All done! Check $OUTPUT_DIR for results"
}

main "$@"
