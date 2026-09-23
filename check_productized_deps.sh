#!/bin/bash

# Check which third-party dependencies from our list are actually productized
DEPS_FILE="camel-4.22.0-productization-report/unproductized-deps-clean.txt"
INDY_URL="https://indy.corp.redhat.com/api/content/maven/hosted/pnc-builds"
OUTPUT="camel-productized-check-results.txt"

echo "Checking productization status of 124 dependencies..." > "$OUTPUT"
echo "" >> "$OUTPUT"

checked=0
productized=0
not_productized=0

while IFS= read -r dep; do
    checked=$((checked + 1))
    
    groupId=$(echo "$dep" | cut -d: -f1)
    artifactId=$(echo "$dep" | cut -d: -f2)
    version=$(echo "$dep" | cut -d: -f3)
    
    # Try .redhat-00001 suffix
    redhat_version="${version}.redhat-00001"
    group_path=$(echo "$groupId" | tr '.' '/')
    
    check_url="$INDY_URL/$group_path/$artifactId/$redhat_version/$artifactId-${redhat_version}.pom"
    
    if curl -f -s -I "$check_url" > /dev/null 2>&1; then
        echo "✓ PRODUCTIZED: $groupId:$artifactId:$redhat_version" >> "$OUTPUT"
        productized=$((productized + 1))
    else
        echo "✗ NOT FOUND: $groupId:$artifactId:$version" >> "$OUTPUT"
        not_productized=$((not_productized + 1))
    fi
    
    if [ $((checked % 20)) -eq 0 ]; then
        echo "Progress: $checked/124 checked..."
    fi
done < "$DEPS_FILE"

echo "" >> "$OUTPUT"
echo "========================================" >> "$OUTPUT"
echo "Summary:" >> "$OUTPUT"
echo "  Checked: $checked" >> "$OUTPUT"
echo "  Productized: $productized" >> "$OUTPUT"
echo "  Not Productized: $not_productized" >> "$OUTPUT"
echo "========================================" >> "$OUTPUT"

cat "$OUTPUT"
