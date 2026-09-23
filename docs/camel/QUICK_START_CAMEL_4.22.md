# Quick Start: Camel 4.22.0 & CXF 4.2.3 Build

## TL;DR - Get Started in 5 Minutes

This is your quick-start guide to begin building Camel 4.22.0 and CXF 4.2.3 in PNC.

---

## Prerequisites Check

```bash
# Verify you have the required tools
which mvn && echo "✓ Maven installed"
which bacon && echo "✓ Bacon CLI installed"
which jq && echo "✓ jq installed"
which yq && echo "✓ yq installed"

# Verify you're in the autobuilds directory
pwd
# Should show: /Users/soghosh/autobuilds
```

---

## Step 1: Create Configuration File (2 minutes)

Create `build-config-camel-4.22.0.yaml`:

```bash
cat > build-config-camel-4.22.0.yaml <<'EOF'
dependencyResolutionConfig:
  analyzeBOM: org.apache.camel:camel-bom:4.22.0
  includeArtifacts:
    - org.apache.camel:*:*
    - org.apache.cxf:*:*
  excludeArtifacts:
    - org.apache.camel:camel-aws*:*
    - org.apache.camel:camel-azure*:*
    - org.apache.camel:camel-google*:*
    - org.apache.camel:*:*:test
    - org.apache.camel:camel-test*:*
  includeOptionalDependencies: false

buildConfigGeneratorConfig:
  defaultValues:
    environmentName: "OpenJDK 21.0; RHEL 9; Mvn 3.9.9"
    buildScript: "mvn -DskipTests clean deploy -B"
  scmPattern:
    "git@github.com:": "https://github.com/"
  scmMapping:
    "org.apache.camel:*": "https://github.com/apache/camel.git"
    "org.apache.cxf:*": "https://github.com/apache/cxf.git"
EOF

echo "✓ Configuration file created"
```

---

## Step 2: Generate Initial Build Configs (3 minutes)

### Option A: Generate Everything at Once (Recommended)

```bash
# Create the complete build script
cat > start-camel-4.22-build.sh <<'EOF'
#!/bin/bash
set -e

OUTPUT_DIR="camel-4.22.0-builds"
CONFIG_FILE="build-config-camel-4.22.0.yaml"

echo "=== Starting Camel 4.22.0 Build Config Generation ==="

# Step 1: Camel BOM
echo "[1/5] Generating Camel BOM..."
./generate_build_configs.sh \
  -a org.apache.camel:camel-bom:4.22.0 \
  -c "$CONFIG_FILE" \
  -o "$OUTPUT_DIR/bom" \
  --format both \
  --no-pnc

# Step 2: CXF BOM
echo "[2/5] Generating CXF BOM..."
./generate_build_configs.sh \
  -a org.apache.cxf:cxf-bom:4.2.3 \
  -c "$CONFIG_FILE" \
  -o "$OUTPUT_DIR/cxf-bom" \
  --format both \
  --no-pnc

# Step 3: Camel Components
echo "[3/5] Generating Camel components..."
./generate_build_configs.sh \
  -b org.apache.camel:camel-bom:4.22.0 \
  -c "$CONFIG_FILE" \
  -o "$OUTPUT_DIR/components" \
  --format both \
  --no-pnc

# Step 4: CXF Components
echo "[4/5] Generating CXF components..."
./generate_build_configs.sh \
  -b org.apache.cxf:cxf-bom:4.2.3 \
  -c "$CONFIG_FILE" \
  -o "$OUTPUT_DIR/cxf-components" \
  --format both \
  --no-pnc

# Step 5: Transitive Dependencies
echo "[5/5] Generating transitive dependencies..."
./generate_build_configs.sh \
  -b org.apache.camel:camel-bom:4.22.0 \
  -c "$CONFIG_FILE" \
  -o "$OUTPUT_DIR/transitives" \
  --format both \
  --no-pnc

echo ""
echo "=== Generation Complete! ==="
echo "Total configs generated:"
find "$OUTPUT_DIR" -name "*.yaml" -type f | wc -l
echo ""
echo "Next steps:"
echo "1. Review: cat $OUTPUT_DIR/*/build-report.txt"
echo "2. Create in PNC: See CAMEL_4.22_BUILD_PLAN.md Phase 5"
EOF

chmod +x start-camel-4.22-build.sh

# Run it
./start-camel-4.22-build.sh
```

### Option B: Step-by-Step (For Testing)

```bash
# Just generate Camel BOM first
mkdir -p camel-4.22.0-builds

./generate_build_configs.sh \
  -a org.apache.camel:camel-bom:4.22.0 \
  -c build-config-camel-4.22.0.yaml \
  -o camel-4.22.0-builds/bom \
  --format both \
  --no-pnc \
  -v

# Review the result
cat camel-4.22.0-builds/bom/build-report.txt
```

---

## Step 3: Review Generated Configs

```bash
# Check what was generated
ls -la camel-4.22.0-builds/

# View summary reports
cat camel-4.22.0-builds/bom/build-report.txt
cat camel-4.22.0-builds/components/build-report.txt

# Count total configs
find camel-4.22.0-builds -name "*.yaml" -type f | wc -l

# View a sample config
cat camel-4.22.0-builds/bom/build-configs/org.apache.camel_camel-bom_4.22.0.yaml
```

---

## Step 4: Create Builds in PNC

### Create All Build Configs

