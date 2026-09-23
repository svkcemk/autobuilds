#!/usr/bin/env bash
# Generate PNC-compatible build configs for Camel 4.22 (PARALLEL VERSION)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_FILE="${1:-camel-4.22.0-redhat-00002-report/unproductized-deps.txt}"
OUTPUT_DIR="${2:-output-camel-4.22-pnc-configs}"
PARALLEL_JOBS="${3:-20}"  # Number of parallel jobs (default: 20)

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "============================================================"
echo "PNC Build Config Generator for Camel 4.22 (PARALLEL)"
echo "============================================================"
echo

if [[ ! -f "$INPUT_FILE" ]]; then
    echo -e "${RED}Error: Input file not found: $INPUT_FILE${NC}"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/.tmp"

# Count total artifacts
total=$(grep -E "^[^:]+:[^:]+:[^:]+$" "$INPUT_FILE" | wc -l | tr -d ' ')
echo -e "${BLUE}Total artifacts to process: $total${NC}"
echo -e "${BLUE}Parallel jobs: $PARALLEL_JOBS${NC}"
echo

# Function to process a single artifact
process_artifact() {
    local gav="$1"
    local output_dir="$2"
    local script_dir="$3"
    
    # Parse GAV
    local group_id=$(echo "$gav" | cut -d: -f1)
    local artifact_id=$(echo "$gav" | cut -d: -f2)
    local version=$(echo "$gav" | cut -d: -f3)
    
    # Generate PNC-compatible name for file
    local file_name="${group_id//./-}-${artifact_id}-${version}"
    local output_file="$output_dir/${file_name}.yaml"
    local status_file="$output_dir/.tmp/${file_name}.status"
    
    # Generate build config using PNC generator
    if python3 "$script_dir/lib/ai/pnc_config_generator.py" \
        "$group_id" "$artifact_id" "$version" --yaml > "$output_file" 2>/dev/null; then
        
        # Check confidence level
        local confidence=$(grep "Overall confidence:" "$output_file" | grep -oE "[0-9]+%" | tr -d '%' || echo "0")
        
        if [[ -n "$confidence" && "$confidence" -ge 90 ]]; then
            echo "SUCCESS:EXACT:$confidence:$gav" > "$status_file"
        elif [[ -n "$confidence" && "$confidence" -ge 60 ]]; then
            echo "SUCCESS:HIGH:$confidence:$gav" > "$status_file"
        else
            echo "SUCCESS:LOW:$confidence:$gav" > "$status_file"
        fi
    else
        echo "FAILED:0:$gav" > "$status_file"
        rm -f "$output_file"
    fi
}

export -f process_artifact

# Extract all GAVs
gavs=$(grep -E "^[^:]+:[^:]+:[^:]+$" "$INPUT_FILE")

# Process in parallel using xargs
echo "$gavs" | xargs -P "$PARALLEL_JOBS" -I {} bash -c "process_artifact '{}' '$OUTPUT_DIR' '$SCRIPT_DIR'"

# Collect results
echo
echo "============================================================"
echo "Collecting Results..."
echo "============================================================"

success_exact=0
success_high=0
success_low=0
failed=0

for status_file in "$OUTPUT_DIR/.tmp"/*.status; do
    [[ ! -f "$status_file" ]] && continue
    
    status=$(cat "$status_file")
    
    if [[ "$status" =~ ^SUCCESS:EXACT ]]; then
        success_exact=$((success_exact + 1))
    elif [[ "$status" =~ ^SUCCESS:HIGH ]]; then
        success_high=$((success_high + 1))
    elif [[ "$status" =~ ^SUCCESS:LOW ]]; then
        success_low=$((success_low + 1))
    elif [[ "$status" =~ ^FAILED ]]; then
        failed=$((failed + 1))
    fi
done

total_success=$((success_exact + success_high + success_low))

echo
echo "============================================================"
echo "PNC Build Config Generation Complete"
echo "============================================================"
echo -e "Total processed:     $total"
echo -e "Exact matches (≥90%): ${GREEN}$success_exact${NC}"
echo -e "High confidence (≥60%): ${GREEN}$success_high${NC}"
echo -e "Low confidence (<60%): ${YELLOW}$success_low${NC}"
echo -e "Failed:              ${RED}$failed${NC}"
echo
echo -e "Output directory: ${BLUE}$OUTPUT_DIR${NC}"
echo -e "Generated configs:   $(ls -1 "$OUTPUT_DIR"/*.yaml 2>/dev/null | wc -l | tr -d ' ')"
echo "============================================================"

# Cleanup temp directory
rm -rf "$OUTPUT_DIR/.tmp"

# Summary by confidence level
echo
echo "=== Confidence Distribution ==="
if [[ $success_exact -gt 0 ]]; then
    echo -e "${GREEN}✓ $success_exact configs with exact matches (≥90%)${NC} - Ready for immediate use"
fi
if [[ $success_high -gt 0 ]]; then
    echo -e "${GREEN}✓ $success_high configs with high confidence (≥60%)${NC} - Recommended for use"
fi
if [[ $success_low -gt 0 ]]; then
    echo -e "${YELLOW}⚠ $success_low configs with low confidence (<60%)${NC} - Needs manual review"
fi
if [[ $failed -gt 0 ]]; then
    echo -e "${RED}✗ $failed configs failed${NC} - Requires manual creation"
fi

echo
echo "=== Key Improvements ==="
echo "✓ PNC-compatible format with proper field names"
echo "✓ Correct naming convention (groupId-artifactId-version-AUTOBUILD)"
echo "✓ buildType field (MVN/GRADLE)"
echo "✓ Smart environment detection (Java 8/11/17 based on artifact)"
echo "✓ Upstream SCM URLs (no downstream mirrors)"
echo "✓ Project paths extracted from GitHub URLs"
