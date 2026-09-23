# Camel 4.22.0 Transitive Dependencies Build Guide

## Overview

Since you've already built Camel 4.22.0.redhat-00001, this guide focuses specifically on building all transitive dependencies that Camel components require.

---

## What Are Transitive Dependencies?

Transitive dependencies are the libraries that Camel components depend on. For example:

```
camel-kafka:4.22.0
├── kafka-clients:3.x.x (transitive)
│   ├── lz4-java:1.x.x (transitive level 2)
│   └── snappy-java:1.x.x (transitive level 2)
└── camel-core:4.22.0 (already built)
```

---

## Step 1: Analyze Camel 4.22.0 for Transitive Dependencies

### Option A: Analyze from Camel BOM (Recommended)

This analyzes all dependencies declared in the Camel BOM:

```bash
# Create output directory
mkdir -p camel-4.22.0-transitives

# Generate transitive dependency analysis
./generate_build_configs.sh \
  -b org.apache.camel:camel-bom:4.22.0 \
  -c build-config-camel-4.22.0.yaml \
  -o camel-4.22.0-transitives/from-bom \
  --format both \
  --no-pnc \
  -v

# Review what was found
cat camel-4.22.0-transitives/from-bom/build-report.txt
cat camel-4.22.0-transitives/from-bom/third-party-dependencies.txt | head -50
```

**Expected Output**:
- 500-1000+ transitive dependencies
- Third-party libraries (Apache Commons, Netty, Jackson, etc.)
- Dependency graph for build ordering

---

### Option B: Analyze from Specific Components

If you only need transitives for specific Camel components:

```bash
# Create a file with the components you need
cat > camel-components-list.txt <<'EOF'
org.apache.camel:camel-kafka:4.22.0
org.apache.camel:camel-http:4.22.0
org.apache.camel:camel-cxf-soap:4.22.0
org.apache.camel:camel-jackson:4.22.0
org.apache.camel:camel-jaxb:4.22.0
EOF

# Generate transitives for these components
./generate_build_configs.sh \
  -r camel-components-list.txt \
  -c build-config-camel-4.22.0.yaml \
  -o camel-4.22.0-transitives/from-components \
  --format both \
  --no-pnc \
  -v
```

---

### Option C: Full Dependency Tree Analysis

For the most comprehensive analysis, create a Maven project:

```bash
# Create analysis project
mkdir -p camel-4.22.0-transitives/analysis
cd camel-4.22.0-transitives/analysis

# Create pom.xml with all Camel components
cat > pom.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    
    <groupId>com.redhat.analysis</groupId>
    <artifactId>camel-4.22.0-transitive-analysis</artifactId>
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
        
        <!-- Messaging -->
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-kafka</artifactId>
        </dependency>
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-jms</artifactId>
        </dependency>
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-amqp</artifactId>
        </dependency>
        
        <!-- HTTP/REST -->
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-http</artifactId>
        </dependency>
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-rest</artifactId>
        </dependency>
        
        <!-- CXF -->
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-cxf-soap</artifactId>
        </dependency>
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-cxf-rest</artifactId>
        </dependency>
        
        <!-- Data Formats -->
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-jackson</artifactId>
        </dependency>
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-jaxb</artifactId>
        </dependency>
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-csv</artifactId>
        </dependency>
        
        <!-- Database -->
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-sql</artifactId>
        </dependency>
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-jdbc</artifactId>
        </dependency>
    </dependencies>
</project>
EOF

# Generate full dependency tree
mvn dependency:tree \
  -DoutputFile=camel-4.22.0-full-deps.txt \
  -DoutputType=text \
  -Dscope=compile

# Also generate in DOT format for visualization
mvn dependency:tree \
  -DoutputFile=camel-4.22.0-deps.dot \
  -DoutputType=dot

# Return to root
cd ../..

# Now generate build configs from this tree
./generate_build_configs.sh \
  -b org.apache.camel:camel-bom:4.22.0 \
  -c build-config-camel-4.22.0.yaml \
  -o camel-4.22.0-transitives/full-analysis \
  --format both \
  --no-pnc \
  -v
```

