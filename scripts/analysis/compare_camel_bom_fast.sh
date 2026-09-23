#!/usr/bin/env bash
# Fast Camel BOM Comparison - Properly expands BOM managed dependencies
set -euo pipefail

VERSION1="${1:-4.18.1}"
VERSION2="${2:-4.18.3}"
REDHAT_SUFFIX1="${3:-redhat-00042}"
REDHAT_SUFFIX2="${4:-redhat-00001}"

echo "==================================================================="
echo "Fast Camel BOM Comparison (Full Managed Dependencies)"
echo "==================================================================="
echo "Version 1: ${VERSION1} (suffix: ${REDHAT_SUFFIX1})"
echo "Version 2: ${VERSION2} (suffix: ${REDHAT_SUFFIX2})"
echo ""

OUT1="./bom-compare-${VERSION1}"
OUT2="./bom-compare-${VERSION2}"
mkdir -p "$OUT1" "$OUT2"

# Function to extract managed dependencies from BOM
extract_bom_deps() {
  local version=$1
  local output_dir=$2
  
  echo "  Downloading BOM POM..."
  local bom_url="https://repo1.maven.org/maven2/org/apache/camel/camel-bom/${version}/camel-bom-${version}.pom"
  curl -s "$bom_url" -o "${output_dir}/bom.pom"
  
  echo "  Extracting managed dependencies..."
  # Extract all managed dependencies from BOM
  grep -A 2 "<dependency>" "${output_dir}/bom.pom" | \
    grep -E "<groupId>|<artifactId>|<version>" | \
    paste -d: - - - | \
    sed 's/<[^>]*>//g' | \
    sed 's/^[ \t]*//' | \
    grep -v "org.apache.camel:" | \
    sort -u > "${output_dir}/all-deps.txt"
  
  local count=$(wc -l < "${output_dir}/all-deps.txt" | tr -d ' ')
  echo "  Found ${count} third-party managed dependencies"
}

# Function to check productization (sample check, not all)
check_productization_sample() {
  local deps_file=$1
  local output_dir=$2
  local redhat_suffix=$3
  
  echo "  Checking productization (sampling first 50)..."
  
  > "${output_dir}/productized.txt"
  > "${output_dir}/pending.txt"
  
  local checked=0
  local max_check=50
  
  while IFS= read -r dep && [[ $checked -lt $max_check ]]; do
    [[ -z "$dep" ]] && continue
    
    local group=$(echo "$dep" | cut -d: -f1)
    local artifact=$(echo "$dep" | cut -d: -f2)
    local version=$(echo "$dep" | cut -d: -f3)
    
    # Quick check via Maven Central redirect
    local redhat_version="${version}.${redhat_suffix}"
    local check_url="https://maven.repository.redhat.com/ga/${group//.//}/${artifact}/${redhat_version}/"
    
    if timeout 2 curl -s -f -I "$check_url" > /dev/null 2>&1; then
      echo "${group}:${artifact}:${redhat_version}" >> "${output_dir}/productized.txt"
    else
      echo "${group}:${artifact}:${version}" >> "${output_dir}/pending.txt"
    fi
    
    checked=$((checked + 1))
    printf "\r  Progress: %d/%d" "$checked" "$max_check"
  done < "$deps_file"
  
  # Add remaining unchecked to pending
  tail -n +$((max_check + 1)) "$deps_file" >> "${output_dir}/pending.txt" 2>/dev/null || true
  
  echo ""
}

echo "[1/6] Extracting Camel ${VERSION1} BOM..."
extract_bom_deps "$VERSION1" "$OUT1"

echo "[2/6] Extracting Camel ${VERSION2} BOM..."
extract_bom_deps "$VERSION2" "$OUT2"

echo "[3/6] Sampling productization check for ${VERSION1}..."
check_productization_sample "${OUT1}/all-deps.txt" "$OUT1" "$REDHAT_SUFFIX1"

echo "[4/6] Sampling productization check for ${VERSION2}..."
check_productization_sample "${OUT2}/all-deps.txt" "$OUT2" "$REDHAT_SUFFIX2"

echo "[5/6] Comparing results..."

