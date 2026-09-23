#!/bin/bash
###############################################################################
# Example Workflow Script
#
# Demonstrates a complete workflow for generating and creating PNC builds
# from transitive dependencies
###############################################################################

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "================================================================================"
echo "  PNC Transitive Build Generation - Example Workflow"
echo "================================================================================"
echo ""

# Step 1: Validate configuration
echo -e "${BLUE}Step 1: Validating configuration...${NC}"
./validate_config.sh build-config.yaml
echo ""

# Step 2: Dry run to see what will be generated
echo -e "${BLUE}Step 2: Running dry-run to preview...${NC}"
./generate_transitive_builds.sh --dry-run --verbose
echo ""

read -p "Continue with actual generation? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted by user"
    exit 0
fi

# Step 3: Generate build configs
echo -e "${BLUE}Step 3: Generating build configurations...${NC}"
./generate_transitive_builds.sh --output ./example-builds --verbose
echo ""

# Step 4: Review the report
echo -e "${BLUE}Step 4: Build generation report:${NC}"
cat example-builds/build-report.txt
echo ""

# Step 5: Show generated files
echo -e "${BLUE}Step 5: Generated files:${NC}"
echo "Total build configs: $(find example-builds/build-configs -name "*.yaml" 2>/dev/null | wc -l)"
echo "Sample configs:"
ls -1 example-builds/build-configs/*.yaml 2>/dev/null | head -5
echo ""

# Step 6: Instructions for PNC
echo -e "${BLUE}Step 6: Next steps for PNC integration:${NC}"
echo ""
echo "To create builds in PNC, you can:"
echo ""
echo "1. Create individual build configs:"
echo "   for config in example-builds/build-configs/*.yaml; do"
echo "     bacon pnc build-config create --file \"\$config\""
echo "   done"
echo ""
echo "2. Or create a build group:"
echo "   bacon pnc build-group create --file example-builds/pig-config.yaml"
echo ""
echo "3. Trigger builds:"
echo "   bacon pnc build start --build-config-id <CONFIG_ID>"
echo ""

echo -e "${GREEN}Workflow complete!${NC}"
echo "Check example-builds/ directory for all generated files"