---

## Step 2: Filter and Categorize Dependencies

### Identify What's Already Built

```bash
# Check which dependencies are already productized
cat camel-4.22.0-transitives/from-bom/third-party-dependencies.txt | \
while read dep; do
  # Extract GAV
  groupId=$(echo "$dep" | cut -d: -f1)
  artifactId=$(echo "$dep" | cut -d: -f2)
  version=$(echo "$dep" | cut -d: -f3)
  
  # Check if .redhat version exists
  redhat_version="${version}.redhat-00001"
  
  if mvn dependency:get \
    -DgroupId="$groupId" \
    -DartifactId="$artifactId" \
    -Dversion="$redhat_version" \
    -DremoteRepositories="https://maven.repository.redhat.com/ga/" \
    > /dev/null 2>&1; then
    echo "ALREADY_BUILT: $dep"
  else
    echo "NEEDS_BUILD: $dep"
  fi
done > camel-4.22.0-transitives/dependency-status.txt

# Separate into two lists
grep "ALREADY_BUILT:" camel-4.22.0-transitives/dependency-status.txt | \
  cut -d: -f2- > camel-4.22.0-transitives/already-built.txt

grep "NEEDS_BUILD:" camel-4.22.0-transitives/dependency-status.txt | \
  cut -d: -f2- > camel-4.22.0-transitives/needs-build.txt

# Show summary
echo "Already built: $(wc -l < camel-4.22.0-transitives/already-built.txt)"
echo "Needs build: $(wc -l < camel-4.22.0-transitives/needs-build.txt)"
```

---

### Categorize by Library Family

```bash
# Categorize dependencies by groupId
cat camel-4.22.0-transitives/needs-build.txt | \
  cut -d: -f1 | \
  sort | uniq -c | \
  sort -rn > camel-4.22.0-transitives/by-group.txt

# Show top 20 groups
head -20 camel-4.22.0-transitives/by-group.txt

# Common categories you'll see:
# - org.apache.kafka (Kafka clients)
# - io.netty (Netty networking)
# - com.fasterxml.jackson (Jackson JSON)
# - org.apache.commons (Apache Commons)
# - org.apache.cxf (CXF components)
# - org.slf4j (Logging)
```

---

## Step 3: Generate Build Configs for Transitives

### Generate All Transitive Build Configs

```bash
# Generate build configs for all needed transitives
./generate_build_configs.sh \
  -b org.apache.camel:camel-bom:4.22.0 \
  -c build-config-camel-4.22.0.yaml \
  -o camel-4.22.0-transitives/build-configs \
  --format both \
  --no-pnc \
  -v

# Review the output
cat camel-4.22.0-transitives/build-configs/build-report.txt

# Count generated configs
find camel-4.22.0-transitives/build-configs/build-configs -name "*.yaml" | wc -l
```

---

### Generate by Priority Groups

Build in waves based on importance:

#### Wave 1: Core Dependencies (Build First)

```bash
# Create priority list
cat > priority-deps.txt <<'EOF'
org.slf4j:slf4j-api
org.apache.logging.log4j:log4j-api
org.apache.logging.log4j:log4j-core
commons-logging:commons-logging
org.apache.commons:commons-lang3
org.apache.commons:commons-text
com.google.guava:guava
EOF

# Generate configs for priority deps
./generate_build_configs.sh \
  -r priority-deps.txt \
  -c build-config-camel-4.22.0.yaml \
  -o camel-4.22.0-transitives/wave1-core \
  --format both \
  --no-pnc
```

#### Wave 2: Messaging Dependencies

```bash
cat > messaging-deps.txt <<'EOF'
org.apache.kafka:kafka-clients
org.apache.qpid:qpid-jms-client
org.apache.activemq:activemq-client
EOF

./generate_build_configs.sh \
  -r messaging-deps.txt \
  -c build-config-camel-4.22.0.yaml \
  -o camel-4.22.0-transitives/wave2-messaging \
  --format both \
  --no-pnc
```

