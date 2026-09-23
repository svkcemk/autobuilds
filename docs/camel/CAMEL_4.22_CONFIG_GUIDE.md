# Camel 4.22.0 Build Configuration Guide

## Overview

This guide provides the complete build configuration for Apache Camel 4.22.0 and CXF 4.2.3 builds in PNC.

---

## Step 1: Create build-config-camel-4.22.0.yaml

Create a new file `build-config-camel-4.22.0.yaml` with the following content:

```yaml
# Build Configuration for Apache Camel 4.22.0 & CXF 4.2.3
# This configuration is optimized for building Camel 4.22.0 with all components and transitive dependencies

dependencyResolutionConfig:
  # Analyze Camel 4.22.0 BOM
  analyzeBOM: org.apache.camel:camel-bom:4.22.0
  
  # Include Camel and CXF artifacts
  includeArtifacts:
    - org.apache.camel:*:*
    - org.apache.cxf:*:*
  
  # Exclude artifacts that should not be built
  excludeArtifacts:
    # AWS Cloud Components (not needed for core builds)
    - org.apache.camel:camel-aws*:*
    - org.apache.camel:camel-aws2*:*
    
    # Azure Cloud Components
    - org.apache.camel:camel-azure*:*
    
    # Google Cloud Components
    - org.apache.camel:camel-google*:*
    
    # Huawei Cloud Components
    - org.apache.camel:camel-huaweicloud*:*
    
    # IBM Cloud Components (optional - remove if needed)
    - org.apache.camel:camel-ibm*:*
    
    # Test artifacts
    - org.apache.camel:*:*:test
    - org.apache.camel:*:*:test-jar
    - org.apache.camel:camel-test*:*
    
    # Native/GraalVM specific (build separately if needed)
    - org.apache.camel:*-native:*
    - org.apache.camel:*-graalvm:*
    
    # Deprecated components
    - org.apache.camel:camel-atmosphere*:*
    - org.apache.camel:camel-spark*:*
    - org.apache.camel:camel-milo*:*
    
    # Build tools (not runtime artifacts)
    - org.apache.camel:camel-package-maven-plugin:*
    - org.apache.camel:camel-api-component-maven-plugin:*
    
    # Documentation artifacts
    - org.apache.camel:*:*:javadoc
    - org.apache.camel:*:*:sources
    
    # Archetypes
    - org.apache.camel:*-archetype:*
    
    # Examples
    - org.apache.camel:camel-example*:*
  
  # Include optional dependencies (set to false to reduce scope)
  includeOptionalDependencies: false

buildConfigGeneratorConfig:
  defaultValues:
    # Environment for Camel 4.22.0 (requires Java 21)
    environmentName: "OpenJDK 21.0; RHEL 9; Mvn 3.9.9"
    
    # Standard build script (skip tests for faster builds)
    buildScript: "mvn -DskipTests clean deploy -B"
  
  # SCM URL transformations
  scmPattern:
    "git@github.com:": "https://github.com/"
    "git://github.com/": "https://github.com/"
    "scm:git:": ""
  
  # SCM URL mappings for known artifacts
  scmMapping:
    "org.apache.camel:*": "https://github.com/apache/camel.git"
    "org.apache.cxf:*": "https://github.com/apache/cxf.git"
```

---

## Step 2: Quick Start Commands

### Generate Camel 4.22.0 BOM Build Config

```bash
# Create output directory
mkdir -p camel-4.22.0-builds

# Generate Camel BOM build config
./generate_build_configs.sh \
  -a org.apache.camel:camel-bom:4.22.0 \
  -c build-config-camel-4.22.0.yaml \
  -o camel-4.22.0-builds/bom \
  --format both \
  --no-pnc \
  -v
```

### Generate CXF 4.2.3 BOM Build Config

```bash
# Generate CXF BOM build config
./generate_build_configs.sh \
  -a org.apache.cxf:cxf-bom:4.2.3 \
  -c build-config-camel-4.22.0.yaml \
  -o camel-4.22.0-builds/cxf-bom \
  --format both \
  --no-pnc \
  -v
```

### Generate All Camel Components

```bash
# Generate all Camel component build configs
./generate_build_configs.sh \
  -b org.apache.camel:camel-bom:4.22.0 \
  -c build-config-camel-4.22.0.yaml \
  -o camel-4.22.0-builds/components \
  --format both \
  --no-pnc \
  -v

# Review results
cat camel-4.22.0-builds/components/build-report.txt
```