```bash
# Create all build configs in PNC
for config in camel-4.22.0-builds/*/build-configs/*.yaml; do
  echo "Creating: $(basename $config)"
  bacon pnc build-config create --file "$config"
  sleep 1  # Rate limiting
done
```

### Start Initial Builds (BOMs First)

```bash
# Start Camel BOM build
bacon pnc build start org.apache.camel-camel-bom-4.22.0

# Start CXF BOM build
bacon pnc build start org.apache.cxf-cxf-bom-4.2.3

# Monitor progress
bacon pnc build list --query="buildConfigName==*camel*4.22.0*" --latest
```

---

## Step 5: Monitor & Manage

### Check Build Status

```bash
# Watch build progress
watch -n 30 'bacon pnc build list --query="buildConfigName==*camel*4.22.0*" | grep -E "(SUCCESS|FAILED|BUILDING)" | sort | uniq -c'

# Check for failures
bacon pnc build list --query="buildConfigName==*camel*4.22.0*" --status FAILED
```

### Batch Build Execution

```bash
# Create batch build script
cat > execute-camel-builds.sh <<'EOF'
#!/bin/bash

# Read build order (if you generated it)
if [ -f "camel-4.22.0-builds/final/build-order.txt" ]; then
  BUILD_ORDER_FILE="camel-4.22.0-builds/final/build-order.txt"
else
  # Use all configs
  BUILD_ORDER_FILE=$(mktemp)
  find camel-4.22.0-builds -name "*.yaml" -type f > "$BUILD_ORDER_FILE"
fi

BATCH_SIZE=10
WAIT_TIME=300

mapfile -t BUILDS < "$BUILD_ORDER_FILE"
total=${#BUILDS[@]}

echo "Total builds: $total"

for ((i=0; i<$total; i+=$BATCH_SIZE)); do
  batch=$((i / BATCH_SIZE + 1))
  echo "=== Batch $batch ==="
  
  for ((j=i; j<i+BATCH_SIZE && j<total; j++)); do
    build="${BUILDS[$j]}"
    build_name=$(basename "$build" .yaml)
    
    echo "Starting: $build_name"
    bacon pnc build start "$build_name" || echo "Failed: $build_name"
  done
  
  echo "Waiting ${WAIT_TIME}s..."
  sleep $WAIT_TIME
done
EOF

chmod +x execute-camel-builds.sh
```

---

## Common Issues & Quick Fixes

### Issue: "Config file not found"

```bash
# Verify file exists
ls -la build-config-camel-4.22.0.yaml

# If missing, recreate it (see Step 1)
```

### Issue: "BOM not found in Maven Central"

```bash
# Verify Camel 4.22.0 exists
mvn dependency:get \
  -DgroupId=org.apache.camel \
  -DartifactId=camel-bom \
  -Dversion=4.22.0 \
  -Dpackaging=pom
```

### Issue: "SCM resolution failed"

```bash
# Add to lib/scm_resolver.sh
cat >> lib/scm_resolver.sh <<'EOF'

# Camel 4.22.0 SCM mapping
org.apache.camel:*)
  echo "SCM_URL=https://github.com/apache/camel.git"
  echo "SCM_REVISION=camel-${version}"
  return 0
  ;;
EOF
```

---

## What You Should See

### After Step 2 (Generation)

```
✓ camel-4.22.0-builds/
  ✓ bom/build-configs/          (1-2 configs)
  ✓ cxf-bom/build-configs/      (1-2 configs)
  ✓ components/build-configs/   (200-300 configs)
  ✓ cxf-components/build-configs/ (50-80 configs)
  ✓ transitives/build-configs/  (500-1000 configs)
```

### After Step 4 (PNC Creation)

```
✓ All build configs registered in PNC
✓ Build configs visible in bacon CLI
✓ Ready to trigger builds
```

### After Step 5 (Builds Running)

```
✓ Builds in BUILDING status
✓ Some builds completing (SUCCESS)
✓ Monitoring for failures
```

---

## Next Steps After Quick Start

1. **Review Full Plan**: Read `CAMEL_4.22_BUILD_PLAN.md` for complete details
2. **Customize Config**: Adjust `build-config-camel-4.22.0.yaml` as needed
3. **Handle Failures**: Use build logs to debug and retry
4. **Verify Productization**: Check artifacts in Maven repository

---

## Time Estimates

- **Step 1**: 2 minutes (config creation)
- **Step 2**: 10-30 minutes (config generation)
- **Step 3**: 5 minutes (review)
- **Step 4**: 30-60 minutes (PNC creation)
- **Step 5**: 24-48 hours (build execution - mostly automated)

**Total Active Time**: ~1-2 hours  
**Total Elapsed Time**: 1-3 days (including build time)

---

## Success Checklist

- [ ] Configuration file created
- [ ] Build configs generated successfully
- [ ] Configs reviewed and validated
- [ ] Build configs created in PNC
- [ ] Initial builds (BOMs) started
- [ ] Monitoring system in place
- [ ] Failure handling process ready

---

## Getting Help

- **Full Documentation**: `CAMEL_4.22_BUILD_PLAN.md`
- **Configuration Guide**: `CAMEL_4.22_CONFIG_GUIDE.md`
- **Tool Documentation**: `README.md`
- **Transitive Dependencies**: `TRANSITIVE_DEPENDENCY_GUIDE.md`

---

**Ready to Start?** Run the commands in Step 1 and Step 2!

**Last Updated**: 2026-08-13
