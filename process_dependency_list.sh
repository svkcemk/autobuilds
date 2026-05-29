#!/bin/bash

# process_dependency_list.sh - Process a dependency list file and generate build configs
# Usage: ./process_dependency_list.sh <dependency-file> [output-dir]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check arguments
if [ $# -lt 1 ]; then
    print_error "Usage: $0 <dependency-file> [output-dir]"
    echo ""
    echo "Example:"
    echo "  $0 camel-test/all-dependencies.txt output/"
    echo "  $0 camel-test/filtered-dependencies.txt camel-builds/"
    exit 1
fi

DEPS_FILE="$1"
OUTPUT_DIR="${2:-output}"

# Validate input file
if [ ! -f "$DEPS_FILE" ]; then
    print_error "Dependency file not found: $DEPS_FILE"
    exit 1
fi

print_info "Processing dependencies from: $DEPS_FILE"
print_info "Output directory: $OUTPUT_DIR"

# Create output directory
mkdir -p "$OUTPUT_DIR/build-configs"

# Count dependencies
TOTAL=$(grep -v "^$" "$DEPS_FILE" | wc -l | tr -d ' ')
print_info "Found $TOTAL dependencies to process"

# Process each dependency
COUNT=0
while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    
    COUNT=$((COUNT + 1))
    
    # Parse dependency (format: groupId:artifactId:type:version or groupId:artifactId:version)
    IFS=':' read -ra PARTS <<< "$line"
    
    if [ ${#PARTS[@]} -eq 3 ]; then
        # Format: groupId:artifactId:version
        GROUP="${PARTS[0]}"
        ARTIFACT="${PARTS[1]}"
        VERSION="${PARTS[2]}"
    elif [ ${#PARTS[@]} -ge 4 ]; then
        # Format: groupId:artifactId:type:version:scope
        GROUP="${PARTS[0]}"
        ARTIFACT="${PARTS[1]}"
        VERSION="${PARTS[3]}"
    else
        print_error "Invalid format: $line"
        continue
    fi
    
    # Clean up whitespace
    GROUP=$(echo "$GROUP" | tr -d '[:space:]|')
    ARTIFACT=$(echo "$ARTIFACT" | tr -d '[:space:]|')
    VERSION=$(echo "$VERSION" | tr -d '[:space:]|')
    
    print_info "[$COUNT/$TOTAL] Processing: $GROUP:$ARTIFACT:$VERSION"
    
    # Generate config file name
    CONFIG_NAME="${GROUP}_${ARTIFACT}_${VERSION}"
    CONFIG_FILE="$OUTPUT_DIR/build-configs/${CONFIG_NAME}.yaml"
    
    # Create build config YAML
    cat > "$CONFIG_FILE" << EOF
name: ${CONFIG_NAME}
description: "Build configuration for ${ARTIFACT} ${VERSION}"
project: ${ARTIFACT}
scmRepository:
  url: "https://github.com/placeholder/${ARTIFACT}.git"
  revision: "${VERSION}"
buildScript: "mvn clean deploy -DskipTests"
environment:
  name: "OpenJDK 11"
buildType: MVN
EOF
    
    print_success "Created: $CONFIG_FILE"
    
done < "$DEPS_FILE"

# Generate summary
print_info "Generating summary report..."

cat > "$OUTPUT_DIR/SUMMARY.md" << EOF
# Build Config Generation Summary

Generated: $(date)
Input file: $DEPS_FILE

## Statistics

- Total dependencies processed: $COUNT
- Build configs created: $(ls -1 "$OUTPUT_DIR/build-configs"/*.yaml 2>/dev/null | wc -l | tr -d ' ')

## Output Files

- Build configs: \`$OUTPUT_DIR/build-configs/\`
- Summary: \`$OUTPUT_DIR/SUMMARY.md\`

## Next Steps

1. Review the generated configs in: \`$OUTPUT_DIR/build-configs/\`
2. Update SCM URLs with actual repository locations
3. Use bacon CLI to create builds in PNC:
   \`\`\`bash
   for config in $OUTPUT_DIR/build-configs/*.yaml; do
       bacon pnc build-config create -f "\$config"
   done
   \`\`\`

## Sample Config

\`\`\`yaml
$(head -20 "$OUTPUT_DIR/build-configs"/*.yaml 2>/dev/null | head -15)
\`\`\`
EOF

print_success "Summary saved to: $OUTPUT_DIR/SUMMARY.md"
print_success "All done! Generated $COUNT build configs in $OUTPUT_DIR/build-configs/"

echo ""
print_info "To view summary: cat $OUTPUT_DIR/SUMMARY.md"
print_info "To list configs: ls -lh $OUTPUT_DIR/build-configs/"

# Made with Bob
