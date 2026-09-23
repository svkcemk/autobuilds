#!/usr/bin/env bash
# Create PNC batch build configs (15 artifacts per file) for bulk import

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_DIR="${1:-output-camel-4.22-pnc-configs}"
OUTPUT_DIR="${2:-output-camel-4.22-pnc-batches}"
BATCH_SIZE="${3:-15}"  # Default: 15 artifacts per batch
PRODUCT_ID="${4:-163}"  # PNC Product ID for Camel

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "============================================================"
echo "PNC Batch Build Config Generator"
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
        batch_file="$OUTPUT_DIR/camel-4.22-pnc-batch-$(printf "%03d" $batch_num).yaml"
        
        echo -e "${BLUE}Creating batch $batch_num/${total_batches}${NC} (${#current_batch_configs[@]} configs)"
        
        # Create batch header (PNC format)
        cat > "$batch_file" <<EOF
# Camel 4.22 PNC Build Configs - Batch $batch_num of $total_batches
# PNC Product: https://orch.pnc.engineering.redhat.com/pnc-web/products/$PRODUCT_ID
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Format: PNC build configuration YAML
# Artifacts in this batch: ${#current_batch_configs[@]}

product:
  name: "Camel Extensions for Quarkus"
  abbreviation: "CEQ"
  stage: "GA"
  issueTrackerUrl: "https://issues.redhat.com/projects/CEQ"
version: "4.22.0.redhat-00002"
milestone: "DR1"
group: "Camel 4.22 Third-Party Dependencies - Batch $batch_num"
defaultBuildParameters:
  brewPullActive: false

builds:
EOF
        
        # Append each config
        for cfg in "${current_batch_configs[@]}"; do
            # Extract fields from individual config
            name=$(grep '^name:' "$cfg" | cut -d'"' -f2)
            project=$(grep '^project:' "$cfg" | cut -d'"' -f2)
            buildType=$(grep '^buildType:' "$cfg" | cut -d'"' -f2)
            scmUrl=$(grep '^scmUrl:' "$cfg" | cut -d'"' -f2)
            scmRevision=$(grep '^scmRevision:' "$cfg" | cut -d'"' -f2)
            environmentName=$(grep '^environmentName:' "$cfg" | cut -d'"' -f2)
            description=$(grep '^description:' "$cfg" | cut -d'"' -f2)
            
            # Extract build script (multiline)
            buildScript=$(awk '/^buildScript: \|/{flag=1; next} /^[a-zA-Z]/{flag=0} flag{print}' "$cfg" | sed 's/^  //')
            
            # Add to batch file in PNC format
            cat >> "$batch_file" <<BUILDEOF
- name: "$name"
  project: "$project"
  buildType: "$buildType"
  scmUrl: "$scmUrl"
  scmRevision: "$scmRevision"
  environmentName: "$environmentName"
  buildScript: |
$(echo "$buildScript" | sed 's/^/    /')
  description: "$description"

BUILDEOF
        done
        
        echo -e "  ${GREEN}✓${NC} Created: $(basename "$batch_file")"
        
        # Reset for next batch
        current_batch_configs=()
    fi
done

echo
echo "============================================================"
echo "PNC Batch Creation Complete"
echo "============================================================"
echo -e "Total batches created: ${GREEN}$batch_num${NC}"
echo -e "Output directory: ${BLUE}$OUTPUT_DIR${NC}"
echo
echo "Next steps:"
echo "1. Review batch files: ls -lh $OUTPUT_DIR/"
echo "2. Import to PNC: https://orch.pnc.engineering.redhat.com/pnc-web/products/$PRODUCT_ID"
echo "3. Use PNC bulk import feature for each batch file"
echo "============================================================"