### Generate All CXF Components

```bash
# Generate all CXF component build configs
./generate_build_configs.sh \
  -b org.apache.cxf:cxf-bom:4.2.3 \
  -c build-config-camel-4.22.0.yaml \
  -o camel-4.22.0-builds/cxf-components \
  --format both \
  --no-pnc \
  -v

# Review results
cat camel-4.22.0-builds/cxf-components/build-report.txt
```

### Generate Transitive Dependencies

```bash
# Generate transitive dependency build configs
./generate_build_configs.sh \
  -b org.apache.camel:camel-bom:4.22.0 \
  -c build-config-camel-4.22.0.yaml \
  -o camel-4.22.0-builds/transitives \
  --format both \
  --no-pnc \
  -v

# Review transitive dependencies
cat camel-4.22.0-builds/transitives/third-party-dependencies.txt | head -50
```

---

## Step 3: Configuration Customization

### Include Spring Boot Components

If you need Camel Spring Boot components, modify the config:

```yaml
includeArtifacts:
  - org.apache.camel:*:*
  - org.apache.camel.springboot:*:*
  - org.apache.cxf:*:*
```

### Include Quarkus Components

If you need Camel Quarkus components:

```yaml
includeArtifacts:
  - org.apache.camel:*:*
  - org.apache.camel.quarkus:*:*
  - org.apache.cxf:*:*
```

### Include Cloud Components

To include specific cloud providers, remove them from excludeArtifacts:

```yaml
excludeArtifacts:
  # Remove these lines to include AWS components
  # - org.apache.camel:camel-aws*:*
  # - org.apache.camel:camel-aws2*:*
```

### Enable Productization Check

To check for already-productized artifacts:

```yaml
# Add to your command
./generate_build_configs.sh \
  -b org.apache.camel:camel-bom:4.22.0 \
  --check-productization \
  --redhat-suffix redhat-00001 \
  -o camel-4.22.0-builds/components
```

---

## Step 4: SCM Resolution Configuration

### Add Custom SCM Mappings

If you need custom SCM URLs, add to `lib/scm_resolver.sh`:

```bash
# Add to the case statement in resolve_scm_info()

org.apache.camel:*)
  echo "SCM_URL=https://github.com/apache/camel.git"
  echo "SCM_REVISION=camel-${version}"
  return 0
  ;;

org.apache.cxf:*)
  echo "SCM_URL=https://github.com/apache/cxf.git"
  echo "SCM_REVISION=cxf-${version}"
  return 0
  ;;
```

---

## Step 5: Environment Configuration

### Update env-database.json

Add Camel 4.22.0 environment patterns:

```json
{
  "environments": [
    {
      "name": "OpenJDK 21.0; RHEL 9; Mvn 3.9.9",
      "patterns": [
        "org.apache.camel:*:4.22.*",
        "org.apache.cxf:*:4.2.*"
      ]
    }
  ]
}
```

---

## Step 6: Validation

### Validate Configuration

```bash
# Validate the config file
./validate_config.sh build-config-camel-4.22.0.yaml

# Expected output: "Configuration is valid"
```

### Test with Single Component

```bash
# Test with a single component first
./generate_build_configs.sh \
  -a org.apache.camel:camel-core:4.22.0 \
  -c build-config-camel-4.22.0.yaml \
  -o camel-4.22.0-builds/test \
  -v

# Review the generated config
cat camel-4.22.0-builds/test/build-configs/org.apache.camel_camel-core_4.22.0.yaml
```

---

## Step 7: Complete Build Workflow

### Full Automated Build