#### Wave 3: Data Format Dependencies

```bash
cat > dataformat-deps.txt <<'EOF'
com.fasterxml.jackson.core:jackson-core
com.fasterxml.jackson.core:jackson-databind
com.fasterxml.jackson.core:jackson-annotations
com.fasterxml.jackson.dataformat:jackson-dataformat-xml
com.fasterxml.jackson.dataformat:jackson-dataformat-yaml
EOF

./generate_build_configs.sh \
  -r dataformat-deps.txt \
  -c build-config-camel-4.22.0.yaml \
  -o camel-4.22.0-transitives/wave3-dataformat \
  --format both \
  --no-pnc
```

#### Wave 4: Networking Dependencies

```bash
cat > networking-deps.txt <<'EOF'
io.netty:netty-all
io.netty:netty-handler
io.netty:netty-codec
io.netty:netty-transport
io.netty:netty-buffer
EOF

./generate_build_configs.sh \
  -r networking-deps.txt \
  -c build-config-camel-4.22.0.yaml \
  -o camel-4.22.0-transitives/wave4-networking \
  --format both \
  --no-pnc
```

---

## Step 4: Create Dependency Build Order

### Generate Topological Sort

```bash
# Generate dependency graph
./generate_build_configs.sh \
  -b org.apache.camel:camel-bom:4.22.0 \
  -c build-config-camel-4.22.0.yaml \
  -o camel-4.22.0-transitives/ordered \
  --format combined \
  --no-pnc

# Extract build order from dependency edges
cat camel-4.22.0-transitives/ordered/dependency-edges.txt | \
  python3 << 'PYTHON_SCRIPT'
import sys
from collections import defaultdict, deque

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

# Topological sort
queue = deque([node for node in all_nodes if in_degree[node] == 0])
build_order = []

while queue:
    node = queue.popleft()
    build_order.append(node)
    
    for neighbor in edges[node]:
        in_degree[neighbor] -= 1
        if in_degree[neighbor] == 0:
            queue.append(neighbor)

for i, artifact in enumerate(build_order, 1):
    print(f'{i}. {artifact}')
PYTHON_SCRIPT
> camel-4.22.0-transitives/build-order.txt

# Review build order
head -50 camel-4.22.0-transitives/build-order.txt
```

---

## Step 5: Create Builds in PNC

### Batch Create Build Configs

```bash
# Create all transitive build configs in PNC
for config in camel-4.22.0-transitives/build-configs/build-configs/*.yaml; do
  echo "Creating: $(basename $config)"
  bacon pnc build-config create --file "$config" || echo "Failed or already exists"
  sleep 1
done

# Verify creation
bacon pnc build-config list --query="name==*" | grep -E "(kafka|netty|jackson|commons)" | wc -l
```

---

### Execute Builds in Order

