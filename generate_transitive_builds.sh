#!/bin/bash
###############################################################################
# Transitive Build Config Generator for PNC using Bacon CLI
#
# This script automates the process of generating PNC build configs for
# transitive dependencies using the bacon CLI tool.
#
# Prerequisites:
#   - bacon CLI installed (https://project-ncl.github.io/bacon/)
#   - build-config.yaml in current directory
#   - Java and Maven installed
#
# Usage:
#   ./generate_transitive_builds.sh [OPTIONS]
#
# Options:
#   -c, --config FILE       Config file (default: build-config.yaml)
#   -o, --output DIR        Output directory (default: ./generated-configs)
#   -b, --bom GAV          BOM to analyze (from config if not specified)
#   -d, --dry-run          Show what would be done without executing
#   -v, --verbose          Verbose output
#   -h, --help             Show this help message
###############################################################################

set -e

# Default values
CONFIG_FILE="build-config.yaml"
OUTPUT_DIR="./generated-configs"
DRY_RUN=false
VERBOSE=false
BOM_GAV=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[VERBOSE]${NC} $1"
    fi
}

# Show usage
show_usage() {
    grep "^#" "$0" | grep -v "^#!/" | sed 's/^# //' | sed 's/^#//'
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -b|--bom)
                BOM_GAV="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if bacon is installed
    if ! command -v bacon &> /dev/null; then
        log_error "bacon CLI not found. Please install it from: https://project-ncl.github.io/bacon/"
        exit 1
    fi
    
    # Check if config file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi
    
    # Check if yq is installed (for YAML parsing)
    if ! command -v yq &> /dev/null; then
        log_warn "yq not found. Installing via pip..."
        pip install yq || {
            log_error "Failed to install yq. Please install manually: pip install yq"
            exit 1
        }
    fi
    
    log_success "All prerequisites met"
}

# Extract BOM from config if not provided
extract_bom_from_config() {
    if [ -z "$BOM_GAV" ]; then
        log_info "Extracting BOM from config file..."
        BOM_GAV=$(yq -r '.dependencyResolutionConfig.analyzeBOM' "$CONFIG_FILE")
        
        if [ -z "$BOM_GAV" ] || [ "$BOM_GAV" = "null" ]; then
            log_error "No BOM specified and none found in config file"
            exit 1
        fi
        
        log_info "Using BOM: $BOM_GAV"
    fi
}

# Analyze dependencies using Maven
analyze_dependencies() {
    log_info "Analyzing transitive dependencies from BOM: $BOM_GAV"
    
    local temp_dir=$(mktemp -d)
    local dep_file="$temp_dir/dependencies.txt"
    
    # Create temporary POM for dependency analysis
    cat > "$temp_dir/pom.xml" << POMPOM
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    
    <groupId>temp.analysis</groupId>
    <artifactId>dependency-analyzer</artifactId>
    <version>1.0.0</version>
    
    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>$(echo $BOM_GAV | cut -d: -f1)</groupId>
                <artifactId>$(echo $BOM_GAV | cut -d: -f2)</artifactId>
                <version>$(echo $BOM_GAV | cut -d: -f3)</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>
</project>
POMPOM
    
    # Run Maven dependency:list
    log_verbose "Running Maven dependency analysis..."
    (cd "$temp_dir" && mvn dependency:list -DoutputFile="$dep_file" -DincludeScope=compile > /dev/null 2>&1) || {
        log_error "Maven dependency analysis failed"
        rm -rf "$temp_dir"
        exit 1
    }
    
    # Parse dependencies
    if [ -f "$dep_file" ]; then
        grep -E "^   " "$dep_file" | sed 's/^   //' | sort -u > "$OUTPUT_DIR/all-dependencies.txt"
        log_success "Found $(wc -l < "$OUTPUT_DIR/all-dependencies.txt") dependencies"
    else
        log_error "Dependency file not created"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    rm -rf "$temp_dir"
}

