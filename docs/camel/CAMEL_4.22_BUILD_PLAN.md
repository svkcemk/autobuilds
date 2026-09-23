# Apache Camel 4.22.0 & CXF 4.2.3 PNC Build Plan

## Executive Summary

This document outlines the complete strategy for building Apache Camel 4.22.0 and Apache CXF 4.2.3 in PNC (Project Newcastle), including all transitive dependencies.

**Key Information:**
- **Camel Version**: 4.22.0
- **CXF Version**: 4.2.3 (determined from camel-cxf-soap dependencies)
- **RedHat Suffix**: redhat-00001
- **Build Approach**: Build Camel BOM first, then CXF, then all transitive dependencies
- **Productization Check**: Skipped (as requested)

---

## Phase 1: Initial Builds (Camel & CXF Core)

### Step 1.1: Build Camel 4.22.0 BOM

**Objective**: Build the main Camel BOM which defines all component versions.

**Artifact**: `org.apache.camel:camel-bom:4.22.0`

**Commands**:
```bash
# Create output directory
mkdir -p camel-4.22.0-builds

# Generate Camel BOM build config
./generate_build_configs.sh \
  -a org.apache.camel:camel-bom:4.22.0 \
  -o camel-4.22.0-builds/bom \
  --format both \
  --no-pnc \
  -v

# Review generated config
cat camel-4.22.0-builds/bom/build-report.txt
```

**Expected Output**:
- Build config for camel-bom-4.22.0
- SCM URL: https://github.com/apache/camel.git
- SCM Revision: camel-4.22.0 (tag)

**PNC Build**:
```bash
# Create build in PNC
bacon pnc build-config create \
  --file camel-4.22.0-builds/bom/build-configs/org.apache.camel_camel-bom_4.22.0.yaml

# Trigger build
bacon pnc build start org.apache.camel-camel-bom-4.22.0
```

---

### Step 1.2: Build CXF 4.2.3 BOM

**Objective**: Build Apache CXF BOM which is required by Camel CXF components.

**Artifact**: `org.apache.cxf:cxf-bom:4.2.3`

**Commands**:
```bash
# Generate CXF BOM build config
./generate_build_configs.sh \
  -a org.apache.cxf:cxf-bom:4.2.3 \
  -o camel-4.22.0-builds/cxf-bom \
  --format both \
  --no-pnc \
  -v

# Review generated config
cat camel-4.22.0-builds/cxf-bom/build-report.txt
```

**Expected Output**:
- Build config for cxf-bom-4.2.3
- SCM URL: https://github.com/apache/cxf.git
- SCM Revision: cxf-4.2.3 (tag)

**PNC Build**:
```bash
# Create build in PNC
bacon pnc build-config create \
  --file camel-4.22.0-builds/cxf-bom/build-configs/org.apache.cxf_cxf-bom_4.2.3.yaml

# Trigger build
bacon pnc build start org.apache.cxf-cxf-bom-4.2.3
```

---

## Phase 2: Camel Components Analysis

### Step 2.1: Analyze Camel 4.22.0 BOM for All Components

**Objective**: Generate build configs for all Camel components defined in the BOM.

**Configuration**: Update `build-config.yaml` to target Camel 4.22.0:

```yaml
dependencyResolutionConfig:
  analyzeBOM: org.apache.camel:camel-bom:4.22.0
  includeArtifacts:
    - org.apache.camel:*:*
    - org.apache.cxf:*:*
  excludeArtifacts:
    # Cloud providers (not needed for core builds)
    - org.apache.camel:camel-aws*:*
    - org.apache.camel:camel-azure*:*
    - org.apache.camel:camel-google*:*
    - org.apache.camel:camel-huaweicloud*:*
    
    # Test and build-time only
    - org.apache.camel:*:*:test
    - org.apache.camel:*:*:test-jar
    - org.apache.camel:camel-test*:*
    
    # Native/GraalVM specific
    - org.apache.camel:*-native:*
    - org.apache.camel:*-graalvm:*
    
    # Deprecated components
    - org.apache.camel:camel-atmosphere*:*
    - org.apache.camel:camel-spark*:*
    
  includeOptionalDependencies: false

buildConfigGeneratorConfig:
  defaultValues:
    environmentName: "OpenJDK 21.0; RHEL 9; Mvn 3.9.9"
    buildScript: "mvn -DskipTests clean deploy -B"
```