```bash
# Create execution script
cat > execute-transitive-builds.sh <<'EOF'
#!/bin/bash

set -e

BUILD_ORDER_FILE="camel-4.22.0-transitives/build-order.txt"
BATCH_SIZE=20
WAIT_TIME=600  # 10 minutes between batches

if [ ! -f "$BUILD_ORDER_FILE" ]; then
  echo "Error: Build order file not found"
  exit 1
fi

mapfile -t BUILD_ORDER < "$BUILD_ORDER_FILE"
total_builds=${#BUILD_ORDER[@]}

echo "Total transitive builds: $total_builds"
echo "Batch size: $BATCH_SIZE"
echo ""

for ((i=0; i<$total_builds; i+=$BATCH_SIZE)); do
  batch_num=$((i / BATCH_SIZE + 1))
  echo "=== Batch $batch_num ==="
  
  # Start builds in this batch
  for ((j=i; j<i+BATCH_SIZE && j<total_builds; j++)); do
    artifact="${BUILD_ORDER[$j]}"
    # Remove line number prefix
    artifact=$(echo "$artifact" | sed 's/^[0-9]*\. //')
    
    # Convert to build config name
    build_name=$(echo "$artifact" | sed 's/:/_/g' | sed 's/\./-/g')
    
    echo "  Starting: $build_name"
    bacon pnc build start "$build_name" 2>/dev/null || echo "    (skipped or failed)"
  done
  
  echo "  Waiting ${WAIT_TIME}s for batch to complete..."
  sleep $WAIT_TIME
  
  # Check batch status
  echo "  Checking batch status..."
  success=0
  failed=0
  building=0
  
  for ((j=i; j<i+BATCH_SIZE && j<total_builds; j++)); do
    artifact="${BUILD_ORDER[$j]}"
    artifact=$(echo "$artifact" | sed 's/^[0-9]*\. //')
    build_name=$(echo "$artifact" | sed 's/:/_/g' | sed 's/\./-/g')
    
    status=$(bacon pnc build list --query="buildConfigName==$build_name" --latest 2>/dev/null | \
             grep -oP 'Status: \K\w+' | head -1 || echo "UNKNOWN")
    
    case "$status" in
      SUCCESS) ((success++)) ;;
      FAILED) ((failed++)) ;;
      BUILDING) ((building++)) ;;
    esac
  done
  
  echo "  Batch $batch_num results: SUCCESS=$success, FAILED=$failed, BUILDING=$building"
  echo ""
done

echo "All transitive builds triggered!"
echo ""
echo "Monitor progress with:"
echo "  watch -n 60 'bacon pnc build list --latest | grep -E \"(SUCCESS|FAILED|BUILDING)\" | sort | uniq -c'"
EOF

chmod +x execute-transitive-builds.sh

# Execute the builds
./execute-transitive-builds.sh
```

---

## Step 6: Monitor and Verify

### Monitor Build Progress

```bash
# Watch overall progress
watch -n 60 'bacon pnc build list --latest | \
             grep -E "(SUCCESS|FAILED|BUILDING)" | \
             sort | uniq -c'

# Check for failures
bacon pnc build list --status FAILED > transitive-failures.txt
cat transitive-failures.txt

# Count successes
bacon pnc build list --status SUCCESS | \
  grep -v "camel-" | \
  wc -l
```

---

### Verify Critical Dependencies

```bash
# Check key transitive dependencies
critical_deps=(
  "org.apache.kafka:kafka-clients"
  "io.netty:netty-handler"
  "com.fasterxml.jackson.core:jackson-databind"
  "org.apache.commons:commons-lang3"
  "org.slf4j:slf4j-api"
)

echo "Verifying critical dependencies..."
for dep in "${critical_deps[@]}"; do
  IFS=':' read -r groupId artifactId <<< "$dep"
  
  # Check if built
  build_name="${groupId}_${artifactId}"
  build_name=$(echo "$build_name" | sed 's/\./-/g')
  
  status=$(bacon pnc build list --query="buildConfigName==$build_name" --latest 2>/dev/null | \
           grep -oP 'Status: \K\w+' | head -1 || echo "NOT_FOUND")
  
  if [ "$status" = "SUCCESS" ]; then
    echo "✓ $dep"
  else
    echo "✗ $dep ($status)"
  fi
done
```

---

## Step 7: Handle Failures and Retries

### Analyze Failures

```bash
# Get detailed failure information
bacon pnc build list --status FAILED | \
while read build_id; do
  echo "=== Build: $build_id ==="
  bacon pnc build logs "$build_id" | tail -100
  echo ""
done > transitive-failure-logs.txt

# Categorize failures
grep -E "(ERROR|FAILED)" transitive-failure-logs.txt | \
  cut -d: -f1-2 | \
  sort | uniq -c | \
  sort -rn > failure-categories.txt

cat failure-categories.txt
```

---

### Retry Failed Builds

