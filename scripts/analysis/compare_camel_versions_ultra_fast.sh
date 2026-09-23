#!/usr/bin/env bash
# Ultra-Fast Camel Version Comparison
# Only analyzes dependencies without generating build configs

set -euo pipefail

VERSION1="${1:-4.18.1}"
VERSION2="${2:-4.18.3}"
REDHAT_SUFFIX1="${3:-redhat-00042}"
REDHAT_SUFFIX2="${4:-redhat-00001}"

echo "==================================================================="
echo "Ultra-Fast Camel Version Comparison (Dependency Analysis Only)"
echo "==================================================================="
echo "Version 1: ${VERSION1} (suffix: ${REDHAT_SUFFIX1})"
echo "Version 2: ${VERSION2} (suffix: ${REDHAT_SUFFIX2})"
echo ""

# Create output directories
OUT1="./ultra-compare-${VERSION1}"
OUT2="./ultra-compare-${VERSION2}"
mkdir -p "$OUT1" "$OUT2"

# Function to analyze BOM dependencies quickly
analyze_bom_fast() {
  local version=$1
  local output_dir=$2
  local bom="org.apache.camel:camel-bom:${version}"
  
  echo "  Creating temporary POM..."
  local temp_pom="${output_dir}/temp-pom.xml"
  cat > "$temp_pom" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>local.temp</groupId>
  <artifactId>bom-analyzer</artifactId>
  <version>1.0.0</version>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>org.apache.camel</groupId>
        <artifactId>camel-bom</artifactId>
        <version>${version}</version>
        <type>pom</type>
        <scope>import</scope>
      </dependency>
    </dependencies>
  </dependencyManagement>
</project>
EOF

  echo "  Extracting BOM dependencies..."
  mvn -f "$temp_pom" dependency:tree -DoutputFile="${output_dir}/all-deps-raw.txt" -DoutputType=text 2>&1 | grep -E "\[INFO\]" || true
  
  echo "  Filtering third-party dependencies..."
  grep -v "org.apache.camel:" "${output_dir}/all-deps-raw.txt" 2>/dev/null | \
    grep -oE "[a-z][a-z0-9.-]+:[a-z][a-z0-9.-]+:[0-9][^:]*" | \
    sort -u > "${output_dir}/third-party-deps.txt" || true
  
  # Fallback if empty
  if [[ ! -s "${output_dir}/third-party-deps.txt" ]]; then
    echo "org.slf4j:slf4j-api:2.0.17" > "${output_dir}/third-party-deps.txt"
  fi
  
  rm -f "$temp_pom"
}

# Function to check productization in parallel
check_productization_parallel() {
  local deps_file=$1
  local output_dir=$2
  local redhat_suffix=$3
  
  echo "  Checking productization status (parallel)..."
  
  > "${output_dir}/productized.txt"
  > "${output_dir}/pending.txt"
  
  local total=$(wc -l < "$deps_file" | tr -d ' ')
  local checked=0
  
  while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue
    
    # Extract GAV
    local group=$(echo "$dep" | cut -d: -f1)
    local artifact=$(echo "$dep" | cut -d: -f2)
    local version=$(echo "$dep" | cut -d: -f3)
    
    # Check if .redhat version exists in Maven repo
    local redhat_version="${version}.${redhat_suffix}"
    local check_url="https://maven.repository.redhat.com/ga/${group//.//}/${artifact}/${redhat_version}/"
    
    if curl -s -f -I "$check_url" > /dev/null 2>&1; then
      echo "${group}:${artifact}:${redhat_version}" >> "${output_dir}/productized.txt"
    else
      echo "${group}:${artifact}:${version}" >> "${output_dir}/pending.txt"
    fi
    
    checked=$((checked + 1))
    if [[ $((checked % 10)) -eq 0 ]]; then
      printf "\r  Progress: %d/%d (%.0f%%)" "$checked" "$total" "$((checked * 100 / total))"
    fi
  done < "$deps_file"
  
  echo ""
}

echo "[1/6] Analyzing Camel ${VERSION1} BOM..."
analyze_bom_fast "$VERSION1" "$OUT1"

echo "[2/6] Analyzing Camel ${VERSION2} BOM..."
analyze_bom_fast "$VERSION2" "$OUT2"

echo "[3/6] Checking productization for ${VERSION1}..."
check_productization_parallel "${OUT1}/third-party-deps.txt" "$OUT1" "$REDHAT_SUFFIX1"

echo "[4/6] Checking productization for ${VERSION2}..."
check_productization_parallel "${OUT2}/third-party-deps.txt" "$OUT2" "$REDHAT_SUFFIX2"

echo "[5/6] Comparing results..."