**Commands**:
```bash
# Generate all Camel component build configs
./generate_build_configs.sh \
  -b org.apache.camel:camel-bom:4.22.0 \
  -c build-config.yaml \
  -o camel-4.22.0-builds/components \
  --format both \
  --no-pnc \
  -v

# Review results
cat camel-4.22.0-builds/components/build-report.txt
cat camel-4.22.0-builds/components/root-artifacts.txt | wc -l
```

**Expected Output**:
- 200-300 Camel component build configs
- Filtered list excluding cloud providers, test artifacts, etc.
- Combined YAML for batch processing

---

### Step 2.2: Analyze CXF 4.2.3 Components

**Objective**: Generate build configs for all CXF components.

**Commands**:
```bash
# Generate CXF component build configs
./generate_build_configs.sh \
  -b org.apache.cxf:cxf-bom:4.2.3 \
  -o camel-4.22.0-builds/cxf-components \
  --format both \
  --no-pnc \
  -v

# Review results
cat camel-4.22.0-builds/cxf-components/build-report.txt
```

**Expected Output**:
- 50-80 CXF component build configs
- Core CXF runtime modules
- CXF frontend and transport implementations

---

## Phase 3: Transitive Dependencies Analysis

### Step 3.1: Generate Full Dependency Tree

**Objective**: Get complete transitive dependency tree for Camel 4.22.0.

**Commands**:
```bash
# Create temporary Maven project with Camel BOM
mkdir -p camel-4.22.0-builds/dependency-analysis
cd camel-4.22.0-builds/dependency-analysis

# Create minimal pom.xml
cat > pom.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    
    <groupId>com.redhat.analysis</groupId>
    <artifactId>camel-dependency-analysis</artifactId>
    <version>1.0.0</version>
    
    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>org.apache.camel</groupId>
                <artifactId>camel-bom</artifactId>
                <version>4.22.0</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>
    
    <dependencies>
        <!-- Core Camel -->
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-core</artifactId>
        </dependency>
        
        <!-- Essential components -->
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-kafka</artifactId>
        </dependency>
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-http</artifactId>
        </dependency>
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-jackson</artifactId>
        </dependency>
        
        <!-- CXF components -->
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-cxf-soap</artifactId>
        </dependency>
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-cxf-rest</artifactId>
        </dependency>
    </dependencies>
</project>
EOF

# Generate dependency tree
mvn dependency:tree \
  -DoutputFile=camel-4.22.0-full-deps.txt \
  -DoutputType=text \
  -Dscope=compile

# Return to root
cd ../..
```

**Expected Output**:
- Complete dependency tree file
- All transitive dependencies at all levels
- Scope information (compile, runtime, etc.)

---

### Step 3.2: Generate Transitive Dependency Build Configs

**Objective**: Create build configs for all third-party transitive dependencies.

**Commands**:
```bash
# Generate build configs for transitive dependencies
./generate_build_configs.sh \
  -b org.apache.camel:camel-bom:4.22.0 \
  -o camel-4.22.0-builds/transitives \
  --format both \
  --no-pnc \
  -v

# Review transitive dependencies
cat camel-4.22.0-builds/transitives/third-party-dependencies.txt | head -50
cat camel-4.22.0-builds/transitives/build-report.txt
```

**Expected Output**:
- 500-1000+ transitive dependency build configs
- Third-party libraries (Apache Commons, Netty, Jackson, etc.)
- Dependency graph edges for build ordering