```bash
# Create retry script
cat > retry-failed-transitives.sh <<'EOF'
#!/bin/bash

# Get list of failed builds
bacon pnc build list --status FAILED | \
while read build_id; do
  build_name=$(bacon pnc build get "$build_id" | grep "Build Config:" | awk '{print $3}')
  
  echo "Retrying: $build_name"
  bacon pnc build start "$build_name"
  
  sleep 5
done
EOF

chmod +x retry-failed-transitives.sh
./retry-failed-transitives.sh
```

---

## Step 8: Generate Final Report

```bash
# Create comprehensive report
cat > camel-4.22.0-transitives/TRANSITIVE_BUILD_REPORT.md <<'EOF'
# Camel 4.22.0 Transitive Dependencies Build Report

## Summary

- **Analysis Date**: $(date +%Y-%m-%d)
- **Total Transitive Dependencies**: $(cat camel-4.22.0-transitives/from-bom/third-party-dependencies.txt | wc -l)
- **Already Built**: $(wc -l < camel-4.22.0-transitives/already-built.txt)
- **Needed to Build**: $(wc -l < camel-4.22.0-transitives/needs-build.txt)
- **Build Configs Generated**: $(find camel-4.22.0-transitives/build-configs/build-configs -name "*.yaml" | wc -l)

## Build Status

### Successful Builds
$(bacon pnc build list --status SUCCESS | grep -v "camel-" | wc -l) builds completed successfully

### Failed Builds
$(bacon pnc build list --status FAILED | wc -l) builds failed

### Top Dependency Groups

$(head -10 camel-4.22.0-transitives/by-group.txt)

## Critical Dependencies Status

| Dependency | Status |
|------------|--------|
$(for dep in "org.apache.kafka:kafka-clients" "io.netty:netty-handler" "com.fasterxml.jackson.core:jackson-databind"; do
  IFS=':' read -r g a <<< "$dep"
  bn="${g}_${a}"
  bn=$(echo "$bn" | sed 's/\./-/g')
  st=$(bacon pnc build list --query="buildConfigName==$bn" --latest 2>/dev/null | grep -oP 'Status: \K\w+' | head -1 || echo "NOT_FOUND")
  echo "| $dep | $st |"
done)

## Next Steps

1. Retry failed builds
2. Investigate build failures
3. Update dependency versions if needed
4. Verify artifacts in Maven repository

EOF

cat camel-4.22.0-transitives/TRANSITIVE_BUILD_REPORT.md
```

---

## Quick Reference Commands

### Check Status of All Transitives
```bash
bacon pnc build list --latest | \
  grep -v "camel-" | \
  grep -E "(SUCCESS|FAILED|BUILDING)" | \
  sort | uniq -c
```

### List Top 20 Transitive Dependencies
```bash
cat camel-4.22.0-transitives/from-bom/third-party-dependencies.txt | \
  head -20
```

### Find Specific Dependency Build
```bash
# Example: Find kafka-clients build
bacon pnc build list --query="buildConfigName==*kafka-clients*"
```

### Retry All Failed Builds
```bash
bacon pnc build list --status FAILED | \
while read build_id; do
  bacon pnc build start "$build_id"
done
```

---

## Troubleshooting

### Issue: Too Many Dependencies

**Solution**: Build in waves (see Step 3)

### Issue: Circular Dependencies

**Solution**: Check dependency-edges.txt and break cycles manually

### Issue: Build Failures Due to Missing Dependencies

**Solution**: Check build order and ensure dependencies built first

### Issue: SCM Resolution Failures

**Solution**: Add SCM mappings to lib/scm_resolver.sh for common libraries

---

## Expected Timeline

- **Analysis**: 1-2 hours
- **Config Generation**: 2-3 hours
- **PNC Creation**: 2-4 hours
- **Build Execution**: 24-48 hours (automated)
- **Verification**: 4-6 hours

**Total**: 2-3 days

---

## Success Criteria

- ✅ All transitive dependencies identified
- ✅ Build configs generated for all needed dependencies
- ✅ Builds created in PNC
- ✅ >95% build success rate
- ✅ Critical dependencies built successfully
- ✅ Artifacts available in Maven repository

---

**Last Updated**: 2026-08-14
