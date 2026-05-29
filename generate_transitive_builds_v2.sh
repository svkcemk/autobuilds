#!/bin/bash
###############################################################################
# Transitive Build Config Generator for PNC using Bacon CLI (Version 2)
#
# This version properly handles BOM analysis by extracting managed dependencies
###############################################################################

set -e

# Default values
CONFIG_FILE="build-config.yaml"
OUTPUT_DIR="./generated-configs"
DRY_RUN=false
VERBOSE=false
BOM_GAV=""

# Colors
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
    
    if ! command -v mvn &> /dev/null; then
        log_error "Maven not found. Please install Maven."
        exit 1
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

# NEW: Download and parse BOM to get managed dependencies
get_managed_dependencies_from_bom() {
    local bom_gav="$1"
    local output_file="$2"
    
    log_info "Downloading BOM to extract managed dependencies..."
    
    local group_id=$(echo "$bom_gav" | cut -d: -f1)
    local artifact_id=$(echo "$bom_gav" | cut -d: -f2)
    local version=$(echo "$bom_gav" | cut -d: -f3)
    
    # Convert group ID to path
    local group_path=$(echo "$group_id" | tr '.' '/')
    
    # Download BOM POM
    local bom_url="https://repo1.maven.org/maven2/${group_path}/${artifact_id}/${version}/${artifact_id}-${version}.pom"
    local temp_bom="/tmp/bom-$$.pom"
    
    log_verbose "Downloading from: $bom_url"
    
    if ! curl -sf "$bom_url" -o "$temp_bom"; then
        log_error "Failed to download BOM from $bom_url"
        return 1
    fi
    
    log_success "Downloaded BOM"
    
    # Extract managed dependencies (groupId:artifactId:version format)
    log_info "Extracting managed dependencies from BOM..."
    
    # Parse XML to extract dependencies
    # This is a simple parser - for production use a proper XML parser
    grep -A 10 '<dependency>' "$temp_bom" | \
        awk '
            /<groupId>/ {gsub(/<\/?groupId>/, ""); group=$0}
            /<artifactId>/ {gsub(/<\/?artifactId>/, ""); artifact=$0}
            /<version>/ {gsub(/<\/?version>/, ""); version=$0; print group":"artifact":"version}
        ' | grep -v '${' > "$output_file"
    
    rm -f "$temp_bom"
    
    local count=$(wc -l < "$output_file")
    log_success "Extracted $count managed dependencies from BOM"
}

analyze_dependencies() {
    log_info "Analyzing dependencies from BOM: $BOM_GAV"
    
    mkdir -p "$OUTPUT_DIR"
    
    # Get managed dependencies from BOM
    local managed_deps="$OUTPUT_DIR/managed-dependencies.txt"
    get_managed_dependencies_from_bom "$BOM_GAV" "$managed_deps"
    
    if [ ! -s "$managed_deps" ]; then
        log_error "No managed dependencies found in BOM"
        exit 1
    fi
    
    # For now, use managed dependencies as our dependency list
    # In a full implementation, we'd resolve transitive dependencies for each
    cp "$managed_deps" "$OUTPUT_DIR/all-dependencies.txt"
    
    log_success "Found $(wc -l < "$OUTPUT_DIR/all-dependencies.txt") dependencies"
}

filter_dependencies() {
    log_info "Filtering dependencies based on config patterns..."
    
    local all_deps="$OUTPUT_DIR/all-dependencies.txt"
    local filtered_deps="$OUTPUT_DIR/filtered-dependencies.txt"
    
    # Extract patterns from config
    local include_patterns=$(yq -r '.dependencyResolutionConfig.includeArtifacts[]?' "$CONFIG_FILE" 2>/dev/null || echo "")
    local exclude_patterns=$(yq -r '.dependencyResolutionConfig.excludeArtifacts[]?' "$CONFIG_FILE" 2>/dev/null || echo "")
    
    # Start with all dependencies
    cp "$all_deps" "$filtered_deps.tmp"
    
    # Apply exclude patterns
    if [ -n "$exclude_patterns" ]; then
        log_verbose "Applying exclude patterns..."
        while IFS= read -r pattern; do
            if [ -n "$pattern" ]; then
                local grep_pattern=$(echo "$pattern" | sed 's/\*/[^:]*/g')
                grep -v -E "^$grep_pattern" "$filtered_deps.tmp" > "$filtered_deps.tmp2" 2>/dev/null || true
                mv "$filtered_deps.tmp2" "$filtered_deps.tmp"
            fi
        done <<< "$exclude_patterns"
    fi
    
    # Apply include patterns if specified
    if [ -n "$include_patterns" ]; then
        log_verbose "Applying include patterns..."
        > "$filtered_deps.tmp2"
        while IFS= read -r pattern; do
            if [ -n "$pattern" ]; then
                local grep_pattern=$(echo "$pattern" | sed 's/\*/[^:]*/g')
                grep -E "^$grep_pattern" "$filtered_deps.tmp" >> "$filtered_deps.tmp2" 2>/dev/null || true
            fi
        done <<< "$include_patterns"
        mv "$filtered_deps.tmp2" "$filtered_deps.tmp"
    fi
    
    # Remove duplicates
    sort -u "$filtered_deps.tmp" > "$filtered_deps"
    rm -f "$filtered_deps.tmp" "$filtered_deps.tmp2"
    
    log_success "Filtered to $(wc -l < "$filtered_deps") dependencies to build"
}

generate_build_configs() {
    log_info "Generating PNC build configs..."
    
    local filtered_deps="$OUTPUT_DIR/filtered-dependencies.txt"
    local configs_dir="$OUTPUT_DIR/build-configs"
    
    mkdir -p "$configs_dir"
    
    if [ ! -s "$filtered_deps" ]; then
        log_warn "No dependencies to generate configs for"
        return
    fi
    
    local count=0
    local total=$(wc -l < "$filtered_deps")
    
    # Get default values from config
    local default_env=$(yq -r '.buildConfigGeneratorConfig.defaultValues.environmentName' "$CONFIG_FILE" 2>/dev/null || echo "OpenJDK 11.0; Mvn 3.5.4")
    local default_script=$(yq -r '.buildConfigGeneratorConfig.defaultValues.buildScript' "$CONFIG_FILE" 2>/dev/null || echo "mvn -DskipTests clean deploy")
    
    while IFS= read -r dep; do
        count=$((count + 1))
        log_info "[$count/$total] Processing: $dep"
        
        local group_id=$(echo "$dep" | cut -d: -f1)
        local artifact_id=$(echo "$dep" | cut -d: -f2)
        local version=$(echo "$dep" | cut -d: -f3)
        
        if [ "$DRY_RUN" = true ]; then
            log_verbose "Would generate config for: $group_id:$artifact_id:$version"
            continue
        fi
        
        local config_name="${group_id}_${artifact_id}_${version}"
        local config_file="$configs_dir/${config_name}.yaml"
        
        # Generate build config YAML
        cat > "$config_file" << YAML
name: $config_name
description: Auto-generated build config for $artifact_id
scmRepository:
  url: https://github.com/placeholder/${artifact_id}.git
  revision: $version
buildScript: $default_script
environment:
  name: $default_env
buildType: MVN
YAML
        
        log_success "Generated: $config_file"
        
    done < "$filtered_deps"
    
    log_success "Build config generation complete"
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
    
    cat > "$report_file" << REPORT
================================================================================
Transitive Build Config Generation Report
================================================================================
Generated: $(date)
Config File: $CONFIG_FILE
BOM Analyzed: $BOM_GAV

Summary:
--------
Total Dependencies Found: $(wc -l < "$OUTPUT_DIR/all-dependencies.txt" 2>/dev/null || echo "0")
Dependencies After Filtering: $(wc -l < "$OUTPUT_DIR/filtered-dependencies.txt" 2>/dev/null || echo "0")
Build Configs Generated: $(find "$OUTPUT_DIR/build-configs" -name "*.yaml" 2>/dev/null | wc -l || echo "0")

Output Directory: $OUTPUT_DIR

Files Generated:
----------------
- managed-dependencies.txt: Dependencies managed by the BOM
- all-dependencies.txt: Complete list of dependencies
- filtered-dependencies.txt: Dependencies after include/exclude filtering
- build-configs/: Individual PNC build configurations
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
    echo "  Transitive Build Config Generator for PNC (v2)"
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