```bash
#!/bin/bash
# complete-camel-4.22-build.sh

set -e

OUTPUT_DIR="camel-4.22.0-builds"
CONFIG_FILE="build-config-camel-4.22.0.yaml"

echo "=== Camel 4.22.0 Complete Build Workflow ==="

# Step 1: Generate Camel BOM
echo "Step 1: Generating Camel BOM build config..."
./generate_build_configs.sh \
  -a org.apache.camel:camel-bom:4.22.0 \
  -c "$CONFIG_FILE" \
  -o "$OUTPUT_DIR/bom" \
  --format both \
  --no-pnc

# Step 2: Generate CXF BOM
echo "Step 2: Generating CXF BOM build config..."
./generate_build_configs.sh \
  -a org.apache.cxf:cxf-bom:4.2.3 \
  -c "$CONFIG_FILE" \
  -o "$OUTPUT_DIR/cxf-bom" \
  --format both \
  --no-pnc

# Step 3: Generate all Camel components
echo "Step 3: Generating Camel component build configs..."
./generate_build_configs.sh \
  -b org.apache.camel:camel-bom:4.22.0 \
  -c "$CONFIG_FILE" \
  -o "$OUTPUT_DIR/components" \
  --format both \
  --no-pnc

# Step 4: Generate all CXF components
echo "Step 4: Generating CXF component build configs..."
./generate_build_configs.sh \
  -b org.apache.cxf:cxf-bom:4.2.3 \
  -c "$CONFIG_FILE" \
  -o "$OUTPUT_DIR/cxf-components" \
  --format both \
  --no-pnc

# Step 5: Generate transitive dependencies
echo "Step 5: Generating transitive dependency build configs..."
./generate_build_configs.sh \
  -b org.apache.camel:camel-bom:4.22.0 \
  -c "$CONFIG_FILE" \
  -o "$OUTPUT_DIR/transitives" \
  --format both \
  --no-pnc

# Step 6: Combine all configs
echo "Step 6: Combining all build configs..."
mkdir -p "$OUTPUT_DIR/final"
cat "$OUTPUT_DIR"/*/combined-build-configs.yaml > "$OUTPUT_DIR/final/all-builds.yaml"

# Step 7: Generate summary report
echo "Step 7: Generating summary report..."
cat > "$OUTPUT_DIR/SUMMARY.md" <<EOF
# Camel 4.22.0 Build Summary

## Generated Build Configs

- Camel BOM: $(ls -1 $OUTPUT_DIR/bom/build-configs/*.yaml 2>/dev/null | wc -l) configs
- CXF BOM: $(ls -1 $OUTPUT_DIR/cxf-bom/build-configs/*.yaml 2>/dev/null | wc -l) configs
- Camel Components: $(ls -1 $OUTPUT_DIR/components/build-configs/*.yaml 2>/dev/null | wc -l) configs
- CXF Components: $(ls -1 $OUTPUT_DIR/cxf-components/build-configs/*.yaml 2>/dev/null | wc -l) configs
- Transitive Dependencies: $(ls -1 $OUTPUT_DIR/transitives/build-configs/*.yaml 2>/dev/null | wc -l) configs

## Total Build Configs

Total: $(find $OUTPUT_DIR -name "*.yaml" -type f | wc -l) YAML files

## Next Steps

1. Review generated configs in: $OUTPUT_DIR
2. Create builds in PNC using bacon CLI
3. Monitor build progress
4. Verify productization

EOF

cat "$OUTPUT_DIR/SUMMARY.md"

echo ""
echo "=== Build config generation complete! ==="
echo "Output directory: $OUTPUT_DIR"
echo "Review the SUMMARY.md file for details."
```

Make it executable and run:

```bash
chmod +x complete-camel-4.22-build.sh
./complete-camel-4.22-build.sh
```

---

## Troubleshooting

### Issue: Configuration Not Found

**Error**: `Config file not found: build-config-camel-4.22.0.yaml`

**Solution**: Ensure you created the config file in the correct location:
```bash
ls -la build-config-camel-4.22.0.yaml
```

### Issue: No Dependencies Found

**Error**: `No dependencies found in BOM`

**Solution**: Verify the BOM exists in Maven Central:
```bash
mvn dependency:get \
  -DgroupId=org.apache.camel \
  -DartifactId=camel-bom \
  -Dversion=4.22.0 \
  -Dpackaging=pom
```

### Issue: SCM Resolution Failures

**Error**: `Failed to resolve SCM for artifact`

**Solution**: Add SCM mappings to the config or `lib/scm_resolver.sh`

---

## Best Practices

1. **Start Small**: Test with a single component before generating all configs
2. **Review Exclusions**: Adjust excludeArtifacts based on your needs
3. **Check Dependencies**: Verify transitive dependencies are reasonable
4. **Validate Configs**: Always validate generated configs before creating in PNC
5. **Monitor Builds**: Keep track of build progress and failures
6. **Document Changes**: Keep notes on any custom configurations

---

## Reference

- Main Build Plan: `CAMEL_4.22_BUILD_PLAN.md`
- Tool Documentation: `README.md`
- Transitive Guide: `TRANSITIVE_DEPENDENCY_GUIDE.md`
- Camel Analysis: `CAMEL_ANALYSIS_GUIDE.md`

---

**Last Updated**: 2026-08-13  
**Version**: 1.0
