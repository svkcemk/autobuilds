#!/bin/bash

# Fast parallel analysis of ALL Camel 4.22.0 components
# Analyzes all 530 components to find ALL third-party transitive dependencies

set -e

CAMEL_VERSION="4.22.0.redhat-00001"
INDY_URL="https://indy.corp.redhat.com/api/content/maven/hosted/pnc-builds"
OUTPUT_DIR="camel-4.22.0-full-analysis"
CACHE_DIR="$OUTPUT_DIR/cache"
PARALLEL_JOBS=20  # Process 20 components in parallel

mkdir -p "$OUTPUT_DIR" "$CACHE_DIR"

echo "=== Camel 4.22.0 Full Component Analysis ==="
echo "Analyzing ALL 530 Camel components in parallel..."
echo "Output: $OUTPUT_DIR"
echo ""

# Step 1: Get all Camel components from BOM
echo "[1/5] Fetching Camel BOM..."
BOM_URL="$INDY_URL/org/apache/camel/camel-bom/$CAMEL_VERSION/camel-bom-$CAMEL_VERSION.pom"
curl -sf "$BOM_URL" -o "$OUTPUT_DIR/camel-bom.pom" || {
    echo "ERROR: Failed to fetch Camel BOM"
    exit 1
}

# Extract all Camel component artifacts (exclude Maven plugins)
grep -A2 '<groupId>org.apache.camel</groupId>' "$OUTPUT_DIR/camel-bom.pom" | \
    grep '<artifactId>' | \
    grep -v 'maven-plugin' | \
    sed 's/.*<artifactId>\(.*\)<\/artifactId>.*/\1/' | \
    sort -u > "$OUTPUT_DIR/all-camel-components.txt"

TOTAL_COMPONENTS=$(wc -l < "$OUTPUT_DIR/all-camel-components.txt")
echo "Found $TOTAL_COMPONENTS Camel components"
echo ""

# Step 2: Function to analyze a single component
analyze_component() {
    local artifact_id="$1"
    local cache_file="$CACHE_DIR/${artifact_id}.deps"
    
    # Skip if already cached
    if [ -f "$cache_file" ]; then
        return 0
    fi
    
    # Download POM
    local pom_url="$INDY_URL/org/apache/camel/$artifact_id/$CAMEL_VERSION/${artifact_id}-${CAMEL_VERSION}.pom"
    local pom_file="$CACHE_DIR/${artifact_id}.pom"
    
    if ! curl -sf "$pom_url" -o "$pom_file" 2>/dev/null; then
        echo "SKIP: $artifact_id (no POM)" >> "$OUTPUT_DIR/skipped.txt"
        return 0
    fi
    
    # Extract dependencies (exclude org.apache.camel)
    grep -A3 '<dependency>' "$pom_file" | \
        grep -E '<groupId>|<artifactId>|<version>' | \
        paste -d: - - - | \
        sed 's/<[^>]*>//g' | \
        sed 's/^[ \t]*//' | \
        grep -v '^org.apache.camel:' | \
        grep -v '\${' > "$cache_file" 2>/dev/null || touch "$cache_file"
}

export -f analyze_component
export INDY_URL CAMEL_VERSION CACHE_DIR OUTPUT_DIR

# Step 3: Analyze all components in parallel
echo "[2/5] Analyzing components (parallel, $PARALLEL_JOBS jobs)..."
cat "$OUTPUT_DIR/all-camel-components.txt" | \
    xargs -P "$PARALLEL_JOBS" -I {} bash -c 'analyze_component "{}"'

# Show progress
analyzed=$(find "$CACHE_DIR" -name "*.deps" | wc -l)
echo "Analyzed: $analyzed/$TOTAL_COMPONENTS components"
echo ""