---

## Phase 4: Build Order & Dependency Management

### Step 4.1: Create Topological Build Order

**Objective**: Determine correct build order based on dependencies.

**Commands**:
```bash
# Generate dependency graph and build order
./generate_build_configs.sh \
  -b org.apache.camel:camel-bom:4.22.0 \
  -o camel-4.22.0-builds/final \
  --format combined \
  --no-pnc \
  -v

# Extract build order
cat camel-4.22.0-builds/final/dependency-edges.txt | \
  python3 -c "
import sys
from collections import defaultdict, deque

# Read dependency edges
edges = defaultdict(list)
in_degree = defaultdict(int)
all_nodes = set()

for line in sys.stdin:
    if '->' in line:
        parts = line.strip().split(' -> ')
        if len(parts) == 2:
            from_node, to_node = parts
            edges[from_node].append(to_node)
            in_degree[to_node] += 1
            all_nodes.add(from_node)
            all_nodes.add(to_node)

# Topological sort (Kahn's algorithm)
queue = deque([node for node in all_nodes if in_degree[node] == 0])
build_order = []

while queue:
    node = queue.popleft()
    build_order.append(node)
    
    for neighbor in edges[node]:
        in_degree[neighbor] -= 1
        if in_degree[neighbor] == 0:
            queue.append(neighbor)

# Print build order
for i, artifact in enumerate(build_order, 1):
    print(f'{i}. {artifact}')
" > camel-4.22.0-builds/final/build-order.txt

# Review build order
head -50 camel-4.22.0-builds/final/build-order.txt
```

**Expected Output**:
- Ordered list of artifacts to build
- Dependencies built before dependents
- No circular dependencies

---

### Step 4.2: Create PIG Configuration

**Objective**: Generate PIG (Product Integration Group) config for batch builds.

**Commands**:
```bash
# The combined YAML is already in PIG format
cp camel-4.22.0-builds/final/combined-build-configs.yaml \
   camel-4.22.0-builds/camel-4.22.0-pig-config.yaml

# Add PIG metadata
cat > camel-4.22.0-builds/pig-metadata.yaml <<'EOF'
product:
  name: Apache Camel
  abbreviation: camel
  version: 4.22.0.redhat-00001
  stage: ER1
  issueTrackerUrl: https://issues.redhat.com/projects/CAMEL

group: Camel 4.22.0 Initial Build

defaultBuildParameters:
  environmentName: "OpenJDK 21.0; RHEL 9; Mvn 3.9.9"
  buildScript: "mvn -DskipTests clean deploy -B"

# Include builds from combined config
EOF

# Merge PIG metadata with build configs
# (Manual step - combine pig-metadata.yaml with combined-build-configs.yaml)
```

---

## Phase 5: PNC Build Execution

### Step 5.1: Create Build Configs in PNC

**Objective**: Register all build configs in PNC.

**Commands**:
```bash
# Create all build configs in PNC
for config in camel-4.22.0-builds/final/build-configs/*.yaml; do
  echo "Creating build config: $(basename $config)"
  bacon pnc build-config create --file "$config"
  
  # Rate limit to avoid overwhelming PNC
  sleep 2
done

# Verify creation
bacon pnc build-config list --query="name==*camel*4.22.0*" | wc -l
```

**Expected Output**:
- All build configs registered in PNC
- Unique build config names
- No duplicate entries

---

### Step 5.2: Trigger Builds in Dependency Order

**Objective**: Start builds in correct order, respecting dependencies.

**Strategy**:
1. Build in waves/batches
2. Wait for each wave to complete before starting next
3. Handle failures and retry as needed

