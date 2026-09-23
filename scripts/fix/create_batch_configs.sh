#!/usr/bin/env bash
# Create batch build configs (10-20 artifacts per file) for PNC bulk import

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_DIR="${1:-output-camel-4.22-final}"
OUTPUT_DIR="${2:-output-camel-4.22-batches}"
BATCH_SIZE="${3:-15}"  # Default: 15 artifacts per batch
PRODUCT_ID="${4:-163}"  # PNC Product ID for Camel

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "============================================================"
echo "Batch Build Config Generator for PNC"
echo "============================================================"
echo

if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: Input directory not found: $INPUT_DIR"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Count total configs
total_configs=$(ls -1 "$INPUT_DIR"/*.yaml 2>/dev/null | wc -l | tr -d ' ')
total_batches=$(( (total_configs + BATCH_SIZE - 1) / BATCH_SIZE ))

echo -e "${BLUE}Total configs: $total_configs${NC}"
echo -e "${BLUE}Batch size: $BATCH_SIZE${NC}"
echo -e "${BLUE}Total batches: $total_batches${NC}"
echo -e "${BLUE}PNC Product ID: $PRODUCT_ID${NC}"
echo

# Process configs in batches
batch_num=0
config_count=0
current_batch_configs=()

for config_file in "$INPUT_DIR"/*.yaml; do
    [[ ! -f "$config_file" ]] && continue
    
    current_batch_configs+=("$config_file")
    config_count=$((config_count + 1))
    
    # Create batch when size reached or last config
    if [[ ${#current_batch_configs[@]} -eq $BATCH_SIZE ]] || [[ $config_count -eq $total_configs ]]; then
        batch_num=$((batch_num + 1))
        batch_file="$OUTPUT_DIR/camel-4.22-batch-$(printf "%03d" $batch_num).yaml"
        
        echo -e "${BLUE}Creating batch $batch_num/${total_batches}${NC} (${#current_batch_configs[@]} configs)"
        
        # Create batch header
        cat > "$batch_file" <<EOF
# Camel 4.22 Build Configs - Batch $batch_num of $total_batches
# PNC Product: https://orch.pnc.engineering.redhat.com/pnc-web/products/$PRODUCT_ID
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Artifacts in this batch: ${#current_batch_configs[@]}

---
# Batch Configuration
productId: $PRODUCT_ID
productVersion: "4.22.0.redhat-00002"
batchNumber: $batch_num
totalBatches: $total_batches

---
# Build Configurations

EOF
        
        # Append each config with separator
        for cfg in "${current_batch_configs[@]}"; do
            echo "---" >> "$batch_file"
            cat "$cfg" >> "$batch_file"
            echo "" >> "$batch_file"
        done
        
        # Add batch summary
        cat >> "$batch_file" <<EOF
---
# Batch $batch_num Summary
# Total artifacts: ${#current_batch_configs[@]}
# Artifacts:
EOF
        
        for cfg in "${current_batch_configs[@]}"; do
            artifact_name=$(basename "$cfg" .yaml)
            confidence=$(grep "Overall confidence:" "$cfg" | grep -oE "[0-9]+%" || echo "N/A")
            echo "#   - $artifact_name (confidence: $confidence)" >> "$batch_file"
        done
        
        echo -e "  ${GREEN}✓${NC} Created: $(basename "$batch_file")"
        
        # Reset for next batch
        current_batch_configs=()
    fi
done

echo
echo "============================================================"
echo "Batch Creation Complete"
echo "============================================================"
echo -e "Total batches created: ${GREEN}$batch_num${NC}"
echo -e "Output directory: ${BLUE}$OUTPUT_DIR${NC}"
echo
echo "Next steps:"
echo "1. Review batch files: ls -lh $OUTPUT_DIR/"
echo "2. Import to PNC: https://orch.pnc.engineering.redhat.com/pnc-web/products/$PRODUCT_ID"
echo "3. Use PNC bulk import feature for each batch file"
echo "============================================================"