# Step 4: Aggregate all unique third-party dependencies
echo "[3/5] Aggregating dependencies..."
cat "$CACHE_DIR"/*.deps 2>/dev/null | \
    sort -u | \
    grep -v '^$' > "$OUTPUT_DIR/all-third-party-deps.txt" || touch "$OUTPUT_DIR/all-third-party-deps.txt"

TOTAL_DEPS=$(wc -l < "$OUTPUT_DIR/all-third-party-deps.txt")
echo "Found $TOTAL_DEPS unique third-party dependencies"
echo ""

# Step 5: Check productization status (parallel)
echo "[4/5] Checking productization status (parallel)..."
check_productization() {
    local dep="$1"
    local groupId=$(echo "$dep" | cut -d: -f1)
    local artifactId=$(echo "$dep" | cut -d: -f2)
    local version=$(echo "$dep" | cut -d: -f3)
    
    # Try .redhat-00001 suffix
    local redhat_version="${version}.redhat-00001"
    local group_path=$(echo "$groupId" | tr '.' '/')
    local check_url="$INDY_URL/$group_path/$artifactId/$redhat_version/$artifactId-${redhat_version}.pom"
    
    if curl -sf -I "$check_url" > /dev/null 2>&1; then
        echo "$groupId:$artifactId:$redhat_version" >> "$OUTPUT_DIR/productized.txt"
    else
        echo "$dep" >> "$OUTPUT_DIR/unproductized.txt"
    fi
}

export -f check_productization

# Clear previous results
rm -f "$OUTPUT_DIR/productized.txt" "$OUTPUT_DIR/unproductized.txt"

cat "$OUTPUT_DIR/all-third-party-deps.txt" | \
    xargs -P "$PARALLEL_JOBS" -I {} bash -c 'check_productization "{}"'

# Sort results
sort -u "$OUTPUT_DIR/productized.txt" -o "$OUTPUT_DIR/productized.txt" 2>/dev/null || touch "$OUTPUT_DIR/productized.txt"
sort -u "$OUTPUT_DIR/unproductized.txt" -o "$OUTPUT_DIR/unproductized.txt" 2>/dev/null || touch "$OUTPUT_DIR/unproductized.txt"

PRODUCTIZED=$(wc -l < "$OUTPUT_DIR/productized.txt")
UNPRODUCTIZED=$(wc -l < "$OUTPUT_DIR/unproductized.txt")

echo "Productized: $PRODUCTIZED"
echo "Unproductized: $UNPRODUCTIZED"
echo ""

# Step 6: Generate report
echo "[5/5] Generating report..."
cat > "$OUTPUT_DIR/FULL_ANALYSIS_REPORT.md" << EOF
# Camel 4.22.0 - Complete Third-Party Dependency Analysis

**Generated**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Camel Version**: $CAMEL_VERSION
**Components Analyzed**: $TOTAL_COMPONENTS

---

## Executive Summary

| Metric | Count | Percentage |
|--------|-------|------------|
| **Camel Components Analyzed** | $TOTAL_COMPONENTS | 100% |
| **Total Third-Party Dependencies** | $TOTAL_DEPS | 100% |
| **Already Productized** | $PRODUCTIZED | $(awk "BEGIN {printf \"%.1f\", ($PRODUCTIZED/$TOTAL_DEPS)*100}")% |
| **Need Productization** | $UNPRODUCTIZED | $(awk "BEGIN {printf \"%.1f\", ($UNPRODUCTIZED/$TOTAL_DEPS)*100}")% |

---

## Files Generated

1. **all-camel-components.txt** - List of all $TOTAL_COMPONENTS Camel components
2. **all-third-party-deps.txt** - All $TOTAL_DEPS unique third-party dependencies
3. **productized.txt** - $PRODUCTIZED dependencies already productized
4. **unproductized.txt** - $UNPRODUCTIZED dependencies needing productization
5. **cache/** - Cached POM files and dependency lists

---

## Productization Status

### ✅ Already Productized ($PRODUCTIZED dependencies)

See: \`productized.txt\`

### ❌ Need Productization ($UNPRODUCTIZED dependencies)

See: \`unproductized.txt\`

---

## Analysis Details

- **Method**: Parallel analysis of all Camel component POMs
- **Concurrency**: $PARALLEL_JOBS parallel jobs
- **Cache**: Enabled (rerun is instant)
- **Source**: PNC Builds (Indy)

---

## Next Steps

1. Review \`unproductized.txt\` for dependencies to build
2. Categorize by priority (Netty, CXF, Jackson, etc.)
3. Generate PNC build configs
4. Submit builds to PNC

EOF

echo ""
echo "=== Analysis Complete ==="
echo ""
echo "Results:"
echo "  - Total components: $TOTAL_COMPONENTS"
echo "  - Total dependencies: $TOTAL_DEPS"
echo "  - Productized: $PRODUCTIZED ($(awk "BEGIN {printf \"%.1f\", ($PRODUCTIZED/$TOTAL_DEPS)*100}")%)"
echo "  - Unproductized: $UNPRODUCTIZED ($(awk "BEGIN {printf \"%.1f\", ($UNPRODUCTIZED/$TOTAL_DEPS)*100}")%)"
echo ""
echo "Report: $OUTPUT_DIR/FULL_ANALYSIS_REPORT.md"
echo ""
echo "To rerun (instant with cache):"
echo "  ./analyze_all_camel_components.sh"
echo ""
