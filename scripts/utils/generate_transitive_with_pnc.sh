#!/bin/bash

# Complete transitive dependency build config generator with PNC integration
# Queries PNC for existing configs, falls back to POM analysis, generates pig-config.yaml

set -e

# Configuration
PNC_API_BASE="${PNC_API_BASE:-https://orch.psi.redhat.com/pnc-rest/v2}"
OUTPUT_DIR="${1:-output}"
ROOT_ARTIFACT="${2}"
ROOT_VERSION="${3}"
MILESTONE="${4}"  # Optional: user-defined milestone

if [[ -z "$ROOT_ARTIFACT" ]] || [[ -z "$ROOT_VERSION" ]]; then
    echo "Usage: $0 <output-dir> <groupId:artifactId> <version> [milestone]"
    echo "Example: $0 camel-api-output org.apache.camel:camel-api 4.18.1"
    echo "Example: $0 camel-api-output org.apache.camel:camel-api 4.18.1 4.18.1.DR2"
    echo ""
    echo "If milestone is not provided, it will be auto-incremented from the latest PNC product version."
    exit 1
fi

# Parse artifact coordinates
ROOT_GROUP_ID=$(echo "$ROOT_ARTIFACT" | cut -d: -f1)
ROOT_ARTIFACT_ID=$(echo "$ROOT_ARTIFACT" | cut -d: -f2)

echo "=== PNC-Integrated Transitive Build Config Generator ==="
echo "Root Artifact: $ROOT_ARTIFACT:$ROOT_VERSION"
echo "Output: $OUTPUT_DIR"
echo ""

# Create output directories
mkdir -p "$OUTPUT_DIR/build-configs"
mkdir -p "$OUTPUT_DIR/pnc-cache"
mkdir -p "$OUTPUT_DIR/temp"

# Step 1: Create temporary POM for dependency analysis
echo "Step 1: Creating temporary POM for dependency analysis..."

cat > "$OUTPUT_DIR/temp/pom.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    
    <groupId>temp.analysis</groupId>
    <artifactId>dependency-analyzer</artifactId>
    <version>1.0.0</version>
    <packaging>pom</packaging>
    
    <dependencies>
        <dependency>
            <groupId>$ROOT_GROUP_ID</groupId>
            <artifactId>$ROOT_ARTIFACT_ID</artifactId>
            <version>$ROOT_VERSION</version>
        </dependency>
    </dependencies>
</project>
EOF

echo "Created temporary POM at $OUTPUT_DIR/temp/pom.xml"
echo ""

# Step 2: Detect if this is a BOM and extract dependencies accordingly
echo "Step 2: Detecting artifact type and extracting dependencies..."

# Try to download the POM to check if it's a BOM
BOM_URL=""
if [[ "$ROOT_VERSION" =~ redhat ]]; then
    # Try Red Hat Indy repository first
    BOM_URL="https://indy.corp.redhat.com/api/content/maven/hosted/pnc-builds/${ROOT_GROUP_ID//.//}/${ROOT_ARTIFACT_ID}/${ROOT_VERSION}/${ROOT_ARTIFACT_ID}-${ROOT_VERSION}.pom"
else
    # Try Maven Central
    BOM_URL="https://repo1.maven.org/maven2/${ROOT_GROUP_ID//.//}/${ROOT_ARTIFACT_ID}/${ROOT_VERSION}/${ROOT_ARTIFACT_ID}-${ROOT_VERSION}.pom"
fi

