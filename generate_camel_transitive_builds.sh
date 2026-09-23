#!/bin/bash

set -e

# Generate Build Configs for Camel 4.22.0 Transitive Dependencies
# Uses the unproductized dependencies list from the productization report

DEPS_FILE="camel-4.22.0-productization-report/unproductized-deps-clean.txt"
OUTPUT_DIR="camel-4.22.0-transitive-builds"
CONFIG_FILE="build-config-camel-4.22.0.yaml"

echo "=========================================="
echo "Camel 4.22.0 Transitive Build Generator"
echo "=========================================="
echo ""

# Check if dependencies file exists
if [ ! -f "$DEPS_FILE" ]; then
    echo "Error: Dependencies file not found: $DEPS_FILE"
    echo "Please run analyze_camel_transitive_productization.sh first"
    exit 1
fi

# Count dependencies
TOTAL_DEPS=$(wc -l < "$DEPS_FILE" | tr -d ' ')
echo "Found $TOTAL_DEPS dependencies to build"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate build configs using the unified script
echo "[1/3] Generating build configs for all transitive dependencies..."
echo "This may take 10-15 minutes..."
echo ""

./generate_build_configs.sh \
  -r "$DEPS_FILE" \
  -c "$CONFIG_FILE" \
  -o "$OUTPUT_DIR" \
  --format both \
  --no-pnc-integration \
  --verbose

echo ""
echo "[2/3] Analyzing generated build configs..."

# Count generated configs
if [ -d "$OUTPUT_DIR/build-configs" ]; then
    CONFIG_COUNT=$(find "$OUTPUT_DIR/build-configs" -name "*.yaml" -type f | wc -l | tr -d ' ')
    echo "✓ Generated $CONFIG_COUNT build config files"
else
    echo "✗ No build configs generated"
    exit 1
fi

# Check for combined YAML
if [ -f "$OUTPUT_DIR/combined-build-configs.yaml" ]; then
    echo "✓ Combined build config created"
else
    echo "⚠ Combined build config not found"
fi

# Generate summary report
echo ""
echo "[3/3] Creating build summary..."

cat > "$OUTPUT_DIR/BUILD_SUMMARY.md" <<EOF
# Camel 4.22.0 Transitive Dependencies - Build Summary

**Generated**: $(date +"%Y-%m-%d %H:%M:%S")

---

## Overview

