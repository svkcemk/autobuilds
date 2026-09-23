#!/bin/bash

set -e

# Camel Transitive Dependency Productization Analyzer
# Analyzes third-party dependencies of Camel 4.22.0.redhat-00001 components

CAMEL_VERSION="4.22.0.redhat-00001"
OUTPUT_DIR="camel-4.22.0-productization-report"
INDY_URL="https://indy.psi.redhat.com/api/content/maven/group/builds-untested+shared-imports+public"
MAVEN_CENTRAL="https://repo1.maven.org/maven2"

echo "=========================================="
echo "Camel Transitive Dependency Analyzer"
echo "Version: $CAMEL_VERSION"
echo "=========================================="
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Step 1: Download Camel BOM from Indy
echo "[1/6] Downloading Camel BOM from Indy..."
BOM_URL="$INDY_URL/org/apache/camel/camel-bom/${CAMEL_VERSION}/camel-bom-${CAMEL_VERSION}.pom"
BOM_FILE="$OUTPUT_DIR/camel-bom-${CAMEL_VERSION}.pom"

if curl -f -s -o "$BOM_FILE" "$BOM_URL"; then
    echo "✓ Downloaded Camel BOM from Indy"
else
    echo "✗ Failed to download Camel BOM from Indy"
    echo "  Trying Maven Central for upstream version..."
    UPSTREAM_VERSION="4.22.0"
    curl -f -s -o "$BOM_FILE" "$MAVEN_CENTRAL/org/apache/camel/camel-bom/${UPSTREAM_VERSION}/camel-bom-${UPSTREAM_VERSION}.pom" || {
        echo "✗ Failed to download from Maven Central"
        exit 1
    }
    CAMEL_VERSION="$UPSTREAM_VERSION"
fi

# Step 2: Extract Camel components from BOM
echo ""
echo "[2/6] Extracting Camel components from BOM..."
COMPONENTS_FILE="$OUTPUT_DIR/camel-components.txt"

# Extract all org.apache.camel dependencies from BOM using sed
sed -n '/<groupId>org\.apache\.camel<\/groupId>/{n;s/.*<artifactId>\(.*\)<\/artifactId>.*/\1/p;}' "$BOM_FILE" | \
    grep -v '^camel-bom$' | \
    sort -u > "$COMPONENTS_FILE"

COMPONENT_COUNT=$(wc -l < "$COMPONENTS_FILE" | tr -d ' ')
echo "✓ Found $COMPONENT_COUNT Camel components"

# Step 3: Analyze transitive dependencies for sample components
echo ""
echo "[3/6] Analyzing transitive dependencies (sampling 30 components)..."
TRANSITIVE_DEPS_FILE="$OUTPUT_DIR/all-transitive-deps.txt"
THIRD_PARTY_DEPS_FILE="$OUTPUT_DIR/third-party-deps.txt"

> "$TRANSITIVE_DEPS_FILE"
> "$THIRD_PARTY_DEPS_FILE"

# Create temporary Maven project for analysis
TEMP_PROJECT="$OUTPUT_DIR/temp-analysis"
mkdir -p "$TEMP_PROJECT"

cat > "$TEMP_PROJECT/pom.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    
    <groupId>com.redhat.analysis</groupId>
    <artifactId>camel-transitive-analysis</artifactId>
    <version>1.0.0</version>
    
    <repositories>
        <repository>
            <id>redhat-ga</id>
            <url>https://maven.repository.redhat.com/ga/</url>
        </repository>
        <repository>
            <id>indy</id>
            <url>$INDY_URL</url>
        </repository>
    </repositories>
    
    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>org.apache.camel</groupId>
                <artifactId>camel-bom</artifactId>
                <version>$CAMEL_VERSION</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>
    
    <dependencies>
EOF

# Add sample of important components
echo "  Adding key components to analysis..."
for component in camel-core camel-kafka camel-http camel-cxf-soap camel-jackson camel-jaxb \
                 camel-amqp camel-jms camel-sql camel-rest camel-netty-http camel-csv \
                 camel-xml-jaxb camel-activemq camel-atom camel-aws2-s3 camel-bean \
                 camel-direct camel-file camel-ftp camel-jdbc camel-log camel-mail \
                 camel-quartz camel-scheduler camel-seda camel-timer camel-velocity; do
    if grep -q "^${component}$" "$COMPONENTS_FILE"; then
        cat >> "$TEMP_PROJECT/pom.xml" <<EOF
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>$component</artifactId>
        </dependency>
EOF
    fi
done

