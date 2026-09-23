#!/usr/bin/env bash
# Fast Camel Version Comparison Script
# Generates dependency comparison report without creating build configs

set -euo pipefail

VERSION1="${1:-4.18.1}"
VERSION2="${2:-4.18.3}"
REDHAT_SUFFIX1="${3:-redhat-00042}"
REDHAT_SUFFIX2="${4:-redhat-00001}"

echo "==================================================================="
echo "Fast Camel Version Comparison"
echo "==================================================================="
echo "Version 1: ${VERSION1} (suffix: ${REDHAT_SUFFIX1})"
echo "Version 2: ${VERSION2} (suffix: ${REDHAT_SUFFIX2})"
echo ""

# Create output directories
OUT1="./compare-output-${VERSION1}"
OUT2="./compare-output-${VERSION2}"
mkdir -p "$OUT1" "$OUT2"

echo "[1/4] Analyzing Camel ${VERSION1} BOM dependencies..."
./generate_build_configs.sh \
  -b "org.apache.camel:camel-bom:${VERSION1}" \
  --expand-bom \
  --check-productization \
  --redhat-suffix "${REDHAT_SUFFIX1}" \
  -e org.apache.camel \
  --format combined \
  --no-build-script-reuse \
  --no-topological-sort \
  -o "$OUT1" 2>&1 | grep -E "\[INFO\]|\[WARN\]|\[ERROR\]" || true

echo ""
echo "[2/4] Analyzing Camel ${VERSION2} BOM dependencies..."
./generate_build_configs.sh \
  -b "org.apache.camel:camel-bom:${VERSION2}" \
  --expand-bom \
  --check-productization \
  --redhat-suffix "${REDHAT_SUFFIX2}" \
  -e org.apache.camel \
  --format combined \
  --no-build-script-reuse \
  --no-topological-sort \
  -o "$OUT2" 2>&1 | grep -E "\[INFO\]|\[WARN\]|\[ERROR\]" || true

echo ""
echo "[3/4] Comparing dependency lists..."

# Count dependencies
TOTAL1=$(wc -l < "$OUT1/third-party-dependencies.txt" 2>/dev/null || echo "0")
TOTAL2=$(wc -l < "$OUT2/third-party-dependencies.txt" 2>/dev/null || echo "0")
PROD1=$(wc -l < "$OUT1/build-from-source.txt" 2>/dev/null || echo "0")
PROD2=$(wc -l < "$OUT2/build-from-source.txt" 2>/dev/null || echo "0")
PEND1=$(wc -l < "$OUT1/pending-productized.txt" 2>/dev/null || echo "0")
PEND2=$(wc -l < "$OUT2/pending-productized.txt" 2>/dev/null || echo "0")

echo ""
echo "[4/4] Generating comparison report..."

# Generate report
REPORT="camel-${VERSION1}-vs-${VERSION2}-comparison.txt"
cat > "$REPORT" <<EOF
=================================================================
CAMEL BOM COMPARISON REPORT
=================================================================
Version 1: ${VERSION1} (checking against ${REDHAT_SUFFIX1})
Version 2: ${VERSION2} (checking against ${REDHAT_SUFFIX2})
Generated: $(date +%Y-%m-%d)
Scope: Full Camel BOM (all components and third-party dependencies)

=================================================================
SUMMARY
=================================================================

Camel ${VERSION1}:
  - Total third-party dependencies: ${TOTAL1}
  - Already productized: ${PROD1}
  - Need to be built: ${PEND1}

Camel ${VERSION2}:
  - Total third-party dependencies: ${TOTAL2}
  - Already productized: ${PROD2}
  - Need to be built: ${PEND2}

Progress: $((PROD2 * 100 / TOTAL2))% productized in ${VERSION2}
Change: $((PROD2 - PROD1)) more dependencies productized

=================================================================
DEPENDENCIES THAT BECAME PRODUCTIZED
=================================================================

EOF

# Find newly productized dependencies
if [[ -f "$OUT1/pending-productized.txt" ]] && [[ -f "$OUT2/build-from-source.txt" ]]; then
  comm -12 <(sort "$OUT1/pending-productized.txt") <(sort "$OUT2/build-from-source.txt") | while read dep; do
    echo "✓ $dep" >> "$REPORT"
  done
fi

cat >> "$REPORT" <<EOF

=================================================================
NEW DEPENDENCIES IN ${VERSION2}
=================================================================

EOF

# Find new dependencies
if [[ -f "$OUT1/third-party-dependencies.txt" ]] && [[ -f "$OUT2/third-party-dependencies.txt" ]]; then
  comm -13 <(sort "$OUT1/third-party-dependencies.txt") <(sort "$OUT2/third-party-dependencies.txt") | head -20 | while read dep; do
    echo "➕ $dep" >> "$REPORT"
  done
fi

cat >> "$REPORT" <<EOF

=================================================================
REMOVED DEPENDENCIES FROM ${VERSION1}
=================================================================

EOF

# Find removed dependencies
if [[ -f "$OUT1/third-party-dependencies.txt" ]] && [[ -f "$OUT2/third-party-dependencies.txt" ]]; then
  comm -23 <(sort "$OUT1/third-party-dependencies.txt") <(sort "$OUT2/third-party-dependencies.txt") | head -20 | while read dep; do
    echo "➖ $dep" >> "$REPORT"
  done
fi

cat >> "$REPORT" <<EOF

=================================================================
STILL PENDING PRODUCTIZATION IN ${VERSION2}
=================================================================

EOF

# Show pending (first 50)
if [[ -f "$OUT2/pending-productized.txt" ]]; then
  head -50 "$OUT2/pending-productized.txt" | while read dep; do
    echo "✗ $dep" >> "$REPORT"
  done
  
  REMAINING=$((PEND2 - 50))
  if [[ $REMAINING -gt 0 ]]; then
    echo "" >> "$REPORT"
    echo "... and ${REMAINING} more (see ${OUT2}/pending-productized.txt)" >> "$REPORT"
  fi
fi

cat >> "$REPORT" <<EOF

=================================================================
OUTPUT FILES
=================================================================

Version ${VERSION1}:
  - ${OUT1}/third-party-dependencies.txt (${TOTAL1} items)
  - ${OUT1}/pending-productized.txt (${PEND1} items)
  - ${OUT1}/build-from-source.txt (${PROD1} items)

Version ${VERSION2}:
  - ${OUT2}/third-party-dependencies.txt (${TOTAL2} items)
  - ${OUT2}/pending-productized.txt (${PEND2} items)
  - ${OUT2}/build-from-source.txt (${PROD2} items)

=================================================================
EOF

echo ""
echo "==================================================================="
echo "✓ Comparison complete!"
echo "==================================================================="
echo ""
echo "Report saved to: $REPORT"
echo ""
echo "Summary:"
echo "  Version ${VERSION1}: ${TOTAL1} deps (${PROD1} productized, ${PEND1} pending)"
echo "  Version ${VERSION2}: ${TOTAL2} deps (${PROD2} productized, ${PEND2} pending)"
echo "  Progress: $((PROD2 - PROD1)) more dependencies productized"
echo ""
echo "View full report: cat $REPORT"
echo ""
