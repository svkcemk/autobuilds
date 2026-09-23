#!/usr/bin/env bash
# Generate AI-powered build configs for Camel 4.22 unproductized dependencies

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_FILE="${1:-camel-4.22.0-redhat-00002-report/unproductized-deps.txt}"
OUTPUT_DIR="${2:-output-camel-4.22-build-configs}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "============================================================"
echo "AI-Powered Build Config Generator for Camel 4.22"
echo "============================================================"
echo

if [[ ! -f "$INPUT_FILE" ]]; then
    echo -e "${RED}Error: Input file not found: $INPUT_FILE${NC}"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Count total artifacts
total=$(grep -E "^[^:]+:[^:]+:[^:]+$" "$INPUT_FILE" | wc -l | tr -d ' ')
echo -e "${BLUE}Total artifacts to process: $total${NC}"
echo

# Process each artifact
count=0
success=0
failed=0
low_confidence=0

while IFS= read -r gav; do
    # Skip empty lines and comments
    [[ -z "$gav" || "$gav" =~ ^# ]] && continue
    
    # Parse GAV
    group_id=$(echo "$gav" | cut -d: -f1)
    artifact_id=$(echo "$gav" | cut -d: -f2)
    version=$(echo "$gav" | cut -d: -f3)
    
    count=$((count + 1))
    
    echo -e "${BLUE}[$count/$total]${NC} Processing: $gav"
    
    # Generate build config using unified predictor
    output_file="$OUTPUT_DIR/${artifact_id}-${version}.yaml"
    
    if python3 "$SCRIPT_DIR/lib/ai/unified_predictor.py" \
        "$group_id" "$artifact_id" "$version" --yaml > "$output_file" 2>/dev/null; then
        
        # Check confidence level (UPDATED thresholds for improved scoring)
        confidence=$(grep "Overall confidence:" "$output_file" | grep -oE "[0-9]+%" | tr -d '%')
        
        if [[ -n "$confidence" && "$confidence" -ge 90 ]]; then
            echo -e "  ${GREEN}✓${NC} Generated with ${confidence}% confidence (exact match)"
            success=$((success + 1))
        elif [[ -n "$confidence" && "$confidence" -ge 60 ]]; then
            echo -e "  ${GREEN}✓${NC} Generated with ${confidence}% confidence"
            success=$((success + 1))
        else
            echo -e "  ${YELLOW}⚠${NC} Generated with ${confidence}% confidence (needs review)"
            low_confidence=$((low_confidence + 1))
        fi
    else
        echo -e "  ${RED}✗${NC} Failed to generate"
        failed=$((failed + 1))
        rm -f "$output_file"
    fi
    
    # Progress update every 50 artifacts
    if [[ $((count % 50)) -eq 0 ]]; then
        echo
        echo -e "${BLUE}Progress: $count/$total processed${NC}"
        echo -e "  Success: ${GREEN}$success${NC}, Low confidence: ${YELLOW}$low_confidence${NC}, Failed: ${RED}$failed${NC}"
        echo
    fi
    
done < <(grep -E "^[^:]+:[^:]+:[^:]+$" "$INPUT_FILE")

echo
echo "============================================================"
echo "Build Config Generation Complete"
echo "============================================================"
echo -e "Total processed:     $count"
echo -e "High confidence:     ${GREEN}$success${NC}"
echo -e "Low confidence:      ${YELLOW}$low_confidence${NC}"
echo -e "Failed:              ${RED}$failed${NC}"
echo
echo -e "Output directory: ${BLUE}$OUTPUT_DIR${NC}"
echo -e "Generated configs:   $(ls -1 "$OUTPUT_DIR"/*.yaml 2>/dev/null | wc -l | tr -d ' ')"
echo "============================================================"
