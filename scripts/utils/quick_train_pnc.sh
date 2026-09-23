#!/bin/bash
# Quick PNC training for Camel 4.22
# Complete workflow in one script

set -e

VERSION="${1:-4.22}"
OUTPUT_DIR="${2:-pnc-training-output}"

echo "==================================================================="
echo "Quick PNC Training for Camel $VERSION"
echo "==================================================================="
echo ""
echo "This script will:"
echo "  1. Harvest Camel $VERSION builds from PNC"
echo "  2. Train AI with harvested data"
echo "  3. Create test set from unproductized dependencies"
echo "  4. Validate AI predictions"
echo ""
echo "Output directory: $OUTPUT_DIR"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Check Python dependencies
echo "Checking dependencies..."
if ! python3 -c "import requests" 2>/dev/null; then
    echo "Installing requests library..."
    pip3 install requests
fi
echo "✓ Dependencies OK"
echo ""

# Step 1: Harvest PNC data
echo "==================================================================="
echo "Step 1: Harvesting PNC data for Camel $VERSION"
echo "==================================================================="
python3 lib/ai/pnc_camel_harvester.py "$VERSION" "$OUTPUT_DIR/harvest.jsonl"

if [[ ! -f "$OUTPUT_DIR/harvest.jsonl" ]]; then
    echo ""
    echo "✗ Error: Harvest failed - no data file created"
    exit 1
fi

# Check if we got any data
HARVEST_COUNT=$(wc -l < "$OUTPUT_DIR/harvest.jsonl" | tr -d ' ')
if [[ "$HARVEST_COUNT" -eq 0 ]]; then
    echo ""
    echo "✗ Error: No builds harvested from PNC"
    exit 1
fi

echo ""
echo "✓ Harvested $HARVEST_COUNT builds"
echo ""

# Step 2: Train AI
echo "==================================================================="
echo "Step 2: Training AI with harvested data"
echo "==================================================================="
python3 lib/ai/quick_train.py "$OUTPUT_DIR/harvest.jsonl"

if [[ $? -ne 0 ]]; then
    echo ""
    echo "✗ Error: Training failed"
    exit 1
fi

echo ""

# Step 3: Create test set
echo "==================================================================="
echo "Step 3: Creating test set"
echo "==================================================================="

# Try to find unproductized deps file
TEST_SET_CREATED=false
UNPRODUCTIZED_FILE=""

# Look for Camel 4.22 unproductized deps
for pattern in \
    "camel-4.22.0-redhat-00002-report/unproductized-deps.txt" \
    "camel-4.22.0-redhat-00002-report/third-party-dependencies.txt" \
    "camel-4.22.0-redhat-00002-full-transitives/unresolved-artifacts.txt" \
    "output-first-batch/unresolved-artifacts.txt"; do
    
    if [[ -f "$pattern" ]]; then
        UNPRODUCTIZED_FILE="$pattern"
        break
    fi
done

if [[ -n "$UNPRODUCTIZED_FILE" ]]; then
    echo "Found unproductized deps: $UNPRODUCTIZED_FILE"
    
    # Extract first 50 artifacts for testing
    grep -v "^#" "$UNPRODUCTIZED_FILE" | \
        head -50 | \
        awk '{print $1}' | \
        grep -E "^[^:]+:[^:]+:[^:]+$" > "$OUTPUT_DIR/test-artifacts.txt" 2>/dev/null || true
    
    if [[ -f "$OUTPUT_DIR/test-artifacts.txt" ]] && [[ -s "$OUTPUT_DIR/test-artifacts.txt" ]]; then
        TEST_COUNT=$(wc -l < "$OUTPUT_DIR/test-artifacts.txt" | tr -d ' ')
        echo "✓ Created test set with $TEST_COUNT artifacts"
        TEST_SET_CREATED=true
    else
        echo "⚠ Warning: Could not create test set from $UNPRODUCTIZED_FILE"
    fi
else
    echo "⚠ Warning: No unproductized deps file found"
    echo "  Looked for:"
    echo "    - camel-4.22.0-redhat-00002-report/unproductized-deps.txt"
    echo "    - camel-4.22.0-redhat-00002-report/third-party-dependencies.txt"
    echo "    - camel-4.22.0-redhat-00002-full-transitives/unresolved-artifacts.txt"
fi

echo ""

# Step 4: Validate
if [[ "$TEST_SET_CREATED" == true ]]; then
    echo "==================================================================="
    echo "Step 4: Validating AI predictions"
    echo "==================================================================="
    python3 lib/ai/quick_validate.py "$OUTPUT_DIR/test-artifacts.txt"
else
    echo "==================================================================="
    echo "Step 4: Validation skipped (no test set)"
    echo "==================================================================="
    echo ""
    echo "To validate manually, create a test file with artifacts:"
    echo "  Format: group:artifact:version (one per line)"
    echo "  Then run: python3 lib/ai/quick_validate.py <test-file>"
fi

echo ""
echo "==================================================================="
echo "Training Complete!"
echo "==================================================================="
echo ""
echo "Output directory: $OUTPUT_DIR"
echo "  - harvest.jsonl: Raw PNC data"
echo "  - harvest-summary.json: Statistics"
if [[ "$TEST_SET_CREATED" == true ]]; then
    echo "  - test-artifacts.txt: Test set"
fi
echo ""
echo "AI data location: ~/.bob/ai/scm_learner/"
echo ""
echo "Next steps:"
echo "  1. Test AI predictions:"
echo "     ./ai_enhance.sh predict org.apache.camel:camel-kafka:4.22.0"
echo ""
echo "  2. Check AI status:"
echo "     ./ai_enhance.sh status"
echo ""
echo "  3. Use in autobuilder:"
echo "     source lib/scm_resolver_ai.sh"
echo "     resolve_scm_with_ai \"org.apache.camel\" \"camel-kafka\" \"4.22.0\""
echo ""
echo "  4. Validate with custom test set:"
echo "     python3 lib/ai/quick_validate.py <your-test-file.txt>"
echo ""
echo "==================================================================="
