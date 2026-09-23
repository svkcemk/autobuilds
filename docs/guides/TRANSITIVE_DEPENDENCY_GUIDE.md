# Transitive Dependency Handling Guide

## Overview

This guide explains how the PNC build config generator handles **transitive dependencies** - dependencies of dependencies that are pulled in automatically by Maven.

## What Are Transitive Dependencies?

When you declare a dependency in your POM, Maven automatically includes its dependencies too. For example:

```
Your Project
└── camel-amqp:4.18.1 (direct dependency)
    ├── qpid-jms-client:2.5.0 (transitive - dependency of camel-amqp)
    │   ├── netty-handler:4.1.100 (transitive - dependency of qpid-jms)
    │   ├── netty-buffer:4.1.100 (transitive)
    │   └── slf4j-api:2.0.9 (transitive)
    └── camel-core:4.18.1 (transitive)
        └── camel-api:4.18.1 (transitive)
```

## How the Tool Handles Transitive Dependencies

### Step 1: Generate Full Dependency Tree

Use Maven to get the complete dependency tree including all transitive dependencies:

```bash
# Navigate to your project with BOM
cd /path/to/camel-bom

# Generate full dependency tree
mvn dependency:tree -DoutputFile=full-deps.txt -DoutputType=text

# Or with specific scope
mvn dependency:tree -DoutputFile=full-deps.txt -Dscope=compile
```

**Example Output Format:**
```
[INFO] org.apache.camel:camel-bom:pom:4.18.1
[INFO] +- org.apache.camel:camel-amqp:jar:4.18.1:compile
[INFO] |  +- org.apache.qpid:qpid-jms-client:jar:2.5.0:compile
[INFO] |  |  +- io.netty:netty-handler:jar:4.1.100.Final:compile
[INFO] |  |  |  +- io.netty:netty-buffer:jar:4.1.100.Final:compile
[INFO] |  |  |  \- io.netty:netty-transport:jar:4.1.100.Final:compile
[INFO] |  |  \- org.slf4j:slf4j-api:jar:2.0.9:compile
[INFO] |  \- org.apache.camel:camel-core:jar:4.18.1:compile
[INFO] +- org.apache.camel:camel-kafka:jar:4.18.1:compile
[INFO] |  +- org.apache.kafka:kafka-clients:jar:3.6.0:compile
[INFO] |  |  +- com.github.luben:zstd-jni:jar:1.5.5-6:compile
[INFO] |  |  \- org.lz4:lz4-java:jar:1.8.0:compile
```

### Step 2: Parse and Extract All Dependencies

The tool automatically:

1. **Parses the tree structure** - Understands Maven's tree format with `+-|\` characters
2. **Extracts all levels** - Gets direct AND transitive dependencies
3. **Deduplicates** - Removes duplicate versions
4. **Categorizes** - Separates direct vs transitive

```bash
# Run the analysis
./generate_transitive_builds.sh full-deps.txt output/

# This processes:
# - Direct: camel-amqp, camel-kafka
# - Transitive L1: qpid-jms-client, kafka-clients, camel-core
# - Transitive L2: netty-handler, zstd-jni, lz4-java
# - Transitive L3+: netty-buffer, netty-transport
```

### Step 3: Filter Against PNC

The tool checks each dependency (direct AND transitive) against PNC:

```bash
# For each dependency found:
bacon pnc build-config list --query "name==qpid-jms-client-2.5.0"

# If found in PNC: Skip (already built)
# If NOT found: Generate build config
```

### Step 4: Generate Build Configs

Build configs are generated for ALL dependencies not in PNC:

```yaml
# Example: Transitive dependency config
name: qpid-jms-client-2.5.0
description: "Build for qpid-jms-client 2.5.0 (transitive dependency of camel-amqp)"
scmRepository:
  url: "https://github.com/apache/qpid-jms.git"
  revision: "2.5.0"
buildScript: "mvn clean deploy -DskipTests"
environment:
  name: "OpenJDK 11"
buildType: MVN
dependencies:
  - netty-handler-4.1.100  # Its own transitive deps
  - slf4j-api-2.0.9
```

## Real-World Example: Camel BOM

### Input: Camel BOM with 200+ components

```bash
# Get full tree
cd camel-bom
mvn dependency:tree -DoutputFile=camel-full-tree.txt

# Analyze
./generate_transitive_builds.sh camel-full-tree.txt camel-builds/
```

### Output: Complete Build Configs

```
Processing dependencies...
✓ Found 1,247 total dependencies
  - 203 direct dependencies (Camel components)
  - 1,044 transitive dependencies (third-party libs)

Checking PNC...
✓ 892 already built in PNC
✗ 355 need build configs

Generating configs...
✓ Created 355 build configs:
  - 203 for Camel components
  - 152 for transitive dependencies
    * 45 Apache Commons libraries
    * 38 Netty modules
    * 27 Jackson modules
    * 42 other third-party libs
```

