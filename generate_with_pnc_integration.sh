#!/bin/bash

# Enhanced build config generator with PNC integration
# Checks PNC first for existing SCM info, falls back to POM analysis

set -e

# Configuration
PNC_API_BASE="${PNC_API_BASE:-https://orch.psi.redhat.com/pnc-rest/v2}"
OUTPUT_DIR="${1:-output}"
ARTIFACT="${2}"
VERSION="${3}"

if [[ -z "$ARTIFACT" ]] || [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <output-dir> <groupId:artifactId> <version>"
    echo "Example: $0 output org.apache.camel:camel-api 4.18.1"
    exit 1
fi

# Parse artifact coordinates
GROUP_ID=$(echo "$ARTIFACT" | cut -d: -f1)
ARTIFACT_ID=$(echo "$ARTIFACT" | cut -d: -f2)

echo "=== PNC-Integrated Build Config Generator ==="
echo "Artifact: $GROUP_ID:$ARTIFACT_ID:$VERSION"
echo "Output: $OUTPUT_DIR"
echo ""

# Create output directories
mkdir -p "$OUTPUT_DIR/build-configs"
mkdir -p "$OUTPUT_DIR/pnc-cache"

# Function to query PNC for existing build config
query_pnc_build_config() {
    local group_id="$1"
    local artifact_id="$2"
    local version="$3"
    
    echo "Querying PNC for existing build config..."
    
    # Search by artifact name pattern
    local search_name="${artifact_id}"
    local api_url="${PNC_API_BASE}/build-configs?q=name==${search_name}"
    
    echo "  API: $api_url"
    
    # Query PNC API
    local response=$(curl -s -X GET "$api_url" \
        -H "Accept: application/json" \
        2>/dev/null || echo "{}")
    
    # Save response for debugging
    echo "$response" > "$OUTPUT_DIR/pnc-cache/${group_id}_${artifact_id}_search.json"
    
    # Check if we got results
    local count=$(echo "$response" | jq -r '.content | length' 2>/dev/null || echo "0")
    
    if [[ "$count" -gt 0 ]]; then
        echo "  Found $count existing build config(s) in PNC"
        
        # Extract SCM info from first matching config
        local scm_url=$(echo "$response" | jq -r '.content[0].scmRepository.internalUrl // .content[0].scmRepository.externalUrl // empty' 2>/dev/null)
        local scm_revision=$(echo "$response" | jq -r '.content[0].scmRevision // empty' 2>/dev/null)
        local build_script=$(echo "$response" | jq -r '.content[0].buildScript // empty' 2>/dev/null)
        local env_id=$(echo "$response" | jq -r '.content[0].environment.id // empty' 2>/dev/null)
        local env_name=$(echo "$response" | jq -r '.content[0].environment.name // empty' 2>/dev/null)
        
        # Save extracted info
        cat > "$OUTPUT_DIR/pnc-cache/${group_id}_${artifact_id}_scm.json" <<EOF
{
  "source": "pnc",
  "scmUrl": "$scm_url",
  "scmRevision": "$scm_revision",
  "buildScript": "$build_script",
  "environmentId": "$env_id",
  "environmentName": "$env_name"
}
EOF
        
        echo "  SCM URL: $scm_url"
        echo "  Revision: $scm_revision"
        echo "  Environment: $env_name (ID: $env_id)"
        
        return 0
    else
        echo "  No existing build config found in PNC"
        return 1
    fi
}

# Function to extract SCM from POM (fallback)
extract_scm_from_pom() {
    local group_id="$1"
    local artifact_id="$2"
    local version="$3"
    
    echo "Extracting SCM from POM (fallback)..."
    
    # Download POM
    local pom_url="https://repo1.maven.org/maven2/${group_id//.//}/${artifact_id}/${version}/${artifact_id}-${version}.pom"
    local pom_file="$OUTPUT_DIR/pnc-cache/${artifact_id}-${version}.pom"
    
    echo "  Downloading: $pom_url"
    curl -s -o "$pom_file" "$pom_url" 2>/dev/null || {
        echo "  Failed to download POM"
        return 1
    }
    
    # Extract SCM URL
    local scm_url=$(xmllint --xpath "string(//scm/connection)" "$pom_file" 2>/dev/null | sed 's/scm:git://g' || echo "")
    
    if [[ -z "$scm_url" ]]; then
        scm_url=$(xmllint --xpath "string(//scm/url)" "$pom_file" 2>/dev/null || echo "")
    fi
    
    # Try parent POM if not found
    if [[ -z "$scm_url" ]]; then
        local parent_group=$(xmllint --xpath "string(//parent/groupId)" "$pom_file" 2>/dev/null || echo "")
        local parent_artifact=$(xmllint --xpath "string(//parent/artifactId)" "$pom_file" 2>/dev/null || echo "")
        local parent_version=$(xmllint --xpath "string(//parent/version)" "$pom_file" 2>/dev/null || echo "")
        
        if [[ -n "$parent_group" ]] && [[ -n "$parent_artifact" ]]; then
            echo "  Checking parent POM: $parent_group:$parent_artifact:$parent_version"
            local parent_pom_url="https://repo1.maven.org/maven2/${parent_group//.//}/${parent_artifact}/${parent_version}/${parent_artifact}-${parent_version}.pom"
            local parent_pom_file="$OUTPUT_DIR/pnc-cache/${parent_artifact}-${parent_version}.pom"
            
            curl -s -o "$parent_pom_file" "$parent_pom_url" 2>/dev/null
            scm_url=$(xmllint --xpath "string(//scm/connection)" "$parent_pom_file" 2>/dev/null | sed 's/scm:git://g' || echo "")
            
            if [[ -z "$scm_url" ]]; then
                scm_url=$(xmllint --xpath "string(//scm/url)" "$parent_pom_file" 2>/dev/null || echo "")
            fi
        fi
    fi
    
    # Determine Java version from POM
    local java_version=$(xmllint --xpath "string(//maven.compiler.release)" "$pom_file" 2>/dev/null || \
                        xmllint --xpath "string(//maven.compiler.target)" "$pom_file" 2>/dev/null || \
                        echo "11")
    
    # Map to environment ID
    local env_id="1200"  # Default Java 11
    local env_name="OpenJDK 11.0; Mvn 3.5.4"
    
    case "$java_version" in
        8|1.8)
            env_id="660"
            env_name="OpenJDK 1.8.0; Mvn 3.5.4"
            ;;
        11)
            env_id="1200"
            env_name="OpenJDK 11.0; Mvn 3.5.4"
            ;;
        17)
            env_id="316"
            env_name="OpenJDK 17.0; Mvn 3.8.1"
            ;;
    esac
    
    # Save extracted info
    cat > "$OUTPUT_DIR/pnc-cache/${group_id}_${artifact_id}_scm.json" <<EOF
{
  "source": "pom",
  "scmUrl": "$scm_url",
  "scmRevision": "$version",
  "buildScript": "mvn -Dmaven.test.skip=true -Dartifactory.staging.skip=true -DskipNexusStagingDeployMojo=true clean deploy",
  "environmentId": "$env_id",
  "environmentName": "$env_name"
}
EOF
    
    echo "  SCM URL: $scm_url"
    echo "  Java Version: $java_version"
    echo "  Environment: $env_name (ID: $env_id)"
    
    return 0
}