**Commands**:
```bash
# Create build execution script
cat > camel-4.22.0-builds/execute-builds.sh <<'EOF'
#!/bin/bash

set -e

BUILD_ORDER_FILE="camel-4.22.0-builds/final/build-order.txt"
BATCH_SIZE=10
WAIT_TIME=300  # 5 minutes between batches

# Read build order
mapfile -t BUILD_ORDER < "$BUILD_ORDER_FILE"

total_builds=${#BUILD_ORDER[@]}
echo "Total builds to execute: $total_builds"

# Process in batches
for ((i=0; i<$total_builds; i+=$BATCH_SIZE)); do
  batch_num=$((i / BATCH_SIZE + 1))
  echo ""
  echo "=== Batch $batch_num ==="
  
  # Start builds in this batch
  for ((j=i; j<i+BATCH_SIZE && j<total_builds; j++)); do
    artifact="${BUILD_ORDER[$j]}"
    # Extract build config name from artifact
    build_name=$(echo "$artifact" | sed 's/:/_/g' | sed 's/\./-/g')
    
    echo "Starting build: $build_name"
    bacon pnc build start "$build_name" || echo "Failed to start: $build_name"
  done
  
  # Wait for batch to complete
  echo "Waiting $WAIT_TIME seconds for batch to complete..."
  sleep $WAIT_TIME
  
  # Check batch status
  echo "Checking batch status..."
  for ((j=i; j<i+BATCH_SIZE && j<total_builds; j++)); do
    artifact="${BUILD_ORDER[$j]}"
    build_name=$(echo "$artifact" | sed 's/:/_/g' | sed 's/\./-/g')
    
    status=$(bacon pnc build list --query="buildConfigName==$build_name" --latest | \
             grep -oP 'Status: \K\w+' | head -1)
    
    echo "  $build_name: $status"
  done
done

echo ""
echo "All builds triggered!"
EOF

chmod +x camel-4.22.0-builds/execute-builds.sh

# Execute builds
./camel-4.22.0-builds/execute-builds.sh
```

---

### Step 5.3: Monitor Build Progress

**Objective**: Track build status and handle failures.

**Commands**:
```bash
# Monitor overall progress
watch -n 60 'bacon pnc build list --query="buildConfigName==*camel*4.22.0*" | \
             grep -E "(SUCCESS|FAILED|BUILDING)" | \
             sort | uniq -c'

# Check for failures
bacon pnc build list \
  --query="buildConfigName==*camel*4.22.0*" \
  --status FAILED > camel-4.22.0-builds/failed-builds.txt

# Review failed builds
cat camel-4.22.0-builds/failed-builds.txt
```

**Failure Handling**:
1. Review build logs for each failure
2. Identify root cause (missing dependency, build error, etc.)
3. Fix build config or dependency
4. Retry failed builds

---

## Phase 6: Verification & Validation

### Step 6.1: Verify All Builds Completed

**Objective**: Ensure all required artifacts are built successfully.

**Commands**:
```bash
# Count successful builds
successful=$(bacon pnc build list \
  --query="buildConfigName==*camel*4.22.0*" \
  --status SUCCESS | wc -l)

# Count total expected builds
total=$(cat camel-4.22.0-builds/final/build-order.txt | wc -l)

echo "Successful builds: $successful / $total"

# List any missing builds
bacon pnc build list \
  --query="buildConfigName==*camel*4.22.0*" \
  --status SUCCESS | \
  awk '{print $2}' | \
  sort > camel-4.22.0-builds/successful-builds.txt

comm -23 \
  <(cat camel-4.22.0-builds/final/build-order.txt | sort) \
  <(cat camel-4.22.0-builds/successful-builds.txt) \
  > camel-4.22.0-builds/missing-builds.txt

cat camel-4.22.0-builds/missing-builds.txt
```

---

### Step 6.2: Verify Productized Artifacts in Repository

**Objective**: Confirm artifacts are available with .redhat suffix.