# Filter dependencies based on include/exclude patterns
filter_dependencies() {
    log_info "Filtering dependencies based on config patterns..."
    
    local all_deps="$OUTPUT_DIR/all-dependencies.txt"
    local filtered_deps="$OUTPUT_DIR/filtered-dependencies.txt"
    
    # Extract include patterns
    local include_patterns=$(yq -r '.dependencyResolutionConfig.includeArtifacts[]?' "$CONFIG_FILE" 2>/dev/null || echo "")
    
    # Extract exclude patterns
    local exclude_patterns=$(yq -r '.dependencyResolutionConfig.excludeArtifacts[]?' "$CONFIG_FILE" 2>/dev/null || echo "")
    
    # Start with all dependencies
    cp "$all_deps" "$filtered_deps.tmp"
    
    # Apply exclude patterns
    if [ -n "$exclude_patterns" ]; then
        log_verbose "Applying exclude patterns..."
        while IFS= read -r pattern; do
            if [ -n "$pattern" ]; then
                # Convert Maven pattern to grep pattern
                local grep_pattern=$(echo "$pattern" | sed 's/\*/[^:]*/g')
                grep -v -E "^$grep_pattern" "$filtered_deps.tmp" > "$filtered_deps.tmp2" || true
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
                grep -E "^$grep_pattern" "$filtered_deps.tmp" >> "$filtered_deps.tmp2" || true
            fi
        done <<< "$include_patterns"
        mv "$filtered_deps.tmp2" "$filtered_deps.tmp"
    fi
    
    # Remove duplicates and save
    sort -u "$filtered_deps.tmp" > "$filtered_deps"
    rm -f "$filtered_deps.tmp" "$filtered_deps.tmp2"
    
    log_success "Filtered to $(wc -l < "$filtered_deps") dependencies to build"
}

# Generate build configs using bacon CLI
generate_build_configs() {
    log_info "Generating PNC build configs using bacon CLI..."
    
    local filtered_deps="$OUTPUT_DIR/filtered-dependencies.txt"
    local configs_dir="$OUTPUT_DIR/build-configs"
    
    mkdir -p "$configs_dir"
    
    local count=0
    local total=$(wc -l < "$filtered_deps")
    
    while IFS= read -r dep; do
        count=$((count + 1))
        log_info "[$count/$total] Processing: $dep"
        
        # Parse GAV
        local group_id=$(echo "$dep" | cut -d: -f1)
        local artifact_id=$(echo "$dep" | cut -d: -f2)
        local version=$(echo "$dep" | cut -d: -f4)
        
        if [ "$DRY_RUN" = true ]; then
            log_verbose "Would generate config for: $group_id:$artifact_id:$version"
            continue
        fi
        
        # Use bacon to generate build config
        local config_name="${group_id}_${artifact_id}_${version}"
        local config_file="$configs_dir/${config_name}.yaml"
        
        log_verbose "Generating config: $config_file"
        
        # bacon pig build-config create command
        bacon pig build-config create \
            --name "$config_name" \
            --scm-url "https://github.com/placeholder/${artifact_id}.git" \
            --scm-revision "$version" \
            --build-script "mvn -DskipTests clean deploy" \
            --output "$config_file" 2>/dev/null || {
            log_warn "Failed to generate config for $dep"
            continue
        }
        
        log_success "Generated: $config_file"
        
    done < "$filtered_deps"
    
    log_success "Build config generation complete"
}

# Generate PIG (Product Integration Group) config
generate_pig_config() {
    log_info "Generating PIG configuration..."
    
    local pig_file="$OUTPUT_DIR/pig-config.yaml"
    
    # Extract PIG template from config
    yq -r '.buildConfigGeneratorConfig.pigTemplate' "$CONFIG_FILE" > "$pig_file"
    
    log_success "Generated PIG config: $pig_file"
}

# Generate summary report
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
- all-dependencies.txt: Complete list of transitive dependencies
- filtered-dependencies.txt: Dependencies after include/exclude filtering
- build-configs/: Individual PNC build configurations
- pig-config.yaml: Product Integration Group configuration
- build-report.txt: This report

Next Steps:
-----------
1. Review the generated build configs in: $OUTPUT_DIR/build-configs/
2. Update SCM URLs in the configs with actual repository locations
3. Use bacon CLI to create builds in PNC:
   bacon pig build-config create -f <config-file>
4. Create build group and trigger builds:
   bacon pig build-group create -f pig-config.yaml

For more information on bacon CLI:
https://project-ncl.github.io/bacon/

================================================================================
REPORT
    
    cat "$report_file"
    log_success "Report saved to: $report_file"
}

# Main execution
main() {
    echo "================================================================================"
    echo "  Transitive Build Config Generator for PNC"
    echo "================================================================================"
    echo ""
    
    parse_args "$@"
    check_prerequisites
    
    # Create output directory
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

# Run main function
main "$@"