cat >> "$TEMP_PROJECT/pom.xml" <<EOF
    </dependencies>
</project>
EOF

# Generate dependency list (more reliable than tree)
echo "  Resolving dependencies..."
cd "$TEMP_PROJECT"
mvn dependency:list -DoutputFile="../dependency-list.txt" -DexcludeTransitive=false > /dev/null 2>&1 || {
    echo "  Warning: Some dependencies may not be available"
}
cd - > /dev/null

# Extract third-party dependencies
if [ -f "$OUTPUT_DIR/dependency-list.txt" ]; then
    # Extract compile scope dependencies, exclude org.apache.camel
    grep ':compile' "$OUTPUT_DIR/dependency-list.txt" | \
        sed 's/^[[:space:]]*//' | \
        sed 's/:compile$//' | \
        grep -v '^org\.apache\.camel:' | \
        sort -u > "$THIRD_PARTY_DEPS_FILE"
    
    THIRD_PARTY_COUNT=$(wc -l < "$THIRD_PARTY_DEPS_FILE" | tr -d ' ')
    echo "✓ Found $THIRD_PARTY_COUNT unique third-party dependencies"
else
    echo "✗ Failed to generate dependency list"
    THIRD_PARTY_COUNT=0
fi

# Step 4: Check productization status
echo ""
echo "[4/6] Checking productization status..."
PRODUCTIZED_FILE="$OUTPUT_DIR/productized-deps.txt"
UNPRODUCTIZED_FILE="$OUTPUT_DIR/unproductized-deps.txt"

> "$PRODUCTIZED_FILE"
> "$UNPRODUCTIZED_FILE"

if [ -f "$THIRD_PARTY_DEPS_FILE" ] && [ "$THIRD_PARTY_COUNT" -gt 0 ]; then
    total=$THIRD_PARTY_COUNT
    current=0
    
    while IFS= read -r dep; do
        current=$((current + 1))
        
        # Show progress every 20 deps
        if [ $((current % 20)) -eq 0 ]; then
            echo "  Checked $current/$total dependencies..."
        fi
        
        # Extract GAV
        groupId=$(echo "$dep" | cut -d: -f1)
        artifactId=$(echo "$dep" | cut -d: -f2)
        version=$(echo "$dep" | cut -d: -f4)
        
        # Check for .redhat version in Indy
        redhat_version="${version}.redhat-00001"
        group_path=$(echo "$groupId" | tr '.' '/')
        
        check_url="$INDY_URL/$group_path/$artifactId/$redhat_version/$artifactId-${redhat_version}.pom"
        
        if curl -f -s -I "$check_url" > /dev/null 2>&1; then
            echo "$dep -> $redhat_version" >> "$PRODUCTIZED_FILE"
        else
            echo "$dep" >> "$UNPRODUCTIZED_FILE"
        fi
    done < "$THIRD_PARTY_DEPS_FILE"
    
    PRODUCTIZED_COUNT=$(wc -l < "$PRODUCTIZED_FILE" | tr -d ' ')
    UNPRODUCTIZED_COUNT=$(wc -l < "$UNPRODUCTIZED_FILE" | tr -d ' ')
    
    echo "✓ Productized: $PRODUCTIZED_COUNT"
    echo "✓ Unproductized: $UNPRODUCTIZED_COUNT"
else
    PRODUCTIZED_COUNT=0
    UNPRODUCTIZED_COUNT=0
fi

# Step 5: Categorize by library family
echo ""
echo "[5/6] Categorizing dependencies..."
CATEGORIES_FILE="$OUTPUT_DIR/dependency-categories.txt"

if [ -f "$THIRD_PARTY_DEPS_FILE" ] && [ "$THIRD_PARTY_COUNT" -gt 0 ]; then
    cat "$THIRD_PARTY_DEPS_FILE" | cut -d: -f1 | sort | uniq -c | sort -rn > "$CATEGORIES_FILE"
    
    echo "✓ Top 10 dependency groups:"
    head -10 "$CATEGORIES_FILE" | while read count group; do
        echo "  $group: $count dependencies"
    done
else
    > "$CATEGORIES_FILE"
    echo "  No dependencies to categorize"
fi

# Step 6: Generate comprehensive report
echo ""
echo "[6/6] Generating report..."
REPORT_FILE="$OUTPUT_DIR/PRODUCTIZATION_REPORT.md"

# Calculate percentages safely
if [ "$THIRD_PARTY_COUNT" -gt 0 ]; then
    PROD_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($PRODUCTIZED_COUNT/$THIRD_PARTY_COUNT)*100}")
    UNPROD_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($UNPRODUCTIZED_COUNT/$THIRD_PARTY_COUNT)*100}")
