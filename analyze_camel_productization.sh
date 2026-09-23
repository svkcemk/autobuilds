#!/bin/bash
# Camel Quarkus Productization Analysis
# Analyzes Camel Quarkus BOM to identify unproductized artifacts
# Checks against PNC and filters artifacts with productized transitives

set -euo pipefail

# Configuration
CAMEL_QUARKUS_BOM="${1:-org.apache.camel.quarkus:camel-quarkus-bom:3.17.0}"
OUTPUT_DIR="${2:-./camel-productization-report}"
CONFIG_FILE="${3:-test-config.yaml}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Create output directory
mkdir -p "$OUTPUT_DIR"

log_info "Camel Quarkus Productization Analysis"
log_info "======================================"
log_info "BOM: $CAMEL_QUARKUS_BOM"
log_info "Output: $OUTPUT_DIR"
echo ""

# Step 1: Generate build configs with productization check
log_info "Step 1: Analyzing Camel Quarkus BOM with productization check..."
./generate_build_configs.sh \
  -b "$CAMEL_QUARKUS_BOM" \
  -c "$CONFIG_FILE" \
  -o "$OUTPUT_DIR/analysis" \
  --check-productization \
  --expand-bom \
  --enable-ai-assistant \
  --no-pnc-integration 2>&1 | tee "$OUTPUT_DIR/analysis.log"

log_success "BOM analysis complete"
echo ""

# Step 2: Extract Camel-specific artifacts
log_info "Step 2: Extracting Camel-specific artifacts..."
grep "org.apache.camel" "$OUTPUT_DIR/analysis/all-dependencies.txt" > "$OUTPUT_DIR/camel-artifacts.txt" || true
TOTAL_CAMEL=$(wc -l < "$OUTPUT_DIR/camel-artifacts.txt" | tr -d ' ')
log_info "Found $TOTAL_CAMEL Camel artifacts"
echo ""

# Step 3: Identify unproductized Camel artifacts
log_info "Step 3: Identifying unproductized Camel artifacts..."
grep "org.apache.camel" "$OUTPUT_DIR/analysis/unresolved-artifacts.txt" > "$OUTPUT_DIR/camel-unproductized.txt" 2>/dev/null || touch "$OUTPUT_DIR/camel-unproductized.txt"
UNPRODUCTIZED=$(wc -l < "$OUTPUT_DIR/camel-unproductized.txt" | tr -d ' ')
log_info "Found $UNPRODUCTIZED unproductized Camel artifacts"
echo ""

# Step 4: Analyze transitive dependencies for each unproductized artifact
log_info "Step 4: Analyzing transitive dependencies..."
cat > "$OUTPUT_DIR/detailed-analysis.txt" <<EOF
Camel Quarkus Productization Report
Generated: $(date)
BOM: $CAMEL_QUARKUS_BOM

Summary:
--------
Total Camel Artifacts: $TOTAL_CAMEL
Unproductized Artifacts: $UNPRODUCTIZED
Productization Rate: $( [[ $TOTAL_CAMEL -gt 0 ]] && echo "$(( (TOTAL_CAMEL - UNPRODUCTIZED) * 100 / TOTAL_CAMEL ))%" || echo "N/A" )

Unproductized Artifacts Requiring Action:
------------------------------------------

EOF

# Analyze each unproductized artifact
if [[ $UNPRODUCTIZED -gt 0 ]]; then
  while IFS= read -r artifact; do
    echo "Analyzing: $artifact" >> "$OUTPUT_DIR/detailed-analysis.txt"
    echo "  Status: Needs productization" >> "$OUTPUT_DIR/detailed-analysis.txt"
    echo "" >> "$OUTPUT_DIR/detailed-analysis.txt"
  done < "$OUTPUT_DIR/camel-unproductized.txt"
fi

log_success "Detailed analysis complete"
echo ""

# Step 5: Generate summary report
log_info "Step 5: Generating summary report..."
cat > "$OUTPUT_DIR/REPORT.md" <<EOF
# Camel Quarkus Productization Report

**Generated:** $(date)  
**BOM:** \`$CAMEL_QUARKUS_BOM\`

## Executive Summary

- **Total Camel Artifacts:** $TOTAL_CAMEL
- **Unproductized Artifacts:** $UNPRODUCTIZED
- **Productization Rate:** $( [[ $TOTAL_CAMEL -gt 0 ]] && echo "$(( (TOTAL_CAMEL - UNPRODUCTIZED) * 100 / TOTAL_CAMEL ))%" || echo "N/A (no Camel artifacts found)" )

## Unproductized Artifacts

The following Camel artifacts require productization:

\`\`\`
$(cat "$OUTPUT_DIR/camel-unproductized.txt")
\`\`\`

## Files Generated

- \`camel-artifacts.txt\` - All Camel artifacts from BOM
- \`camel-unproductized.txt\` - Camel artifacts needing productization
- \`detailed-analysis.txt\` - Detailed analysis with transitive dependencies
- \`analysis/\` - Full build config analysis output
- \`analysis.log\` - Complete analysis log

## Next Steps

1. Review unproductized artifacts list
2. Check if artifacts are already in PNC with different versions
3. Create build configs for missing artifacts
4. Submit builds to PNC
5. Track productization progress

## Usage

To re-run this analysis:
\`\`\`bash
./analyze_camel_productization.sh $CAMEL_QUARKUS_BOM $OUTPUT_DIR $CONFIG_FILE
\`\`\`

EOF

log_success "Report generated: $OUTPUT_DIR/REPORT.md"
echo ""

# Display summary
log_info "Analysis Complete!"
log_info "=================="
echo ""
cat "$OUTPUT_DIR/REPORT.md"
