#!/bin/bash
###############################################################################
# Build Config Validator
#
# Validates build-config.yaml for correctness and completeness
###############################################################################

set -e

CONFIG_FILE="${1:-build-config.yaml}"
ERRORS=0
WARNINGS=0

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ERRORS=$((ERRORS + 1))
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

echo "Validating config file: $CONFIG_FILE"
echo "========================================"

# Check if file exists
if [ ! -f "$CONFIG_FILE" ]; then
    error "Config file not found: $CONFIG_FILE"
    exit 1
fi

# Check if yq is available
if ! command -v yq &> /dev/null; then
    error "yq is required for validation. Install with: pip install yq"
    exit 1
fi

# Validate YAML syntax
if ! yq . "$CONFIG_FILE" > /dev/null 2>&1; then
    error "Invalid YAML syntax"
    exit 1
fi
success "YAML syntax is valid"

# Check required sections
echo ""
echo "Checking required sections..."

if yq -e '.dependencyResolutionConfig' "$CONFIG_FILE" > /dev/null 2>&1; then
    success "dependencyResolutionConfig section found"
else
    error "Missing dependencyResolutionConfig section"
fi

if yq -e '.buildConfigGeneratorConfig' "$CONFIG_FILE" > /dev/null 2>&1; then
    success "buildConfigGeneratorConfig section found"
else
    error "Missing buildConfigGeneratorConfig section"
fi

# Check dependencyResolutionConfig
echo ""
echo "Validating dependencyResolutionConfig..."

if yq -e '.dependencyResolutionConfig.analyzeBOM' "$CONFIG_FILE" > /dev/null 2>&1; then
    BOM=$(yq -r '.dependencyResolutionConfig.analyzeBOM' "$CONFIG_FILE")
    if [[ $BOM =~ ^[^:]+:[^:]+:[^:]+$ ]]; then
        success "analyzeBOM is valid: $BOM"
    else
        error "analyzeBOM format invalid. Expected: groupId:artifactId:version"
    fi
else
    error "Missing analyzeBOM"
fi

if yq -e '.dependencyResolutionConfig.includeArtifacts' "$CONFIG_FILE" > /dev/null 2>&1; then
    COUNT=$(yq -r '.dependencyResolutionConfig.includeArtifacts | length' "$CONFIG_FILE")
    success "Found $COUNT include patterns"
else
    warn "No includeArtifacts patterns defined"
fi

if yq -e '.dependencyResolutionConfig.excludeArtifacts' "$CONFIG_FILE" > /dev/null 2>&1; then
    COUNT=$(yq -r '.dependencyResolutionConfig.excludeArtifacts | length' "$CONFIG_FILE")
    success "Found $COUNT exclude patterns"
else
    warn "No excludeArtifacts patterns defined"
fi

# Check buildConfigGeneratorConfig
echo ""
echo "Validating buildConfigGeneratorConfig..."

if yq -e '.buildConfigGeneratorConfig.defaultValues.environmentName' "$CONFIG_FILE" > /dev/null 2>&1; then
    ENV=$(yq -r '.buildConfigGeneratorConfig.defaultValues.environmentName' "$CONFIG_FILE")
    success "Default environment: $ENV"
else
    warn "No default environmentName specified"
fi

if yq -e '.buildConfigGeneratorConfig.defaultValues.buildScript' "$CONFIG_FILE" > /dev/null 2>&1; then
    SCRIPT=$(yq -r '.buildConfigGeneratorConfig.defaultValues.buildScript' "$CONFIG_FILE")
    success "Default build script: $SCRIPT"
else
    warn "No default buildScript specified"
fi

if yq -e '.buildConfigGeneratorConfig.pigTemplate' "$CONFIG_FILE" > /dev/null 2>&1; then
    success "PIG template configuration found"
    
    # Validate PIG template fields
    if yq -e '.buildConfigGeneratorConfig.pigTemplate.product.name' "$CONFIG_FILE" > /dev/null 2>&1; then
        PRODUCT=$(yq -r '.buildConfigGeneratorConfig.pigTemplate.product.name' "$CONFIG_FILE")
        success "Product name: $PRODUCT"
    else
        error "Missing product.name in pigTemplate"
    fi
    
    if yq -e '.buildConfigGeneratorConfig.pigTemplate.version' "$CONFIG_FILE" > /dev/null 2>&1; then
        VERSION=$(yq -r '.buildConfigGeneratorConfig.pigTemplate.version' "$CONFIG_FILE")
        success "Product version: $VERSION"
    else
        error "Missing version in pigTemplate"
    fi
else
    warn "No pigTemplate configuration found"
fi

# Summary
echo ""
echo "========================================"
echo "Validation Summary:"
echo "  Errors: $ERRORS"
echo "  Warnings: $WARNINGS"

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}Configuration is valid!${NC}"
    exit 0
else
    echo -e "${RED}Configuration has errors!${NC}"
    exit 1
fi
