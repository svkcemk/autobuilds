# Apache Camel Analysis Guide for PNC Builds

## Best Way to Analyze Apache Camel Dependencies

### Quick Answer

The best way to analyze Camel depends on your goal:

1. **For Camel Quarkus** (your current config):
   ```bash
   # Use the correct BOM
   analyzeBOM: org.apache.camel.quarkus:camel-quarkus-bom:3.33.0
   ```

2. **For Core Camel**:
   ```bash
   analyzeBOM: org.apache.camel:camel-bom:4.18.1
   ```

3. **For Camel Spring Boot**:
   ```bash
   analyzeBOM: org.apache.camel.springboot:camel-spring-boot-bom:4.18.1
   ```

### Problem with Current Config

Your build-config.yaml has:
```yaml
analyzeBOM: org.apache.camel:camel-parent:4.18.1  # This is wrong!
```

**Issue**: `camel-parent` is a parent POM, not a BOM. It doesn't define dependencies.

**Fix**: Change to the actual BOM:
```yaml
analyzeBOM: org.apache.camel.quarkus:camel-quarkus-bom:3.33.0
```

### Recommended Analysis Strategies

#### Strategy 1: Core Components Only (Recommended for Starting)

```yaml
dependencyResolutionConfig:
  analyzeBOM: org.apache.camel.quarkus:camel-quarkus-bom:3.33.0
  includeArtifacts:
    # Core Camel
    - org.apache.camel:camel-core:*
    - org.apache.camel:camel-core-engine:*
    - org.apache.camel:camel-api:*
    - org.apache.camel:camel-support:*
    
    # Essential components
    - org.apache.camel:camel-bean:*
    - org.apache.camel:camel-direct:*
    - org.apache.camel:camel-http:*
    - org.apache.camel:camel-kafka:*
    - org.apache.camel:camel-rest:*
    
    # CXF
    - org.apache.cxf:*:*
```

#### Strategy 2: All Camel with Smart Exclusions (Your Current Approach)

Your current exclusion list is excellent! Just fix the BOM:

```yaml
dependencyResolutionConfig:
  analyzeBOM: org.apache.camel.quarkus:camel-quarkus-bom:3.33.0  # Fixed!
  includeArtifacts:
    - org.apache.camel:*:*
    - org.apache.cxf:*:*
  excludeArtifacts:
    # Keep all your existing exclusions - they're good!
```

#### Strategy 3: By Component Category

Analyze specific categories:

**Messaging:**
```yaml
includeArtifacts:
  - org.apache.camel:camel-kafka:*
  - org.apache.camel:camel-jms:*
  - org.apache.camel:camel-amqp:*
```

**HTTP/REST:**
```yaml
includeArtifacts:
  - org.apache.camel:camel-http:*
  - org.apache.camel:camel-rest:*
  - org.apache.camel:camel-servlet:*
```

**Data Formats:**
```yaml
includeArtifacts:
  - org.apache.camel:camel-jackson:*
  - org.apache.camel:camel-jaxb:*
  - org.apache.camel:camel-csv:*
```

### Step-by-Step: Fix and Analyze Camel

```bash
# 1. Fix the BOM in build-config.yaml
sed -i.bak 's/camel-parent:4.18.1/camel-quarkus-bom:3.33.0/' build-config.yaml

# 2. Validate
./validate_config.sh

# 3. Dry run to preview
./generate_transitive_builds.sh --dry-run --verbose

# 4. Generate configs
./generate_transitive_builds.sh --output ./camel-builds

# 5. Review results
cat camel-builds/build-report.txt
cat camel-builds/filtered-dependencies.txt | head -20
```

### What Makes Camel Analysis Challenging

1. **300+ Components**: Camel has over 300 components
2. **Many Exclusions Needed**: Cloud providers, deprecated, native builds
3. **Transitive Dependencies**: Each component brings many dependencies
4. **Multiple BOMs**: Core, Spring Boot, Quarkus each have different BOMs

### Your Current Config Analysis

**Good Points:**
- ✅ Excellent exclusion list (300+ patterns)
- ✅ Excludes cloud providers (AWS, Azure, Google)
- ✅ Excludes problematic components
- ✅ Includes CXF components

**Issues:**
- ❌ Wrong BOM (camel-parent instead of camel-quarkus-bom)
- ❌ This causes 0 dependencies to be found

### Recommended Fix for Your Config

```bash
# Quick fix - update line 2 of build-config.yaml
# Change from:
analyzeBOM: org.apache.camel:camel-parent:4.18.1

# Change to:
analyzeBOM: org.apache.camel.quarkus:camel-quarkus-bom:3.33.0
```

### Expected Results After Fix

After fixing the BOM, you should see:
- **Total Dependencies**: 500-1000+ (depending on BOM)
- **After Filtering**: 50-200 (with your exclusions)
- **Build Configs**: 50-200 YAML files

### Priority Components to Build

**High Priority** (build these first):
1. camel-core, camel-core-engine, camel-api
2. camel-http, camel-rest
3. camel-kafka
4. camel-jackson
5. camel-bean, camel-direct

**Medium Priority**:
- camel-sql, camel-jdbc
- camel-ftp, camel-file
- camel-mail
- camel-cxf

**Low Priority**:
- Specialized connectors
- Cloud-specific components
- Deprecated components

### Advanced: Analyze Camel Component Usage

Create a script to see which components are most used:

```bash
#!/bin/bash
# analyze_camel_usage.sh

echo "Analyzing Camel component dependencies..."

# Get all Camel components
grep "org.apache.camel:" generated-configs/all-dependencies.txt | \
  cut -d: -f2 | \
  sort | uniq -c | \
  sort -rn > camel-component-usage.txt

echo "Top 20 Camel components by dependency count:"
head -20 camel-component-usage.txt
```

### Troubleshooting

**Problem: 0 dependencies found**
- Solution: Fix the BOM (use camel-quarkus-bom, not camel-parent)

**Problem: Too many dependencies (1000+)**
- Solution: Add more exclusions or use specific includes

**Problem: Missing expected components**
- Solution: Check if they're in excludeArtifacts list

**Problem: Build configs have wrong SCM URLs**
- Solution: Add SCM mappings to build-config.yaml

### Next Steps

1. Fix the BOM in build-config.yaml
2. Run: `./generate_transitive_builds.sh --output ./camel-builds`
3. Review: `cat camel-builds/build-report.txt`
4. Adjust includes/excludes as needed
5. Generate final configs
6. Create builds in PNC using bacon CLI

### Quick Commands

```bash
# Fix BOM and regenerate
sed -i.bak 's/camel-parent:4.18.1/camel-quarkus-bom:3.33.0/' build-config.yaml
./generate_transitive_builds.sh --output ./camel-builds-fixed

# See what changed
diff generated-configs/build-report.txt camel-builds-fixed/build-report.txt

# List all Camel components found
grep "org.apache.camel:" camel-builds-fixed/filtered-dependencies.txt | \
  cut -d: -f2 | sort -u
```