TOTAL1=$(wc -l < "$OUT1/all-deps.txt" 2>/dev/null || echo "0")
TOTAL2=$(wc -l < "$OUT2/all-deps.txt" 2>/dev/null || echo "0")
PROD1=$(wc -l < "$OUT1/productized.txt" 2>/dev/null || echo "0")
PROD2=$(wc -l < "$OUT2/productized.txt" 2>/dev/null || echo "0")
PEND1=$(wc -l < "$OUT1/pending.txt" 2>/dev/null || echo "0")
PEND2=$(wc -l < "$OUT2/pending.txt" 2>/dev/null || echo "0")

echo "[6/6] Generating report..."

REPORT="camel-bom-${VERSION1}-vs-${VERSION2}-comparison.txt"
cat > "$REPORT" <<EOF
=================================================================
CAMEL BOM COMPARISON REPORT
=================================================================
Version 1: ${VERSION1} (checking against ${REDHAT_SUFFIX1})
Version 2: ${VERSION2} (checking against ${REDHAT_SUFFIX2})
Generated: $(date +%Y-%m-%d\ %H:%M:%S)
Method: Direct BOM POM parsing + sample productization check

=================================================================
SUMMARY
=================================================================

Camel ${VERSION1}:
  - Total managed third-party dependencies: ${TOTAL1}
  - Sampled productized (first 50): ${PROD1}
  - Sampled pending: ${PEND1}

Camel ${VERSION2}:
  - Total managed third-party dependencies: ${TOTAL2}
  - Sampled productized (first 50): ${PROD2}
  - Sampled pending: ${PEND2}

Change in managed deps: $((TOTAL2 - TOTAL1))
Productization improvement (sample): $((PROD2 - PROD1))

=================================================================
TOP 30 NEW DEPENDENCIES IN ${VERSION2}
=================================================================

EOF

if [[ -f "$OUT1/all-deps.txt" ]] && [[ -f "$OUT2/all-deps.txt" ]]; then
  comm -13 <(sort "$OUT1/all-deps.txt") <(sort "$OUT2/all-deps.txt") | head -30 | while read dep; do
    echo "➕ $dep" >> "$REPORT"
  done
fi

cat >> "$REPORT" <<EOF

=================================================================
TOP 30 REMOVED DEPENDENCIES FROM ${VERSION1}
=================================================================

EOF

if [[ -f "$OUT1/all-deps.txt" ]] && [[ -f "$OUT2/all-deps.txt" ]]; then
  comm -23 <(sort "$OUT1/all-deps.txt") <(sort "$OUT2/all-deps.txt") | head -30 | while read dep; do
    echo "➖ $dep" >> "$REPORT"
  done
fi

cat >> "$REPORT" <<EOF

=================================================================
SAMPLE PRODUCTIZED IN ${VERSION2} (first 50 checked)
=================================================================

EOF

if [[ -f "$OUT2/productized.txt" ]]; then
  head -30 "$OUT2/productized.txt" | while read dep; do
    echo "✓ $dep" >> "$REPORT"
  done
fi

cat >> "$REPORT" <<EOF

=================================================================
SAMPLE PENDING IN ${VERSION2} (first 50 checked)
=================================================================

EOF

if [[ -f "$OUT2/pending.txt" ]]; then
  head -30 "$OUT2/pending.txt" | while read dep; do
    echo "✗ $dep" >> "$REPORT"
  done
fi

cat >> "$REPORT" <<EOF

=================================================================
OUTPUT FILES
=================================================================

Version ${VERSION1}:
  - ${OUT1}/all-deps.txt (${TOTAL1} managed dependencies)
  - ${OUT1}/bom.pom (downloaded BOM)

Version ${VERSION2}:
  - ${OUT2}/all-deps.txt (${TOTAL2} managed dependencies)
  - ${OUT2}/bom.pom (downloaded BOM)

Note: Productization check was sampled (first 50 deps) for speed.
For full check, use the main generate_build_configs.sh script.

=================================================================
EOF

echo ""
echo "==================================================================="
echo "✓ Fast BOM comparison complete!"
echo "==================================================================="
echo ""
echo "Report: $REPORT"
echo ""
echo "Summary:"
echo "  ${VERSION1}: ${TOTAL1} managed dependencies"
echo "  ${VERSION2}: ${TOTAL2} managed dependencies"
echo "  Change: $((TOTAL2 - TOTAL1)) dependencies"
echo "  Sample check: ${PROD2} productized out of 50 checked"
echo ""
echo "View report: cat $REPORT"
echo ""