**Commands**:
```bash
# Check key artifacts in Indy/Maven repository
key_artifacts=(
  "org.apache.camel:camel-core:4.22.0.redhat-00001"
  "org.apache.camel:camel-kafka:4.22.0.redhat-00001"
  "org.apache.camel:camel-cxf-soap:4.22.0.redhat-00001"
  "org.apache.cxf:cxf-core:4.2.3.redhat-00001"
)

echo "Verifying productized artifacts..."
for artifact in "${key_artifacts[@]}"; do
  IFS=':' read -r groupId artifactId version <<< "$artifact"
  
  # Check if artifact exists
  mvn dependency:get \
    -DgroupId="$groupId" \
    -DartifactId="$artifactId" \
    -Dversion="$version" \
    -DremoteRepositories="https://maven.repository.redhat.com/ga/" \
    > /dev/null 2>&1
  
  if [ $? -eq 0 ]; then
    echo "✓ $artifact"
  else
    echo "✗ $artifact (NOT FOUND)"
  fi
done
```

---

## Phase 7: Documentation & Handoff

### Step 7.1: Generate Build Report

**Objective**: Create comprehensive report of all builds.

**Commands**:
```bash
# Generate final report
cat > camel-4.22.0-builds/FINAL_REPORT.md <<'EOF'
# Camel 4.22.0 & CXF 4.2.3 Build Report

## Summary

- **Camel Version**: 4.22.0.redhat-00001
- **CXF Version**: 4.2.3.redhat-00001
- **Build Date**: $(date +%Y-%m-%d)
- **Total Builds**: $(cat camel-4.22.0-builds/final/build-order.txt | wc -l)
- **Successful Builds**: $(cat camel-4.22.0-builds/successful-builds.txt | wc -l)
- **Failed Builds**: $(cat camel-4.22.0-builds/failed-builds.txt | wc -l)

## Build Statistics

### Camel Components
- Core modules: $(grep "camel-core" camel-4.22.0-builds/successful-builds.txt | wc -l)
- Components: $(grep "camel-" camel-4.22.0-builds/successful-builds.txt | wc -l)
- CXF integration: $(grep "camel-cxf" camel-4.22.0-builds/successful-builds.txt | wc -l)

### CXF Components
- Total CXF builds: $(grep "cxf-" camel-4.22.0-builds/successful-builds.txt | wc -l)

### Transitive Dependencies
- Third-party libraries: $(grep -v "camel\|cxf" camel-4.22.0-builds/successful-builds.txt | wc -l)

## Key Artifacts

### Camel BOMs
- org.apache.camel:camel-bom:4.22.0.redhat-00001

### CXF BOMs
- org.apache.cxf:cxf-bom:4.2.3.redhat-00001

### Core Components
- org.apache.camel:camel-core:4.22.0.redhat-00001
- org.apache.camel:camel-core-engine:4.22.0.redhat-00001
- org.apache.camel:camel-api:4.22.0.redhat-00001

## Failed Builds

$(cat camel-4.22.0-builds/failed-builds.txt)

## Next Steps

1. Retry failed builds after fixing issues
2. Update downstream products to use Camel 4.22.0
3. Run integration tests
4. Create release notes

EOF

cat camel-4.22.0-builds/FINAL_REPORT.md
```

---

### Step 7.2: Create Reusable Scripts

**Objective**: Package scripts for future Camel builds.

**Files to Create**:
1. `build-camel-version.sh` - Automated build script for any Camel version
2. `verify-camel-build.sh` - Verification script
3. `retry-failed-builds.sh` - Retry logic for failures

---

## Appendix A: Key Camel 4.22.0 Components

### Core Components (Build First)
1. camel-api
2. camel-util
3. camel-base
4. camel-core-engine
5. camel-core
6. camel-support

### Essential Components
1. camel-bean
2. camel-direct
3. camel-file
4. camel-http
5. camel-kafka
6. camel-rest
7. camel-jackson
8. camel-jaxb