| Metric | Count |
|--------|-------|
| Total Dependencies | $TOTAL_DEPS |
| Build Configs Generated | $CONFIG_COUNT |
| Output Directory | \`$OUTPUT_DIR\` |

---

## Build Config Files

Individual build configs are located in:
\`\`\`
$OUTPUT_DIR/build-configs/
\`\`\`

Combined build config (for PNC):
\`\`\`
$OUTPUT_DIR/combined-build-configs.yaml
\`\`\`

---

## Next Steps - PNC Integration

### Option 1: Create All Builds at Once (Recommended)

\`\`\`bash
# Upload combined config to PNC
bacon pnc build-config create --file $OUTPUT_DIR/combined-build-configs.yaml

# Or create individual configs
for config in $OUTPUT_DIR/build-configs/*.yaml; do
  echo "Creating: \$(basename \$config)"
  bacon pnc build-config create --file "\$config"
  sleep 1
done
\`\`\`

### Option 2: Create Builds by Priority

#### Wave 1: Core Libraries (Build First)
\`\`\`bash
# SLF4J, Commons, Logging
bacon pnc build-config create --file $OUTPUT_DIR/build-configs/org.slf4j_slf4j-api_2.0.18.yaml
bacon pnc build-config create --file $OUTPUT_DIR/build-configs/commons-logging_commons-logging_1.3.5.yaml
bacon pnc build-config create --file $OUTPUT_DIR/build-configs/org.apache.commons_commons-lang3_3.17.0.yaml
# ... add more core libraries
\`\`\`

#### Wave 2: Messaging Libraries
\`\`\`bash
# Kafka, Qpid, ActiveMQ
bacon pnc build-config create --file $OUTPUT_DIR/build-configs/org.apache.kafka_kafka-clients_4.3.1.yaml
bacon pnc build-config create --file $OUTPUT_DIR/build-configs/org.apache.qpid_qpid-jms-client_2.10.0.yaml
bacon pnc build-config create --file $OUTPUT_DIR/build-configs/org.apache.activemq_activemq-client-jakarta_5.19.9.yaml
\`\`\`

#### Wave 3: Data Format Libraries
\`\`\`bash
# Jackson, JAXB, XML
bacon pnc build-config create --file $OUTPUT_DIR/build-configs/com.fasterxml.jackson.core_jackson-core_2.22.1.yaml
bacon pnc build-config create --file $OUTPUT_DIR/build-configs/com.fasterxml.jackson.core_jackson-databind_2.22.1.yaml
bacon pnc build-config create --file $OUTPUT_DIR/build-configs/org.glassfish.jaxb_jaxb-runtime_4.0.9.yaml
\`\`\`

#### Wave 4: Networking Libraries
\`\`\`bash
# Netty, HTTP Components
bacon pnc build-config create --file $OUTPUT_DIR/build-configs/io.netty_netty-common_4.2.16.Final.yaml
bacon pnc build-config create --file $OUTPUT_DIR/build-configs/io.netty_netty-buffer_4.2.16.Final.yaml
bacon pnc build-config create --file $OUTPUT_DIR/build-configs/org.apache.httpcomponents.core5_httpcore5_5.4.3.yaml
\`\`\`

#### Wave 5: CXF Components
\`\`\`bash
# CXF Runtime
bacon pnc build-config create --file $OUTPUT_DIR/build-configs/org.apache.cxf_cxf-core_4.2.3.yaml
bacon pnc build-config create --file $OUTPUT_DIR/build-configs/org.apache.cxf_cxf-rt-bindings-soap_4.2.3.yaml
# ... add more CXF components
\`\`\`

---

## Monitoring Builds

### Check Build Status
\`\`\`bash
# Watch overall progress
watch -n 60 'bacon pnc build list --latest | grep -E "(SUCCESS|FAILED|BUILDING)" | sort | uniq -c'

# Check specific build
bacon pnc build list --query="buildConfigName==org_apache_kafka_kafka-clients_4_3_1"

# List all failed builds
bacon pnc build list --status FAILED
\`\`\`

### Retry Failed Builds
\`\`\`bash
# Retry all failed builds
bacon pnc build list --status FAILED | while read build_id; do
  bacon pnc build start "\$build_id"
  sleep 5
done
\`\`\`

---

## Dependency Categories

### Top 10 Groups (by count)
1. **software.amazon.awssdk** - 31 dependencies
2. **io.netty** - 19 dependencies  
3. **org.apache.cxf** - 11 dependencies
4. **org.springframework** - 9 dependencies
5. **org.glassfish.jaxb** - 3 dependencies
6. **org.apache.commons** - 3 dependencies
7. **com.fasterxml.jackson.core** - 3 dependencies
8. **org.eclipse.angus** - 2 dependencies
9. **org.apache.qpid** - 2 dependencies
10. **org.apache.httpcomponents.core5** - 2 dependencies

---

## Critical Dependencies (Must Build First)

### Core Libraries
- org.slf4j:slf4j-api:2.0.18
- commons-logging:commons-logging:1.3.5
- org.apache.commons:commons-lang3:3.17.0
- commons-codec:commons-codec:1.22.1
- commons-io:commons-io:2.20.0

### Messaging
- org.apache.kafka:kafka-clients:4.3.1
- org.apache.qpid:qpid-jms-client:2.10.0
- org.apache.activemq:activemq-client-jakarta:5.19.9

### Data Formats
- com.fasterxml.jackson.core:jackson-core:2.22.1
- com.fasterxml.jackson.core:jackson-databind:2.22.1
- org.glassfish.jaxb:jaxb-runtime:4.0.9

### Networking
- io.netty:netty-common:4.2.16.Final
- io.netty:netty-buffer:4.2.16.Final
- io.netty:netty-handler:4.2.16.Final
- org.apache.httpcomponents.core5:httpcore5:5.4.3

---

## Estimated Timeline

- **Config Generation**: ✅ Complete
- **PNC Creation**: 2-4 hours (manual)
- **Build Execution**: 24-48 hours (automated)
- **Verification**: 4-6 hours (manual)

**Total**: 2-3 days

---

## Success Criteria

- ✅ All build configs generated
- ⏳ All configs created in PNC
- ⏳ >95% build success rate
- ⏳ Critical dependencies built successfully
- ⏳ Artifacts available in Maven repository

---

## Troubleshooting

### Issue: Build Config Creation Fails

**Solution**: Check if build config already exists or if SCM URL is invalid

\`\`\`bash
bacon pnc build-config get <config-name>
\`\`\`

### Issue: Build Fails Due to Missing Dependencies

**Solution**: Check dependency order and ensure prerequisites are built first

\`\`\`bash
# Check build logs
bacon pnc build logs <build-id>
\`\`\`

### Issue: SCM Resolution Fails

**Solution**: Manually specify SCM URL in build config YAML

---

**Generated by**: generate_camel_transitive_builds.sh
**Report Location**: \`$OUTPUT_DIR/BUILD_SUMMARY.md\`
EOF

echo "✓ Build summary created: $OUTPUT_DIR/BUILD_SUMMARY.md"

# Final summary
echo ""
echo "=========================================="
echo "Build Config Generation Complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  • Dependencies Processed: $TOTAL_DEPS"
echo "  • Build Configs Generated: $CONFIG_COUNT"
echo "  • Output Directory: $OUTPUT_DIR"
echo ""
echo "Next Steps:"
echo "  1. Review: $OUTPUT_DIR/BUILD_SUMMARY.md"
echo "  2. Create builds in PNC using bacon CLI"
echo "  3. Monitor build progress"
echo "  4. Verify artifacts in Maven repository"
echo ""
echo "Quick Start:"
echo "  # Create all builds at once"
echo "  for config in $OUTPUT_DIR/build-configs/*.yaml; do"
echo "    bacon pnc build-config create --file \"\$config\""
echo "  done"
echo ""