# Function to generate build config YAML
generate_build_config() {
    local group_id="$1"
    local artifact_id="$2"
    local version="$3"
    local scm_info_file="$4"
    
    # Read SCM info
    local source=$(jq -r '.source' "$scm_info_file")
    local scm_url=$(jq -r '.scmUrl' "$scm_info_file")
    local scm_revision=$(jq -r '.scmRevision' "$scm_info_file")
    local build_script=$(jq -r '.buildScript' "$scm_info_file")
    local env_id=$(jq -r '.environmentId' "$scm_info_file")
    local env_name=$(jq -r '.environmentName' "$scm_info_file")
    
    # Generate filename
    local filename="${group_id}_${artifact_id}_${version}.yaml"
    local output_file="$OUTPUT_DIR/build-configs/$filename"
    
    echo "Generating build config: $filename"
    echo "  Source: $source"
    
    # Create YAML
    cat > "$output_file" <<EOF
name: ${group_id}_${artifact_id}_${version}
description: Build config for ${artifact_id} (SCM from ${source})
project: ${group_id}_${artifact_id}
scmRepository:
  url: ${scm_url}
  revision: ${scm_revision}
buildScript: ${build_script}
environment:
  id: ${env_id}
  name: ${env_name}
buildType: MVN
EOF
    
    echo "  Created: $output_file"
}

# Main workflow
echo "Step 1: Query PNC for existing build config"
if query_pnc_build_config "$GROUP_ID" "$ARTIFACT_ID" "$VERSION"; then
    echo "✓ Using SCM info from PNC"
else
    echo "Step 2: Extract SCM from POM (fallback)"
    if extract_scm_from_pom "$GROUP_ID" "$ARTIFACT_ID" "$VERSION"; then
        echo "✓ Using SCM info from POM"
    else
        echo "✗ Failed to extract SCM info"
        exit 1
    fi
fi

echo ""
echo "Step 3: Generate build config YAML"
generate_build_config "$GROUP_ID" "$ARTIFACT_ID" "$VERSION" \
    "$OUTPUT_DIR/pnc-cache/${GROUP_ID}_${ARTIFACT_ID}_scm.json"

echo ""
echo "=== Build Config Generation Complete ==="
echo "Output directory: $OUTPUT_DIR"
echo "Build config: $OUTPUT_DIR/build-configs/${GROUP_ID}_${ARTIFACT_ID}_${VERSION}.yaml"
echo "PNC cache: $OUTPUT_DIR/pnc-cache/"