### CXF Components
1. camel-cxf-common
2. camel-cxf-soap
3. camel-cxf-rest
4. camel-cxf-transport

### Data Format Components
1. camel-csv
2. camel-json
3. camel-xml
4. camel-avro
5. camel-protobuf

---

## Appendix B: CXF 4.2.3 Components

### Core CXF Modules
1. cxf-core
2. cxf-rt-frontend-jaxws
3. cxf-rt-transports-http
4. cxf-rt-bindings-soap
5. cxf-rt-ws-security
6. cxf-rt-features-logging

---

## Appendix C: Common Issues & Solutions

### Issue 1: SCM Resolution Failures

**Problem**: Cannot resolve SCM URL for artifact

**Solution**:
```bash
# Add to lib/scm_resolver.sh
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

### Issue 2: Build Failures Due to Missing Dependencies

**Problem**: Build fails because dependency not yet built

**Solution**:
1. Check dependency-edges.txt for build order
2. Ensure dependencies built first
3. Retry build after dependencies complete

---

### Issue 3: Test Failures

**Problem**: Tests fail during build

**Solution**:
```bash
# Use -DskipTests in build script
buildScript: "mvn -DskipTests clean deploy -B"
```

---

## Appendix D: Useful Commands Reference

### Query PNC Builds
```bash
# List all Camel builds
bacon pnc build list --query="buildConfigName==*camel*"

# Check specific build status
bacon pnc build get <build-id>

# View build logs
bacon pnc build logs <build-id>
```

### Maven Repository Checks
```bash
# Check if artifact exists
mvn dependency:get \
  -DgroupId=org.apache.camel \
  -DartifactId=camel-core \
  -Dversion=4.22.0.redhat-00001

# Download artifact
mvn dependency:copy \
  -Dartifact=org.apache.camel:camel-core:4.22.0.redhat-00001 \
  -DoutputDirectory=./downloads
```

### Dependency Analysis
```bash
# Show dependency tree
mvn dependency:tree

# Show dependency conflicts
mvn dependency:tree -Dverbose

# Analyze dependencies
mvn dependency:analyze
```

---

## Timeline Estimate

### Phase 1: Initial Builds (Camel & CXF Core)
- **Duration**: 2-4 hours
- **Effort**: Setup + 2 builds

### Phase 2: Camel Components Analysis
- **Duration**: 4-6 hours
- **Effort**: Analysis + config generation

### Phase 3: Transitive Dependencies Analysis
- **Duration**: 6-8 hours
- **Effort**: Full dependency tree + config generation

### Phase 4: Build Order & Dependency Management
- **Duration**: 2-3 hours
- **Effort**: Topological sort + PIG config

### Phase 5: PNC Build Execution
- **Duration**: 24-48 hours
- **Effort**: Batch builds + monitoring (mostly automated)

### Phase 6: Verification & Validation
- **Duration**: 4-6 hours
- **Effort**: Verification + failure handling

### Phase 7: Documentation & Handoff
- **Duration**: 2-3 hours
- **Effort**: Report generation + documentation

**Total Estimated Time**: 3-5 days (including build execution time)

---

## Success Criteria

- ✅ Camel 4.22.0 BOM built successfully
- ✅ CXF 4.2.3 BOM built successfully
- ✅ All Camel components built (200-300 artifacts)
- ✅ All CXF components built (50-80 artifacts)
- ✅ All transitive dependencies built (500-1000+ artifacts)
- ✅ All artifacts available in Maven repository with .redhat-00001 suffix
- ✅ No circular dependencies
- ✅ Build order documented
- ✅ Failure rate < 5%

---

## Contact & Support

For issues or questions during the build process:
1. Check build logs in PNC
2. Review this document's troubleshooting section
3. Consult with PNC team for infrastructure issues
4. Review Camel/CXF documentation for component-specific issues

---

**Document Version**: 1.0  
**Last Updated**: 2026-08-13  
**Author**: Build Automation Team