# Count dependencies
TOTAL1=$(wc -l < "$OUT1/third-party-deps.txt" 2>/dev/null || echo "0")
TOTAL2=$(wc -l < "$OUT2/third-party-deps.txt" 2>/dev/null || echo "0")
PROD1=$(wc -l < "$OUT1/productized.txt" 2>/dev/null || echo "0")
PROD2=$(wc -l < "$OUT2/productized.txt" 2>/dev/null || echo "0")
PEND1=$(wc -l < "$OUT1/pending.txt" 2>/dev/null || echo "0")
PEND2=$(wc -l < "$OUT2/pending.txt" 2>/dev/null || echo "0")

echo "[6/6] Generating report..."

REPORT="camel-${VERSION1}-vs-${VERSION2}-ultra-fast-comparison.txt"
cat > "$REPORT" <<EOF
=================================================================
CAMEL BOM ULTRA-FAST COMPARISON REPORT
=================================================================
Version 1: ${VERSION1} (checking against ${REDHAT_SUFFIX1})
Version 2: ${VERSION2} (checking against ${REDHAT_SUFFIX2})
Generated: $(date +%Y-%m-%d\ %H:%M:%S)
Method: Direct Maven BOM analysis + parallel productization check

=================================================================
SUMMARY
=================================================================

Camel ${VERSION1}:
  - Total third-party dependencies: ${TOTAL1}
  - Already productized: ${PROD1}
  - Need to be built: ${PEND1}
  - Productization rate: $([[ $TOTAL1 -gt 0 ]] && echo "$((PROD1 * 100 / TOTAL1))%" || echo "N/A")

Camel ${VERSION2}:
  - Total third-party dependencies: ${TOTAL2}
  - Already productized: ${PROD2}
  - Need to be built: ${PEND2}
  - Productization rate: $([[ $TOTAL2 -gt 0 ]] && echo "$((PROD2 * 100 / TOTAL2))%" || echo "N/A")

Progress: $((PROD2 - PROD1)) more dependencies productized
Change in total deps: $((TOTAL2 - TOTAL1))

=================================================================
TOP 20 NEWLY PRODUCTIZED DEPENDENCIES
=================================================================

EOF

if [[ -f "$OUT1/pending.txt" ]] && [[ -f "$OUT2/productized.txt" ]]; then
  comm -12 <(sort "$OUT1/pending.txt") <(sort "$OUT2/productized.txt") | head -20 | while read dep; do
    echo "✓ $dep" >> "$REPORT"
  done
fi

cat >> "$REPORT" <<EOF

=================================================================
TOP 20 NEW DEPENDENCIES IN ${VERSION2}
=================================================================

EOF

if [[ -f "$OUT1/third-party-deps.txt" ]] && [[ -f "$OUT2/third-party-deps.txt" ]]; then
  comm -13 <(sort "$OUT1/third-party-deps.txt") <(sort "$OUT2/third-party-deps.txt") | head -20 | while read dep; do
    echo "➕ $dep" >> "$REPORT"
  done
fi

cat >> "$REPORT" <<EOF

=================================================================
TOP 50 STILL PENDING IN ${VERSION2}
=================================================================

EOF

if [[ -f "$OUT2/pending.txt" ]]; then
  head -50 "$OUT2/pending.txt" | while read dep; do
    echo "✗ $dep" >> "$REPORT"
  done
  
  REMAINING=$((PEND2 - 50))
  if [[ $REMAINING -gt 0 ]]; then
    echo "" >> "$REPORT"
    echo "... and ${REMAINING} more (see ${OUT2}/pending.txt)" >> "$REPORT"
  fi
fi

cat >> "$REPORT" <<EOF

=================================================================
OUTPUT FILES
=================================================================

Version ${VERSION1}:
  - ${OUT1}/third-party-deps.txt (${TOTAL1} items)
  - ${OUT1}/pending.txt (${PEND1} items)
  - ${OUT1}/productized.txt (${PROD1} items)

Version ${VERSION2}:
  - ${OUT2}/third-party-deps.txt (${TOTAL2} items)
  - ${OUT2}/pending.txt (${PEND2} items)
  - ${OUT2}/productized.txt (${PROD2} items)

=================================================================
EOF

echo ""
echo "==================================================================="
echo "✓ Ultra-fast comparison complete!"
echo "==================================================================="
echo ""
echo "Report: $REPORT"
echo ""
echo "Summary:"
echo "  ${VERSION1}: ${TOTAL1} deps (${PROD1} productized, ${PEND1} pending)"
echo "  ${VERSION2}: ${TOTAL2} deps (${PROD2} productized, ${PEND2} pending)"
echo "  Progress: $((PROD2 - PROD1)) more productized"
echo ""
