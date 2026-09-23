#!/bin/bash

set -e

# Improved Camel Transitive Dependency Analyzer
# Analyzes ALL third-party dependencies from Camel 4.22.0.redhat-00001

CAMEL_VERSION="4.22.0.redhat-00001"
OUTPUT_DIR="camel-4.22.0-productization-report-v2"
INDY_URL="https://indy.corp.redhat.com/api/content/maven/hosted/pnc-builds"

echo "=========================================="
echo "Camel Productization Analyzer v2"
echo "Version: $CAMEL_VERSION"
echo "=========================================="
echo ""

mkdir -p "$OUTPUT_DIR"

# Step 1: Download Camel BOM from Indy
echo "[1/5] Downloading Camel BOM from Indy..."
BOM_URL="$INDY_URL/org/apache/camel/camel-bom/${CAMEL_VERSION}/camel-bom-${CAMEL_VERSION}.pom"
BOM_FILE="$OUTPUT_DIR/camel-bom.pom"

if curl -f -s -o "$BOM_FILE" "$BOM_URL"; then
    echo "✓ Downloaded productized Camel BOM"
else
    echo "✗ Failed to download from Indy"
    exit 1
fi

# Step 2: Extract ALL managed dependencies from BOM
echo ""
echo "[2/5] Extracting managed dependencies from BOM..."

# Use Maven to get effective POM with all managed dependencies
cat > "$OUTPUT_DIR/extract-pom.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    
    <groupId>com.redhat.analysis</groupId>
    <artifactId>camel-bom-extractor</artifactId>
    <version>1.0.0</version>
    
    <repositories>
        <repository>
            <id>indy</id>
            <url>https://indy.corp.redhat.com/api/content/maven/hosted/pnc-builds</url>
        </repository>
    </repositories>
    
    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>org.apache.camel</groupId>
                <artifactId>camel-bom</artifactId>
                <version>4.22.0.redhat-00001</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>
</project>
EOF

cd "$OUTPUT_DIR"
mvn help:effective-pom -f extract-pom.xml -Doutput=effective-pom.xml > /dev/null 2>&1
cd - > /dev/null

# Extract all managed dependencies
if [ -f "$OUTPUT_DIR/effective-pom.xml" ]; then
    # Extract groupId:artifactId:version from dependencyManagement
    sed -n '/<dependencyManagement>/,/<\/dependencyManagement>/p' "$OUTPUT_DIR/effective-pom.xml" | \
        grep -A 3 '<dependency>' | \
        awk '
            /<groupId>/ {gsub(/<\/?groupId>/, ""); g=$0}
            /<artifactId>/ {gsub(/<\/?artifactId>/, ""); a=$0}
            /<version>/ {gsub(/<\/?version>/, ""); v=$0; print g":"a":"v}
        ' | \
        sed 's/^[[:space:]]*//' | \
        grep -v '^$' | \
        sort -u > "$OUTPUT_DIR/all-managed-deps.txt"
    
    TOTAL_MANAGED=$(wc -l < "$OUTPUT_DIR/all-managed-deps.txt" | tr -d ' ')
    echo "✓ Found $TOTAL_MANAGED managed dependencies in BOM"
else
    echo "✗ Failed to extract effective POM"
    exit 1
fi

# Step 3: Separate Camel components from third-party deps
echo ""
echo "[3/5] Separating Camel components from third-party dependencies..."

grep '^org\.apache\.camel:' "$OUTPUT_DIR/all-managed-deps.txt" > "$OUTPUT_DIR/camel-components.txt" || true
grep -v '^org\.apache\.camel:' "$OUTPUT_DIR/all-managed-deps.txt" > "$OUTPUT_DIR/third-party-deps.txt" || true

CAMEL_COUNT=$(wc -l < "$OUTPUT_DIR/camel-components.txt" | tr -d ' ')
THIRD_PARTY_COUNT=$(wc -l < "$OUTPUT_DIR/third-party-deps.txt" | tr -d ' ')

echo "✓ Camel components: $CAMEL_COUNT"
echo "✓ Third-party dependencies: $THIRD_PARTY_COUNT"

# Step 4: Check productization status
echo ""
echo "[4/5] Checking productization status of third-party dependencies..."

PRODUCTIZED_FILE="$OUTPUT_DIR/productized-deps.txt"
UNPRODUCTIZED_FILE="$OUTPUT_DIR/unproductized-deps.txt"

> "$PRODUCTIZED_FILE"
> "$UNPRODUCTIZED_FILE"

if [ "$THIRD_PARTY_COUNT" -gt 0 ]; then
    current=0
    
    while IFS= read -r dep; do
        current=$((current + 1))
        
        if [ $((current % 50)) -eq 0 ]; then
            echo "  Checked $current/$THIRD_PARTY_COUNT dependencies..."
        fi
        
        # Extract GAV
        groupId=$(echo "$dep" | cut -d: -f1)
        artifactId=$(echo "$dep" | cut -d: -f2)
        version=$(echo "$dep" | cut -d: -f3)
        
        # Check if already has .redhat suffix
        if [[ "$version" == *".redhat-"* ]]; then
            echo "$dep" >> "$PRODUCTIZED_FILE"
            continue
        fi
        
        # Check for .redhat version in Indy
        redhat_version="${version}.redhat-00001"
        group_path=$(echo "$groupId" | tr '.' '/')
        
        check_url="$INDY_URL/$group_path/$artifactId/$redhat_version/$artifactId-${redhat_version}.pom"
        
        if curl -f -s -I "$check_url" > /dev/null 2>&1; then
            echo "$dep -> $redhat_version" >> "$PRODUCTIZED_FILE"
        else
            echo "$dep" >> "$UNPRODUCTIZED_FILE"
        fi
    done < "$OUTPUT_DIR/third-party-deps.txt"
    
    PRODUCTIZED_COUNT=$(wc -l < "$PRODUCTIZED_FILE" | tr -d ' ')
    UNPRODUCTIZED_COUNT=$(wc -l < "$UNPRODUCTIZED_FILE" | tr -d ' ')
    
    echo "✓ Already productized: $PRODUCTIZED_COUNT"
    echo "✓ Need productization: $UNPRODUCTIZED_COUNT"