## Dependency Levels Explained

### Level 0: Direct Dependencies
```
org.apache.camel:camel-amqp:4.18.1
org.apache.camel:camel-kafka:4.18.1
```
These are explicitly in your BOM.

### Level 1: First-Level Transitive
```
org.apache.qpid:qpid-jms-client:2.5.0  (from camel-amqp)
org.apache.kafka:kafka-clients:3.6.0   (from camel-kafka)
```
Direct dependencies of your direct dependencies.

### Level 2+: Deep Transitive
```
io.netty:netty-handler:4.1.100         (from qpid-jms-client)
com.github.luben:zstd-jni:1.5.5-6      (from kafka-clients)
```
Dependencies of transitive dependencies (can go many levels deep).

## Advanced Usage

### Filter by Scope

```bash
# Only compile scope (excludes test dependencies)
mvn dependency:tree -Dscope=compile -DoutputFile=compile-deps.txt
./generate_transitive_builds.sh compile-deps.txt

# Only runtime scope
mvn dependency:tree -Dscope=runtime -DoutputFile=runtime-deps.txt
./generate_transitive_builds.sh runtime-deps.txt
```

### Exclude Certain Groups

```bash
# Exclude already-built groups
mvn dependency:tree \
  -Dexcludes=org.apache.camel:*,io.quarkus:* \
  -DoutputFile=external-deps.txt

./generate_transitive_builds.sh external-deps.txt
```

### Generate PiG Config with Dependencies

```bash
# Generate single PiG YAML with all transitive deps
./generate_pig_config.sh camel-full-tree.txt camel-pig.yaml

# The PiG config will include dependency relationships:
# builds:
#   - name: qpid-jms-client-2.5.0
#     dependencies:
#       - netty-handler-4.1.100
#       - slf4j-api-2.0.9
#   - name: camel-amqp-4.18.1
#     dependencies:
#       - qpid-jms-client-2.5.0
#       - camel-core-4.18.1
```

## Verification

### Check What Was Found

```bash
# View all dependencies
cat output/all-dependencies.txt

# View only transitive
cat output/transitive-only.txt

# View dependency tree
cat output/dependency-tree.txt
```

### Validate Completeness

```bash
# Count dependencies at each level
grep "^[^|+-]" full-deps.txt | wc -l  # Direct
grep "^|  " full-deps.txt | wc -l     # Level 1
grep "^|  |  " full-deps.txt | wc -l  # Level 2
```

## Common Scenarios

### Scenario 1: Build Entire Product Stack

```bash
# Get everything
mvn dependency:tree -DoutputFile=all.txt
./generate_transitive_builds.sh all.txt
# Result: Configs for ALL dependencies
```

### Scenario 2: Only Third-Party Dependencies

```bash
# Exclude your own groupId
mvn dependency:tree -Dexcludes=org.apache.camel:* -DoutputFile=third-party.txt
./generate_transitive_builds.sh third-party.txt
# Result: Only external library configs
```

### Scenario 3: Incremental Builds

```bash
# Get new dependencies since last build
mvn dependency:tree -DoutputFile=current.txt
diff previous.txt current.txt > new-deps.txt
./generate_transitive_builds.sh new-deps.txt
# Result: Only new dependency configs
```

## Troubleshooting

### Issue: Too Many Dependencies

**Solution:** Filter by scope or exclude groups
```bash
mvn dependency:tree -Dscope=compile -Dexcludes=org.slf4j:*,junit:*
```

### Issue: Circular Dependencies

**Solution:** Maven handles this automatically. The tool will deduplicate.

### Issue: Version Conflicts

**Solution:** Use dependency management to enforce versions
```bash
mvn dependency:tree -Dverbose
# Shows conflict resolution
```

## Summary

✅ **The tool FULLY supports transitive dependencies**  
✅ **Processes entire dependency tree automatically**  
✅ **Handles dependencies at any depth level**  
✅ **Filters against PNC to avoid duplicates**  
✅ **Generates configs for all missing dependencies**  
✅ **Maintains dependency relationships in PiG configs**

## Next Steps

1. Generate your full dependency tree:
   ```bash
   mvn dependency:tree -DoutputFile=deps.txt
   ```

2. Run the build config generator:
   ```bash
   ./generate_transitive_builds.sh deps.txt
   ```

3. Review and submit to PNC:
   ```bash
   bacon pnc build-config create -f output/configs/*.yaml
   ```

The tool is ready to handle your complete transitive dependency tree!