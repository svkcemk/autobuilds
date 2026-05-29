#!/bin/bash
###############################################################################
# Bacon CLI Utility Functions
# 
# Helper functions for working with bacon CLI and PNC
###############################################################################

# Fetch SCM information from Maven Central POM
fetch_scm_from_maven() {
    local group_id="$1"
    local artifact_id="$2"
    local version="$3"
    
    # Convert group ID to path
    local group_path=$(echo "$group_id" | tr '.' '/')
    
    # Maven Central POM URL
    local pom_url="https://repo1.maven.org/maven2/${group_path}/${artifact_id}/${version}/${artifact_id}-${version}.pom"
    
    # Download POM
    local pom_content=$(curl -s "$pom_url")
    
    if [ -z "$pom_content" ]; then
        echo "ERROR: Could not fetch POM from $pom_url" >&2
        return 1
    fi
    
    # Extract SCM URL (simple XML parsing)
    local scm_url=$(echo "$pom_content" | grep -oP '(?<=<connection>)[^<]+' | head -1 | sed 's/scm:git://g' | sed 's/scm:svn://g')
    local scm_tag=$(echo "$pom_content" | grep -oP '(?<=<tag>)[^<]+' | head -1)
    
    # If no tag found, try revision
    if [ -z "$scm_tag" ]; then
        scm_tag=$(echo "$pom_content" | grep -oP '(?<=<revision>)[^<]+' | head -1)
    fi
    
    # Default to version if no tag
    if [ -z "$scm_tag" ]; then
        scm_tag="$version"
    fi
    
    echo "SCM_URL=$scm_url"
    echo "SCM_TAG=$scm_tag"
}

# Apply SCM URL transformations from config
transform_scm_url() {
    local scm_url="$1"
    local config_file="$2"
    
    # Apply pattern replacements
    local patterns=$(yq -r '.buildConfigGeneratorConfig.scmPattern | to_entries[] | "\(.key)|\(.value)"' "$config_file" 2>/dev/null)
    
    while IFS='|' read -r pattern replacement; do
        if [ -n "$pattern" ] && [ -n "$replacement" ]; then
            scm_url=$(echo "$scm_url" | sed "s|$pattern|$replacement|g")
        fi
    done <<< "$patterns"
    
    # Apply direct mappings
    local mappings=$(yq -r '.buildConfigGeneratorConfig.scmMapping | to_entries[] | "\(.key)|\(.value)"' "$config_file" 2>/dev/null)
    
    while IFS='|' read -r original mapped; do
        if [ -n "$original" ] && [ -n "$mapped" ]; then
            if [ "$scm_url" = "$original" ]; then
                scm_url="$mapped"
                break
            fi
        fi
    done <<< "$mappings"
    
    echo "$scm_url"
}

# Create build config using bacon CLI
create_build_config() {
    local name="$1"
    local scm_url="$2"
    local scm_revision="$3"
    local build_script="$4"
    local environment="$5"
    local output_file="$6"
    
    # Create build config YAML
    cat > "$output_file" << YAML
name: $name
description: Auto-generated build config for $name
scmRepository:
  url: $scm_url
  revision: $scm_revision
buildScript: $build_script
environment:
  name: $environment
buildType: MVN
YAML
    
    echo "Created build config: $output_file"
}

# Validate bacon CLI installation
validate_bacon_cli() {
    if ! command -v bacon &> /dev/null; then
        echo "ERROR: bacon CLI not found" >&2
        echo "Install from: https://project-ncl.github.io/bacon/" >&2
        return 1
    fi
    
    # Check bacon version
    local version=$(bacon --version 2>&1 | head -1)
    echo "Found bacon CLI: $version"
    return 0
}

# Create PNC build using bacon
create_pnc_build() {
    local config_file="$1"
    local product_version_id="$2"
    
    if [ ! -f "$config_file" ]; then
        echo "ERROR: Config file not found: $config_file" >&2
        return 1
    fi
    
    echo "Creating PNC build from config: $config_file"
    
    bacon pnc build-config create \
        --file "$config_file" \
        --product-version-id "$product_version_id" || {
        echo "ERROR: Failed to create build config in PNC" >&2
        return 1
    }
    
    echo "Build config created successfully"
}

# Trigger build in PNC
trigger_pnc_build() {
    local build_config_id="$1"
    local rebuild_mode="${2:-IMPLICIT_DEPENDENCY_CHECK}"
    
    echo "Triggering build for config ID: $build_config_id"
    
    bacon pnc build start \
        --build-config-id "$build_config_id" \
        --rebuild-mode "$rebuild_mode" || {
        echo "ERROR: Failed to trigger build" >&2
        return 1
    }
    
    echo "Build triggered successfully"
}

# Create build group
create_build_group() {
    local group_name="$1"
    local product_version_id="$2"
    shift 2
    local build_config_ids=("$@")
    
    echo "Creating build group: $group_name"
    
    local config_ids_arg=""
    for id in "${build_config_ids[@]}"; do
        config_ids_arg="$config_ids_arg --build-config-id $id"
    done
    
    bacon pnc build-group create \
        --name "$group_name" \
        --product-version-id "$product_version_id" \
        $config_ids_arg || {
        echo "ERROR: Failed to create build group" >&2
        return 1
    }
    
    echo "Build group created successfully"
}

# Get build status
get_build_status() {
    local build_id="$1"
    
    bacon pnc build get --id "$build_id" --output json | \
        jq -r '.status' 2>/dev/null || echo "UNKNOWN"
}

# Wait for build completion
wait_for_build() {
    local build_id="$1"
    local timeout="${2:-3600}"  # Default 1 hour
    local interval="${3:-30}"   # Check every 30 seconds
    
    echo "Waiting for build $build_id to complete..."
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local status=$(get_build_status "$build_id")
        
        case "$status" in
            SUCCESS)
                echo "Build completed successfully"
                return 0
                ;;
            FAILED|CANCELLED|SYSTEM_ERROR)
                echo "Build failed with status: $status"
                return 1
                ;;
            *)
                echo "Build status: $status (elapsed: ${elapsed}s)"
                sleep $interval
                elapsed=$((elapsed + interval))
                ;;
        esac
    done
    
    echo "Build timeout after ${timeout}s"
    return 1
}

# Export functions for use in other scripts
export -f fetch_scm_from_maven
export -f transform_scm_url
export -f create_build_config
export -f validate_bacon_cli
export -f create_pnc_build
export -f trigger_pnc_build
export -f create_build_group
export -f get_build_status
export -f wait_for_build