fi

# Step 5: Categorize and generate report
echo ""
echo "[5/5] Generating comprehensive report..."

# Categorize by group
cat "$OUTPUT_DIR/third-party-deps.txt" | cut -d: -f1 | sort | uniq -c | sort -rn > "$OUTPUT_DIR/by-group.txt"

# Calculate percentages
if [ "$THIRD_PARTY_COUNT" -gt 0 ]; then
    PROD_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($PRODUCTIZED_COUNT/$THIRD_PARTY_COUNT)*100}")
    UNPROD_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($UNPRODUCTIZED_COUNT/$THIRD_PARTY_COUNT)*100}")
else
    PROD_PERCENT="0.0"
    UNPROD_PERCENT="0.0"
fi

# Generate report
cat > "$OUTPUT_DIR/PRODUCTIZATION_REPORT.md" <<EOF
# Camel $CAMEL_VERSION - Complete Productization Analysis

**Generated**: $(date +"%Y-%m-%d %H:%M:%S")
**Source**: Indy productized BOM

---

## Executive Summary

| Metric | Count |
|--------|-------|
| Total Managed Dependencies | $TOTAL_MANAGED |
| Camel Components | $CAMEL_COUNT |
| Third-Party Dependencies | $THIRD_PARTY_COUNT |
| Already Productized | $PRODUCTIZED_COUNT (${PROD_PERCENT}%) |
| Need Productization | $UNPRODUCTIZED_COUNT (${UNPROD_PERCENT}%) |

---

## Top 20 Third-Party Dependency Groups

\`\`\`
$(head -20 "$OUTPUT_DIR/by-group.txt")
\`\`\`

---

## Already Productized Dependencies

\`\`\`
$(head -100 "$PRODUCTIZED_FILE")
$([ "$PRODUCTIZED_COUNT" -gt 100 ] && echo "... and $((PRODUCTIZED_COUNT - 100)) more")
\`\`\`

---

## Unproductized Dependencies (Need Building)

\`\`\`
$(cat "$UNPRODUCTIZED_FILE")
\`\`\`

---

## Priority Build Order

### Wave 1: Core Libraries
\`\`\`
$(grep -E "(slf4j|log4j|commons-)" "$UNPRODUCTIZED_FILE" || echo "All core libraries productized")
\`\`\`

### Wave 2: Messaging
\`\`\`
$(grep -E "(kafka|qpid|activemq|amqp|jms)" "$UNPRODUCTIZED_FILE" || echo "All messaging libraries productized")
\`\`\`

### Wave 3: Data Formats
\`\`\`
$(grep -E "(jackson|jaxb|xml|json|yaml)" "$UNPRODUCTIZED_FILE" || echo "All data format libraries productized")
\`\`\`

### Wave 4: Networking
\`\`\`
$(grep -E "(netty|http|okhttp)" "$UNPRODUCTIZED_FILE" || echo "All networking libraries productized")
\`\`\`

### Wave 5: CXF & Web Services
\`\`\`
$(grep -E "(cxf|ws|soap|wsdl)" "$UNPRODUCTIZED_FILE" || echo "All CXF libraries productized")
\`\`\`

---

## Files Generated

- \`all-managed-deps.txt\` - All dependencies from BOM ($TOTAL_MANAGED)
- \`camel-components.txt\` - Camel components ($CAMEL_COUNT)
- \`third-party-deps.txt\` - Third-party dependencies ($THIRD_PARTY_COUNT)
- \`productized-deps.txt\` - Already productized ($PRODUCTIZED_COUNT)
- \`unproductized-deps.txt\` - Need building ($UNPRODUCTIZED_COUNT)
- \`by-group.txt\` - Dependencies grouped by organization

---

## Next Steps

1. Review \`unproductized-deps.txt\` for dependencies to build
2. Generate PNC build configs: \`./generate_camel_transitive_builds.sh\`
3. Create builds in PNC using bacon CLI
4. Monitor and verify build success

---

**Analysis Complete**
EOF

echo "✓ Report generated: $OUTPUT_DIR/PRODUCTIZATION_REPORT.md"

# Summary
echo ""
echo "=========================================="
echo "Analysis Complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  • Total Managed Dependencies: $TOTAL_MANAGED"
echo "  • Camel Components: $CAMEL_COUNT"
echo "  • Third-Party Dependencies: $THIRD_PARTY_COUNT"
echo "  • Already Productized: $PRODUCTIZED_COUNT (${PROD_PERCENT}%)"
echo "  • Need Productization: $UNPRODUCTIZED_COUNT (${UNPROD_PERCENT}%)"
echo ""
echo "Files:"
echo "  • Report: $OUTPUT_DIR/PRODUCTIZATION_REPORT.md"
echo "  • Unproductized list: $OUTPUT_DIR/unproductized-deps.txt"
echo ""