else
    PROD_PERCENT="0.0"
    UNPROD_PERCENT="0.0"
fi

cat > "$REPORT_FILE" <<EOF
# Camel $CAMEL_VERSION - Transitive Dependency Productization Report

**Generated**: $(date +"%Y-%m-%d %H:%M:%S")

---

## Executive Summary

| Metric | Count |
|--------|-------|
| Camel Components Analyzed | $COMPONENT_COUNT |
| Sample Components Used | 30 (key components) |
| Total Third-Party Dependencies | $THIRD_PARTY_COUNT |
| Already Productized | $PRODUCTIZED_COUNT |
| Need Productization | $UNPRODUCTIZED_COUNT |
| Productization Rate | ${PROD_PERCENT}% |

---

## Top Dependency Groups

\`\`\`
$(head -20 "$CATEGORIES_FILE")
\`\`\`

---

## Productized Dependencies

The following third-party dependencies already have .redhat versions available:

\`\`\`
$(cat "$PRODUCTIZED_FILE" 2>/dev/null | head -50)
$([ -f "$PRODUCTIZED_FILE" ] && [ $(wc -l < "$PRODUCTIZED_FILE" | tr -d ' ') -gt 50 ] && echo "... and $(($(wc -l < "$PRODUCTIZED_FILE" | tr -d ' ') - 50)) more")
\`\`\`

---

## Unproductized Dependencies (Need Building)

The following third-party dependencies need to be productized:

\`\`\`
$(cat "$UNPRODUCTIZED_FILE" 2>/dev/null | head -100)
$([ -f "$UNPRODUCTIZED_FILE" ] && [ $(wc -l < "$UNPRODUCTIZED_FILE" | tr -d ' ') -gt 100 ] && echo "... and $(($(wc -l < "$UNPRODUCTIZED_FILE" | tr -d ' ') - 100)) more")
\`\`\`

---

## Priority Dependencies for Productization

### Critical (Core Libraries)
\`\`\`
$(grep -E "(slf4j|log4j|commons-|guava)" "$UNPRODUCTIZED_FILE" 2>/dev/null || echo "None found")
\`\`\`

### Messaging
\`\`\`
$(grep -E "(kafka|qpid|activemq|amqp)" "$UNPRODUCTIZED_FILE" 2>/dev/null || echo "None found")
\`\`\`

### Data Formats
\`\`\`
$(grep -E "(jackson|jaxb|gson|xml)" "$UNPRODUCTIZED_FILE" 2>/dev/null || echo "None found")
\`\`\`

### Networking
\`\`\`
$(grep -E "(netty|http|okhttp)" "$UNPRODUCTIZED_FILE" 2>/dev/null || echo "None found")
\`\`\`

---

## Next Steps

1. **Review Unproductized List**: Prioritize which dependencies need building
2. **Generate Build Configs**: Use generate_build_configs.sh for unproductized deps
3. **Create PNC Builds**: Submit builds to PNC in dependency order
4. **Monitor Progress**: Track build success/failure rates
5. **Verify Artifacts**: Confirm artifacts are available in Maven repository

---

## Files Generated

- \`camel-components.txt\` - List of all Camel components ($COMPONENT_COUNT total)
- \`third-party-deps.txt\` - All third-party dependencies ($THIRD_PARTY_COUNT total)
- \`productized-deps.txt\` - Dependencies with .redhat versions ($PRODUCTIZED_COUNT total)
- \`unproductized-deps.txt\` - Dependencies needing productization ($UNPRODUCTIZED_COUNT total)
- \`dependency-categories.txt\` - Dependencies grouped by organization
- \`dependency-list.txt\` - Full Maven dependency list

---

**Report Location**: \`$OUTPUT_DIR/\`
EOF

echo "✓ Report generated: $REPORT_FILE"

# Summary
echo ""
echo "=========================================="
echo "Analysis Complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  • Camel Components: $COMPONENT_COUNT"
echo "  • Third-Party Dependencies: $THIRD_PARTY_COUNT"
echo "  • Already Productized: $PRODUCTIZED_COUNT (${PROD_PERCENT}%)"
echo "  • Need Productization: $UNPRODUCTIZED_COUNT (${UNPROD_PERCENT}%)"
echo ""
echo "Full report: $REPORT_FILE"
echo ""
echo "Next: Review unproductized-deps.txt and generate build configs"
echo ""