echo "Downloading artifact POM from: $BOM_URL"
if curl -s -f -o "$OUTPUT_DIR/temp/artifact.pom" "$BOM_URL" 2>/dev/null; then
    # Check if it's a BOM (packaging=pom AND has dependencyManagement section)
    packaging=$(grep "<packaging>" "$OUTPUT_DIR/temp/artifact.pom" | sed 's/.*<packaging>\(.*\)<\/packaging>.*/\1/' | head -1)
    has_dep_mgmt=$(grep -c "<dependencyManagement>" "$OUTPUT_DIR/temp/artifact.pom")
    
    if [[ "$packaging" == "pom" ]] && [[ "$has_dep_mgmt" -gt 0 ]]; then
        echo "✓ Detected BOM artifact (packaging=pom) - extracting managed dependencies"
        
        # Extract managed dependencies from BOM - skip exclusions
        awk '
            /<dependencyManagement>/,/<\/dependencyManagement>/ {
                if (/<exclusions>/) { in_exclusions=1 }
                if (/<\/exclusions>/) { in_exclusions=0; next }
                if (in_exclusions) next
                
                if (/<dependency>/) { dep=1; group=""; artifact=""; version="" }
                if (dep && /<groupId>/) { gsub(/.*<groupId>|<\/groupId>.*/, ""); group=$0 }
                if (dep && /<artifactId>/) { gsub(/.*<artifactId>|<\/artifactId>.*/, ""); artifact=$0 }
                if (dep && /<version>/) { gsub(/.*<version>|<\/version>.*/, ""); version=$0 }
                if (/<\/dependency>/ && dep) {
                    if (group && artifact && version && version !~ /\$\{/ && group !~ /\*/) {
                        print group ":" artifact ":" version
                    }
                    dep=0
                }
            }
        ' "$OUTPUT_DIR/temp/artifact.pom" | \
            grep -v "^${ROOT_GROUP_ID}:${ROOT_ARTIFACT_ID}:" | \
            sort -u > "$OUTPUT_DIR/bom-managed-deps.txt"
        
        bom_count=$(wc -l < "$OUTPUT_DIR/bom-managed-deps.txt" | tr -d ' ')
        echo "Found $bom_count managed dependencies in BOM"
        echo "BOM entries will be treated as the artifacts to build (no transitive analysis needed)"
        
        # Copy BOM entries directly as the dependency list
        cp "$OUTPUT_DIR/bom-managed-deps.txt" "$OUTPUT_DIR/all-dependencies.txt"
        
        # Format for filtering: convert to Maven dependency format
        sed 's/\(.*\):\(.*\):\(.*\)/\1:\2:jar:\3:compile/' "$OUTPUT_DIR/all-dependencies.txt" > "$OUTPUT_DIR/all-dependencies.tmp"
        mv "$OUTPUT_DIR/all-dependencies.tmp" "$OUTPUT_DIR/all-dependencies.txt"
        
        # Skip the transitive analysis loop entirely for BOMs
        # The managed dependencies in the BOM are what we want to build
        
        echo "Extracting unique third-party dependencies from BOM entries..."
        
        # For BOMs, convert from Maven format (group:artifact:jar:version:compile) to simple format (group:artifact:version)
        awk -F: '{print $1":"$2":"$4}' "$OUTPUT_DIR/all-dependencies.txt" | \
            grep -v ":test" | \
            grep -v "^${ROOT_GROUP_ID}:" | \
            sort -u > "$OUTPUT_DIR/filtered-dependencies.txt"
        
        dep_count=$(wc -l < "$OUTPUT_DIR/filtered-dependencies.txt" | tr -d ' ')
        echo "Found $dep_count unique third-party transitive dependencies"
        echo ""
    else
        echo "✓ Regular artifact - analyzing transitive dependencies"
        
        cd "$OUTPUT_DIR/temp"
        MAVEN_OPTS="-XX:+IgnoreUnrecognizedVMOptions --add-opens=java.base/java.lang=ALL-UNNAMED" \
        mvn -q dependency:tree \
            -DoutputFile="../all-dependencies.txt" \
            -DoutputType=text \
            -DappendOutput=false \
            2>&1 | grep -v "WARNING:" | tee "../maven-output.log"
        
        cd - > /dev/null
        
        # Check if dependency analysis succeeded
        if [[ ! -f "$OUTPUT_DIR/all-dependencies.txt" ]]; then
            echo "ERROR: Failed to analyze dependencies. Check $OUTPUT_DIR/maven-output.log"
            exit 1
        fi
        
        # Extract unique dependencies (exclude test scope and root artifact only)
        grep -E "[+\\\\-]" "$OUTPUT_DIR/all-dependencies.txt" | \
            grep -v ":test" | \
            sed -E 's/.*[+\\-] ([^:]+):([^:]+):jar:([^:]+):.*/\1:\2:\3/' | \
            grep -v "^temp.analysis:" | \
            grep -v "^${ROOT_GROUP_ID}:${ROOT_ARTIFACT_ID}:" | \
            sort -u > "$OUTPUT_DIR/filtered-dependencies.txt"
        
        dep_count=$(wc -l < "$OUTPUT_DIR/filtered-dependencies.txt" | tr -d ' ')
        echo "Found $dep_count unique dependencies (excluding test scope)"
        echo ""
    fi
else
    echo "ERROR: Failed to download artifact POM from $BOM_URL"
    exit 1
fi

# Get dependency count for parallel processing
dep_count=$(wc -l < "$OUTPUT_DIR/filtered-dependencies.txt" | tr -d ' ')

# Function to query PNC for build config
query_pnc_build_config() {
    local group_id="$1"
    local artifact_id="$2"
    local version="$3"
    
    local cache_file="$OUTPUT_DIR/pnc-cache/${group_id}_${artifact_id}_${version}_pnc.json"
    
    # Check cache first
    if [[ -f "$cache_file" ]]; then
        return 0
    fi
    
    # Query PNC API with wildcard pattern
    local search_name="${artifact_id}"
    local api_url="${PNC_API_BASE}/build-configs?q=name=like=*${search_name}*"
    
    local response=$(curl -s -X GET "$api_url" \
        -H "Accept: application/json" \
        2>/dev/null || echo '{"content":[]}')
    
    echo "$response" > "$cache_file"
    
    local count=$(echo "$response" | jq -r '.content | length' 2>/dev/null || echo "0")
    
    if [[ "$count" -gt 0 ]]; then
        # Find best match by version
        local best_match=$(echo "$response" | jq -r --arg ver "$version" \
            '.content[] | select(.scmRevision | contains($ver)) | .id' 2>/dev/null | head -1)
        
        if [[ -n "$best_match" ]]; then
            
            # Get full build config details
            local detail_url="${PNC_API_BASE}/build-configs/${best_match}"
            local detail_response=$(curl -s -X GET "$detail_url" \
                -H "Accept: application/json" 2>/dev/null || echo '{}')
            
            echo "$detail_response" > "${cache_file%.json}_detail.json"
            return 0
        fi
    fi
    
    echo "  [PNC] No matching config found"
    return 1
}

# Function to extract SCM from POM
extract_scm_from_pom() {
    local group_id="$1"
    local artifact_id="$2"
    local version="$3"
    
    local pom_file="$OUTPUT_DIR/temp/${artifact_id}-${version}.pom"
    local pom_url=""
    
    # Try Red Hat Indy first if version contains 'redhat'
    if [[ "$version" =~ redhat ]] || [[ "$ROOT_VERSION" =~ redhat ]]; then
        # If processing BOM dependencies, try with Red Hat version suffix
        if [[ "$ROOT_VERSION" =~ redhat ]] && [[ ! "$version" =~ redhat ]]; then
            # Extract redhat suffix from root version (e.g., 00038 from 4.18.1.redhat-00038)
            local redhat_suffix=$(echo "$ROOT_VERSION" | grep -o 'redhat-[0-9]*')
            local redhat_version="${version}.${redhat_suffix}"
            pom_url="https://indy.corp.redhat.com/api/content/maven/hosted/pnc-builds/${group_id//.//}/${artifact_id}/${redhat_version}/${artifact_id}-${redhat_version}.pom"
            
            if curl -s -f -o "$pom_file" "$pom_url" 2>/dev/null; then
                version="$redhat_version"  # Update version for later use
            else
                # Fallback to original version from Maven Central
                pom_url="https://repo1.maven.org/maven2/${group_id//.//}/${artifact_id}/${version}/${artifact_id}-${version}.pom"
                
                if ! curl -s -f -o "$pom_file" "$pom_url" 2>/dev/null; then
                    return 1
                fi
            fi
        else
            pom_url="https://indy.corp.redhat.com/api/content/maven/hosted/pnc-builds/${group_id//.//}/${artifact_id}/${version}/${artifact_id}-${version}.pom"
            
            if ! curl -s -f -o "$pom_file" "$pom_url" 2>/dev/null; then
                return 1
            fi
        fi
    else
        pom_url="https://repo1.maven.org/maven2/${group_id//.//}/${artifact_id}/${version}/${artifact_id}-${version}.pom"
        
        if ! curl -s -f -o "$pom_file" "$pom_url" 2>/dev/null; then
            return 1
        fi
    fi
    
    # Extract SCM
    local scm_connection=$(xmllint --xpath "string(//scm/connection)" "$pom_file" 2>/dev/null | sed 's/scm:git://g')
    local scm_url=$(xmllint --xpath "string(//scm/url)" "$pom_file" 2>/dev/null)
    local scm_tag=$(xmllint --xpath "string(//scm/tag)" "$pom_file" 2>/dev/null)
    
    # Use connection if available, otherwise URL
    local final_scm="${scm_connection:-$scm_url}"
    
    # Try parent POMs recursively if not found (up to 3 levels)
    if [[ -z "$final_scm" ]]; then
        current_pom="$pom_file"
        for level in 1 2 3; do
            # Use grep to extract parent info (handles XML namespaces better)
            parent_group=$(grep -A 3 "<parent>" "$current_pom" | grep "<groupId>" | sed 's/.*<groupId>\(.*\)<\/groupId>.*/\1/' | head -1)
            parent_artifact=$(grep -A 3 "<parent>" "$current_pom" | grep "<artifactId>" | sed 's/.*<artifactId>\(.*\)<\/artifactId>.*/\1/' | head -1)
            parent_version=$(grep -A 3 "<parent>" "$current_pom" | grep "<version>" | sed 's/.*<version>\(.*\)<\/version>.*/\1/' | head -1)
            
            if [[ -z "$parent_group" ]] || [[ -z "$parent_artifact" ]]; then
                break
            fi
            
            parent_pom="$OUTPUT_DIR/temp/${parent_artifact}-${parent_version}.pom"
            parent_url="https://repo1.maven.org/maven2/${parent_group//.//}/${parent_artifact}/${parent_version}/${parent_artifact}-${parent_version}.pom"
            
            if curl -s -f -o "$parent_pom" "$parent_url" 2>/dev/null; then
                # Extract SCM from parent
                scm_connection=$(grep -A 5 "<scm>" "$parent_pom" | grep "<connection>" | sed 's/.*<connection>\(.*\)<\/connection>.*/\1/' | sed 's/scm:git://g' | head -1)
                scm_url=$(grep -A 5 "<scm>" "$parent_pom" | grep "<url>" | sed 's/.*<url>\(.*\)<\/url>.*/\1/' | head -1)
                final_scm="${scm_connection:-$scm_url}"
                
                if [[ -n "$final_scm" ]]; then
                    break
                fi
                
                current_pom="$parent_pom"
            else
                break
            fi
        done
    fi
    
    # Determine Java version
    local java_version=$(xmllint --xpath "string(//maven.compiler.release)" "$pom_file" 2>/dev/null || \
                        xmllint --xpath "string(//maven.compiler.target)" "$pom_file" 2>/dev/null || \
                        echo "11")
    
    # Map to environment
    local env_id="1200"
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
    
    # Save SCM info
    cat > "$OUTPUT_DIR/pnc-cache/${group_id}_${artifact_id}_${version}_scm.json" <<EOF
{
  "source": "pom",
  "scmUrl": "${final_scm}",
  "scmRevision": "${scm_tag:-$version}",
  "buildScript": "mvn -Dmaven.test.skip=true -Dartifactory.staging.skip=true -DskipNexusStagingDeployMojo=true clean deploy",
  "environmentId": "${env_id}",
  "environmentName": "${env_name}",
  "javaVersion": "${java_version}"
}
EOF
    
    echo "  [POM] SCM: ${final_scm}"
    echo "  [POM] Java: ${java_version} -> Env ${env_id}"
    
    return 0
}

# Function to generate build config from PNC data
generate_from_pnc() {
    local group_id="$1"
    local artifact_id="$2"
    local version="$3"
    local pnc_detail_file="$4"
    
    local scm_url=$(jq -r '.scmRepository.internalUrl // .scmRepository.externalUrl // ""' "$pnc_detail_file")
    local scm_revision=$(jq -r '.scmRevision // ""' "$pnc_detail_file")
    local build_script=$(jq -r '.buildScript // ""' "$pnc_detail_file")
    local env_id=$(jq -r '.environment.id // ""' "$pnc_detail_file")
    local env_name=$(jq -r '.environment.name // ""' "$pnc_detail_file")
    local project_name=$(jq -r '.project.name // ""' "$pnc_detail_file")
    local default_alignment=$(jq -r '.defaultAlignmentParams // ""' "$pnc_detail_file")
    local brew_pull=$(jq -r '.brewPullActive // false' "$pnc_detail_file")
    
    local filename="${group_id}_${artifact_id}_${version}.yaml"
    local output_file="$OUTPUT_DIR/build-configs/$filename"
    
    cat > "$output_file" <<EOF
name: ${group_id}_${artifact_id}_${version}
description: Build config for ${artifact_id} (from PNC)
project: ${project_name:-${group_id}_${artifact_id}}
scmRepository:
  url: ${scm_url}
  revision: ${scm_revision}
buildScript: ${build_script}
environment:
  id: ${env_id}
  name: ${env_name}
buildType: MVN
EOF

    # Add defaultAlignmentParams if present
    if [[ -n "$default_alignment" ]]; then
        echo "defaultAlignmentParams: ${default_alignment}" >> "$output_file"
    fi
    
    # Add brewPullActive if true
    if [[ "$brew_pull" == "true" ]]; then
        echo "brewPullActive: true" >> "$output_file"
    fi
    
    # Extract and add parameters if present
    local params=$(jq -r '.parameters // {}' "$pnc_detail_file")
    if [[ "$params" != "{}" ]]; then
        echo "parameters:" >> "$output_file"
        echo "$params" | jq -r 'to_entries[] | "  \(.key): \"\(.value)\""' >> "$output_file"
    fi
    
    echo "  [YAML] Created from PNC: $filename"
}

# Function to generate build config from POM data
generate_from_pom() {
    local group_id="$1"
    local artifact_id="$2"
    local version="$3"
    local scm_file="$4"
    
    local scm_url=$(jq -r '.scmUrl' "$scm_file")
    local scm_revision=$(jq -r '.scmRevision' "$scm_file")
    local build_script=$(jq -r '.buildScript' "$scm_file")
    local env_id=$(jq -r '.environmentId' "$scm_file")
    local env_name=$(jq -r '.environmentName' "$scm_file")
    
    local filename="${group_id}_${artifact_id}_${version}.yaml"
    local output_file="$OUTPUT_DIR/build-configs/$filename"
    
    # Start building the YAML
    cat > "$output_file" <<EOF
name: ${group_id}_${artifact_id}_${version}
description: Build config for ${artifact_id} (from POM analysis)
project: ${group_id}_${artifact_id}
EOF
    
    # Only add scmRepository if URL is found
    if [[ -n "$scm_url" ]] && [[ "$scm_url" != "null" ]]; then
        cat >> "$output_file" <<EOF
scmRepository:
  url: ${scm_url}
  revision: ${scm_revision}
EOF
    else
        echo "  [WARNING] No SCM URL found - scmRepository section omitted"
    fi
    
    # Add remaining fields
    cat >> "$output_file" <<EOF
buildScript: ${build_script}
environment:
  id: ${env_id}
  name: ${env_name}
buildType: MVN
EOF
    
    echo "  [YAML] Created from POM: $filename"
}

# Step 3: Process each dependency with parallel processing
echo "Step 3: Processing dependencies with PNC integration (parallel mode)..."
echo ""

# Track builds without SCM
> "$OUTPUT_DIR/no-scm-builds.txt"

# Function to process a single dependency
process_single_dep() {
    local group_id="$1"
    local artifact_id="$2"
    local version="$3"
    local dep_num="$4"
    local total="$5"
    
    echo "[$dep_num/$total] Processing: $group_id:$artifact_id:$version"
    
    # Try PNC first
    if query_pnc_build_config "$group_id" "$artifact_id" "$version"; then
        detail_file="$OUTPUT_DIR/pnc-cache/${group_id}_${artifact_id}_${version}_pnc_detail.json"
        if [[ -f "$detail_file" ]]; then
            generate_from_pnc "$group_id" "$artifact_id" "$version" "$detail_file"
            echo ""
            return 0
        fi
    fi
    
    # Fallback to POM
    if extract_scm_from_pom "$group_id" "$artifact_id" "$version"; then
        scm_file="$OUTPUT_DIR/pnc-cache/${group_id}_${artifact_id}_${version}_scm.json"
        scm_url=$(jq -r '.scmUrl' "$scm_file")
        
        if [[ -z "$scm_url" ]] || [[ "$scm_url" == "null" ]]; then
            echo "  [WARNING] No SCM URL found - skipping build config generation"
            echo "${group_id}:${artifact_id}:${version}" >> "$OUTPUT_DIR/no-scm-builds.txt"
        else
            generate_from_pom "$group_id" "$artifact_id" "$version" "$scm_file"
        fi
    else
        echo "  [ERROR] Failed to extract SCM info"
    fi
    
    echo ""
    return 0
}

export -f process_single_dep
export -f query_pnc_build_config
export -f extract_scm_from_pom
export -f generate_from_pnc
export -f generate_from_pom
export OUTPUT_DIR
export PNC_API_BASE

# Process in parallel (16 at a time for maximum speed)
cat "$OUTPUT_DIR/filtered-dependencies.txt" | nl -nln | while read num line; do
    echo "$line:$num:$dep_count"
done | xargs -P 16 -I {} bash -c '
    IFS=: read -r g a v n t <<< "{}"
    process_single_dep "$g" "$a" "$v" "$n" "$t"
'

# Count results after parallel processing
processed=$dep_count
pnc_hits=$(find "$OUTPUT_DIR/build-configs" -name "*.yaml" -exec grep -l "from PNC" {} \; 2>/dev/null | wc -l | tr -d ' ')
pom_hits=$(find "$OUTPUT_DIR/build-configs" -name "*.yaml" -exec grep -l "from POM" {} \; 2>/dev/null | wc -l | tr -d ' ')
no_scm_count=$(wc -l < "$OUTPUT_DIR/no-scm-builds.txt" 2>/dev/null | tr -d ' ')
failures=$((processed - pnc_hits - pom_hits - no_scm_count))

# Step 4: Generate pig-config.yaml with detailed build information
echo "Step 4: Generating pig-config.yaml..."

# Get product name from PNC (Product ID 163)
PRODUCT_NAME=$(curl -s "https://orch.psi.redhat.com/pnc-rest/v2/products/163" -H "Accept: application/json" 2>/dev/null | jq -r '.name // "Camel Extensions for Quarkus Third Party Components"')
PRODUCT_ABBREV=$(echo "$PRODUCT_NAME" | tr '[:lower:]' '[:upper:]' | tr ' ' '_' | sed 's/[^A-Z0-9_]//g')

# Determine milestone: user-provided or default to DR1
if [[ -z "$MILESTONE" ]]; then
    MILESTONE="${ROOT_VERSION}.DR1"
    echo "Using default milestone: $MILESTONE (use 4th parameter to override)"
else
    echo "Using provided milestone: $MILESTONE"
fi

cat > "$OUTPUT_DIR/pig-config.yaml" <<EOF
---
product:
  name: "$PRODUCT_NAME"
  abbreviation: "$PRODUCT_ABBREV"
  version: "$ROOT_VERSION"
  milestone: "$MILESTONE"

builds:
EOF

# Add detailed build entries
for config_file in "$OUTPUT_DIR/build-configs"/*.yaml; do
    [[ -f "$config_file" ]] || continue
    
    build_name=$(basename "$config_file" .yaml)
    
    # Extract info from individual config
    name=$(grep "^name:" "$config_file" | cut -d: -f2- | xargs)
    description=$(grep "^description:" "$config_file" | cut -d: -f2- | xargs)
    scm_url=$(grep "url:" "$config_file" | grep -v "^name:" | cut -d: -f2- | xargs)
    scm_revision=$(grep "revision:" "$config_file" | cut -d: -f2- | xargs)
    build_script=$(grep "buildScript:" "$config_file" | cut -d: -f2- | xargs)
    env_id=$(grep -A2 "^environment:" "$config_file" | grep "id:" | cut -d: -f2- | xargs)
    env_name=$(grep -A2 "^environment:" "$config_file" | grep "name:" | cut -d: -f2- | xargs)
    
    cat >> "$OUTPUT_DIR/pig-config.yaml" <<EOF
  - name: "$name"
    description: "$description"
    scmUrl: "$scm_url"
    scmRevision: "$scm_revision"
    buildScript: |
      $build_script
    environmentId: $env_id
    environmentName: "$env_name"
    buildType: "MVN"

EOF
done

# Add build order section
cat >> "$OUTPUT_DIR/pig-config.yaml" <<EOF
buildOrder:
EOF

for config_file in "$OUTPUT_DIR/build-configs"/*.yaml; do
    [[ -f "$config_file" ]] || continue
    name=$(grep "^name:" "$config_file" | cut -d: -f2- | xargs)
    echo "  - \"$name\"" >> "$OUTPUT_DIR/pig-config.yaml"
done

build_count=$(grep -c "^  - name:" "$OUTPUT_DIR/pig-config.yaml" || echo "0")
echo "Created pig-config.yaml with $build_count builds"
echo ""

# Step 5: Generate summary report

# Step 5: Analyze productization status (for Red Hat artifacts)
if [[ "$ROOT_VERSION" =~ redhat ]]; then
    echo "Step 5: Analyzing productization status..."
    
    build_from_source=0
    pending_productized=0
    
    > "$OUTPUT_DIR/build-from-source.txt"
    > "$OUTPUT_DIR/pending-productized.txt"
    
    while IFS=: read -r dep_group dep_artifact dep_version; do
        [[ -z "$dep_group" ]] && continue
        
        # Extract redhat suffix from root version
        redhat_suffix=$(echo "$ROOT_VERSION" | grep -o 'redhat-[0-9]*')
        redhat_version="${dep_version}.${redhat_suffix}"
        
        # Check if .redhat version exists in Indy
        indy_url="https://indy.corp.redhat.com/api/content/maven/hosted/pnc-builds/${dep_group//.//}/${dep_artifact}/${redhat_version}/${dep_artifact}-${redhat_version}.pom"
        
        if curl -s -f -I "$indy_url" > /dev/null 2>&1; then
            echo "${dep_group}:${dep_artifact}:${redhat_version}" >> "$OUTPUT_DIR/build-from-source.txt"
            build_from_source=$((build_from_source + 1))
        else
            echo "${dep_group}:${dep_artifact}:${dep_version}" >> "$OUTPUT_DIR/pending-productized.txt"
            pending_productized=$((pending_productized + 1))
        fi
    done < "$OUTPUT_DIR/filtered-dependencies.txt"
    
    echo "Productization analysis complete:"
    echo "  - Build-from-source: $build_from_source"
    echo "  - Pending productized: $pending_productized"
    echo ""
fi

# Step 6: Generate summary report
echo "Step 6: Generating summary report..."

echo "Step 5: Generating summary report..."

# Calculate percentages safely
pnc_pct=0
pom_pct=0
fail_pct=0

if [[ $processed -gt 0 ]]; then
    pnc_pct=$((pnc_hits * 100 / processed))
    pom_pct=$((pom_hits * 100 / processed))
    fail_pct=$((failures * 100 / processed))
fi

# Calculate no-SCM percentage
no_scm_pct=0
if [[ $processed -gt 0 ]]; then
    no_scm_pct=$((no_scm_count * 100 / processed))
fi

cat > "$OUTPUT_DIR/SUMMARY.md" <<EOF
# Build Configuration Summary

**Root Artifact:** $ROOT_ARTIFACT:$ROOT_VERSION  
**Generated:** $(date)  
**Output Directory:** $OUTPUT_DIR

## Statistics

- **Total Dependencies Processed:** $processed
- **Configs from PNC:** $pnc_hits (${pnc_pct}%)
- **Configs from POM:** $pom_hits (${pom_pct}%)
- **Skipped (No SCM):** $no_scm_count (${no_scm_pct}%)
- **Failures:** $failures (${fail_pct}%)
EOF

# Add productization statistics if Red Hat artifact
if [[ "$ROOT_VERSION" =~ redhat ]]; then
    cat >> "$OUTPUT_DIR/SUMMARY.md" <<EOF

## Productization Status

- **Build-from-source:** $build_from_source (already productized with .redhat suffix)
- **Pending productized:** $pending_productized (need productization)

## PNC Integration

This build configuration was generated using PNC-first approach:
1. Query PNC API for existing build configs
2. Reuse SCM URLs, build scripts, and environment settings from PNC
3. Fall back to POM analysis only when PNC data unavailable

## Generated Files

- **Build Configs:** $OUTPUT_DIR/build-configs/ ($build_count files)
- **Pig Config:** $OUTPUT_DIR/pig-config.yaml
- **PNC Cache:** $OUTPUT_DIR/pnc-cache/ (for debugging)
- **Dependencies:** $OUTPUT_DIR/filtered-dependencies.txt
- **No SCM Builds:** $OUTPUT_DIR/no-scm-builds.txt

## Builds Without SCM Information
EOF
fi  # Close the first productization statistics if block

if [[ -s "$OUTPUT_DIR/no-scm-builds.txt" ]]; then
    cat >> "$OUTPUT_DIR/SUMMARY.md" <<EOF

The following builds were skipped because no SCM URL could be found:

\`\`\`
$(cat "$OUTPUT_DIR/no-scm-builds.txt")
\`\`\`

**Action Required:** These dependencies need manual SCM discovery or may need to be built from Maven Central artifacts.
EOF
else
    cat >> "$OUTPUT_DIR/SUMMARY.md" <<EOF

✅ All dependencies have SCM information available.
EOF
fi

# Add productization details if Red Hat artifact
if [[ "$ROOT_VERSION" =~ redhat ]]; then
    cat >> "$OUTPUT_DIR/SUMMARY.md" <<EOF

## Build-from-Source Dependencies

These dependencies already have .redhat versions in Indy (productized):

\`\`\`
$(cat "$OUTPUT_DIR/build-from-source.txt" 2>/dev/null || echo "(none)")
\`\`\`

## Pending Productized Dependencies

These dependencies need productization (no .redhat version found in Indy):

\`\`\`
$(cat "$OUTPUT_DIR/pending-productized.txt" 2>/dev/null || echo "(none)")
\`\`\`

**Action Required:** Pending dependencies need to be built and productized with .redhat suffix.
EOF
fi  # Close the productization details if block

cat >> "$OUTPUT_DIR/SUMMARY.md" <<EOF

## Next Steps

1. Review generated build configs in \`build-configs/\` directory
2. Verify SCM URLs and revisions
3. Adjust environment IDs if needed
4. For builds without SCM: manually locate source repositories
5. Upload pig-config.yaml to PNC
6. Trigger builds in dependency order

## Notes

- PNC API Base: $PNC_API_BASE
- Build Script Template: \`mvn -Dmaven.test.skip=true -Dartifactory.staging.skip=true -DskipNexusStagingDeployMojo=true clean deploy\`
- Environment Mapping:
  - Java 8: ID 660
  - Java 11: ID 1200
  - Java 17: ID 316
- Builds without SCM are excluded from pig-config.yaml

## Dependency List

\`\`\`
$(cat "$OUTPUT_DIR/filtered-dependencies.txt")
\`\`\`
EOF

echo "Created SUMMARY.md"
echo ""

# Final summary
echo "=== Generation Complete ==="
echo "Processed: $processed dependencies"
echo "  - From PNC: $pnc_hits (${pnc_pct}%)"
echo "  - From POM: $pom_hits (${pom_pct}%)"
echo "  - Failed: $failures (${fail_pct}%)"
echo ""
echo "Output: $OUTPUT_DIR"
echo "  - Build configs: $OUTPUT_DIR/build-configs/"
echo "  - Pig config: $OUTPUT_DIR/pig-config.yaml"
echo "  - Summary: $OUTPUT_DIR/SUMMARY.md"