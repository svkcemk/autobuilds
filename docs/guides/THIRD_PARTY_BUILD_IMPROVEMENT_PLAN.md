# Third-Party Build Improvement Plan for Camel & CEQ Projects

**Version:** 1.0  
**Date:** 2026-08-05  
**Target Projects:** Apache Camel, Community Edition Quarkus (CEQ)  
**Objective:** Enhance autobuilder to efficiently build only missing transitive 3rd party dependencies in PNC

---

## Executive Summary

This plan outlines comprehensive improvements to the autobuilder toolset to optimize building third-party transitive dependencies for large projects like Apache Camel and CEQ. The focus is on building **only** dependencies that lack productized versions in PNC, with significant performance improvements, better filtering, and enhanced reporting.

### Key Improvements

1. **Performance Optimization** - 10x faster for large BOMs (1000+ dependencies)
2. **Recursive BOM Expansion** - Handle nested BOM imports automatically
3. **Smart Filtering** - Exclude test deps, already-productized groups, and duplicates
4. **Parallel Productization Checks** - Concurrent PNC/Indy queries
5. **Enhanced Caching** - Persistent cache for dependency trees and SCM data
6. **Better Reporting** - Detailed build plans with cost estimates

---

## Current State Analysis

### Existing Capabilities ✅

- Basic transitive dependency resolution via Maven
- Productization checking with `--check-productization` flag
- PNC integration via bacon CLI
- Individual and combined YAML output
- Topological sorting for build order
- Basic exclude groups filtering

### Current Limitations ❌

1. **Performance Issues**
   - Sequential productization checks (slow for 500+ deps)
   - No persistent caching between runs
   - Maven resolution can timeout on large BOMs
   - No incremental processing

2. **Filtering Gaps**
   - Cannot exclude test-scoped dependencies
   - No support for excluding already-productized groups (e.g., `io.quarkus.*`)
   - Cannot filter by artifact patterns (e.g., `*-test`, `*-bom`)
   - No deduplication across multiple root artifacts

3. **BOM Handling**
   - No recursive BOM import expansion
   - Cannot detect circular BOM imports
   - Limited support for property resolution in BOMs
   - No BOM version alignment checking

4. **Productization Detection**
   - Only checks exact `.redhat-XXXXX` suffix
   - No wildcard support for finding any productized version
   - No checking of alternative repositories (PSI, Maven Central)
   - No version range checking (e.g., "any 1.x.x.redhat-*")

5. **Reporting**
   - Limited visibility into why artifacts were included/excluded
   - No cost estimation for builds
   - No dependency conflict detection
   - No build time estimation

---

## Improvement Areas

### 1. Performance Optimization

#### 1.1 Parallel Productization Checking

**Current:** Sequential HTTP checks (1-2 seconds per artifact)  
**Proposed:** Parallel batch processing with connection pooling

```bash
# Implementation approach
- Use GNU parallel or xargs for parallel HTTP checks
- Batch size: 20-50 concurrent requests
- Connection pooling to Indy/PNC
- Timeout per request: 5 seconds
- Fallback to sequential on errors
```

**Expected Impact:**
- 500 dependencies: 10 minutes → 2 minutes (5x faster)
- 1000 dependencies: 20 minutes → 4 minutes (5x faster)

#### 1.2 Enhanced Caching System

**Current:** No persistent caching  
**Proposed:** Multi-level cache with TTL

```yaml
cache_structure:
  maven_trees:
    location: ~/.bob/cache/maven-trees/
    ttl: 24h
    key: sha256(gav + bom + excludes)
  
  productization_status:
    location: ~/.bob/cache/productization/
    ttl: 6h
    key: sha256(gav + redhat_suffix)
  
  scm_resolution:
    location: ~/.bob/cache/scm/
    ttl: 7d
    key: sha256(gav)
  
  bom_expansion:
    location: ~/.bob/cache/bom-expansion/
    ttl: 24h
    key: sha256(bom_gav)
```

**Cache Invalidation:**
- Manual: `--clear-cache` flag
- Automatic: TTL expiration
- Smart: Detect version changes in BOMs

**Expected Impact:**
- Second run: 10 minutes → 30 seconds (20x faster)
- Incremental updates: Only check new/changed artifacts

#### 1.3 Incremental Processing

**Current:** Full re-analysis on every run  
**Proposed:** Track processed artifacts and skip unchanged

```bash
# Track state in output directory
output/
  .state/
    last-run.json          # Timestamp, config hash
    processed-artifacts.db # SQLite DB of processed artifacts
    dependency-graph.json  # Cached graph for incremental updates
```

**Features:**
- Detect which artifacts changed since last run
- Only re-analyze changed artifacts and their dependents
- Merge results with previous run
- Support for `--force-full` to override

**Expected Impact:**
- Incremental runs: 10 minutes → 1-2 minutes (5-10x faster)

#### 1.4 Maven Resolution Optimization

**Current:** Single Maven invocation, can timeout  
**Proposed:** Chunked resolution with timeout handling

```bash
# Split large artifact lists into chunks
- Chunk size: 50 artifacts per Maven invocation
- Parallel Maven processes: 2-4 (based on CPU cores)
- Per-chunk timeout: 120 seconds
- Retry failed chunks with smaller size
- Fallback to individual artifact resolution
```

**Expected Impact:**
- Large BOMs (500+ artifacts): Reliable completion
- Reduced timeout failures: 30% → 5%

---

### 2. Smart Filtering Mechanisms

#### 2.1 Enhanced Exclude Patterns

**Current:** Only groupId-based exclusion  
**Proposed:** Multi-dimensional filtering

```yaml
# Enhanced build-config.yaml
dependencyResolutionConfig:
  # Existing: Group-level exclusion
  excludeGroups:
    - org.springframework
    - org.testcontainers
  
  # NEW: Artifact pattern exclusion
  excludeArtifactPatterns:
    - "*-test"           # Test utilities
    - "*-tests"          # Test JARs
    - "*-bom"            # BOM artifacts (not buildable)
    - "*-parent"         # Parent POMs
    - "*-javadoc"        # Documentation
    - "*-sources"        # Source JARs
  
  # NEW: Scope-based exclusion
  excludeScopes:
    - test
    - provided
    - system
  
  # NEW: Already-productized group prefixes
  excludeProductizedGroups:
    - io.quarkus         # Quarkus platform (already productized)
    - org.jboss          # JBoss components (already productized)
    - com.redhat         # Red Hat components (already productized)
  
  # NEW: Classifier-based exclusion
  excludeClassifiers:
    - tests
    - test-jar
    - javadoc
    - sources
```

#### 2.2 Smart Deduplication

**Current:** Basic set-based deduplication  
**Proposed:** Version-aware deduplication with conflict detection

```python
# Deduplication strategy
1. Group by groupId:artifactId
2. For each group:
   - If all versions are same: Keep one
   - If versions differ:
     * Check if all are productized → Keep highest version
     * Check if some are productized → Keep non-productized
     * If none productized → Flag as conflict, keep all
3. Report conflicts for manual resolution
```

**Conflict Resolution Rules:**
```yaml
conflict_resolution:
  strategy: highest_version  # Options: highest_version, lowest_version, manual
  
  # Version comparison rules
  version_priority:
    - prefer_redhat: true    # Prefer .redhat versions
    - prefer_stable: true    # Prefer non-SNAPSHOT
    - prefer_newer: true     # Prefer higher version numbers
```

#### 2.3 Transitive Depth Limiting

**Current:** Includes all transitive dependencies  
**Proposed:** Configurable depth limiting

```yaml
dependencyResolutionConfig:
  # Limit transitive depth (0 = direct only, -1 = unlimited)
  maxTransitiveDepth: 3
  
  # Stop at first productized dependency
  stopAtProductized: true
  
  # Include only if required by multiple artifacts
  minRequiredBy: 2
```

**Use Case:**
- Camel components: Only need direct + 1 level (depth=1)
- Full BOM: Need all transitives (depth=-1)

---

### 3. Recursive BOM Expansion

#### 3.1 BOM Import Detection

**Current:** Single-level BOM expansion  
**Proposed:** Recursive BOM import resolution

```python
# Algorithm
def expand_bom_recursive(bom_gav, max_depth=5, visited=None):
    if visited is None:
        visited = set()
    
    if bom_gav in visited or max_depth == 0:
        return []  # Circular import or depth limit
    
    visited.add(bom_gav)
    
    # Parse BOM POM
    managed_deps = []
    bom_imports = []
    
    for dep in parse_bom(bom_gav):
        if dep.type == "pom" and dep.scope == "import":
            bom_imports.append(dep.gav)
        else:
            managed_deps.append(dep.gav)
    
    # Recursively expand imported BOMs
    for imported_bom in bom_imports:
        managed_deps.extend(
            expand_bom_recursive(imported_bom, max_depth-1, visited)
        )
    
    return deduplicate(managed_deps)
```

#### 3.2 BOM Dependency Graph

**Proposed:** Visualize BOM import hierarchy

```bash
# Generate BOM import graph
./generate_build_configs.sh \
  -b org.apache.camel:camel-bom:4.18.1 \
  --expand-bom \
  --bom-graph output/bom-graph.dot

# Output: Graphviz DOT format
digraph bom_imports {
  "camel-bom:4.18.1" -> "camel-parent:4.18.1"
  "camel-bom:4.18.1" -> "jackson-bom:2.15.3"
  "jackson-bom:2.15.3" -> "jackson-parent:2.15.3"
}
```

#### 3.3 BOM Version Alignment

**Proposed:** Detect version mismatches across BOMs

```yaml
# Example conflict detection
conflicts:
  - artifact: com.fasterxml.jackson.core:jackson-databind
    versions:
      - 2.15.3 (from camel-bom:4.18.1)
      - 2.15.2 (from quarkus-bom:3.2.0)
    resolution: use_highest  # or use_lowest, manual
```

---

### 4. Improved Productization Detection

#### 4.1 Multi-Repository Checking

**Current:** Only checks Indy PNC builds  
**Proposed:** Check multiple repositories in priority order

```yaml
productization_check:
  repositories:
    - name: pnc-builds
      url: https://indy.corp.redhat.com/api/content/maven/hosted/pnc-builds
      priority: 1
      timeout: 5s
    
    - name: psi-builds
      url: https://indy.psi.redhat.com/api/content/maven/group/builds-untested+shared-imports+public
      priority: 2
      timeout: 5s
    
    - name: maven-central-redhat
      url: https://repo1.maven.org/maven2
      priority: 3
      timeout: 3s
      # Only check for .redhat versions
```

#### 4.2 Wildcard Suffix Support

**Current:** Exact suffix match only  
**Proposed:** Wildcard and range support

```bash
# Find any .redhat version
--redhat-suffix "redhat-*"

# Find specific range
--redhat-suffix "redhat-0000[1-5]"

# Find latest
--redhat-suffix "redhat-latest"
```

**Implementation:**
```python
def find_productized_version(gav, suffix_pattern):
    if suffix_pattern == "redhat-*":
        # Try common suffixes in order
        for num in range(1, 100):
            for fmt in ["%05d", "%04d"]:
                test_suffix = f"redhat-{fmt % num}"
                if check_exists(gav, test_suffix):
                    return test_suffix
    elif suffix_pattern == "redhat-latest":
        # Query repository metadata for latest
        return find_latest_redhat_version(gav)
    else:
        # Exact match
        return suffix_pattern if check_exists(gav, suffix_pattern) else None
```

#### 4.3 Version Range Checking

**Proposed:** Check if any version in range is productized

```bash
# Check if any 1.x.x version is productized
--check-version-range "1.x.x.redhat-*"

# Use case: If commons-io:2.11.0 is not productized,
# but commons-io:2.10.0.redhat-00001 exists,
# we might not need to build 2.11.0
```

#### 4.4 Productization Status Cache

**Proposed:** Cache productization status with TTL

```json
{
  "commons-io:commons-io:2.11.0": {
    "productized": false,
    "checked_at": "2026-08-05T12:00:00Z",
    "checked_suffixes": ["redhat-00001", "redhat-00002"],
    "ttl": 21600
  },
  "org.apache.camel:camel-core:4.18.1": {
    "productized": true,
    "version": "4.18.1.redhat-00001",
    "repository": "pnc-builds",
    "checked_at": "2026-08-05T12:00:00Z",
    "ttl": 21600
  }
}
```

---

### 5. Enhanced Reporting

#### 5.1 Detailed Build Plan Report

**Proposed:** Comprehensive report with actionable insights

```markdown
# Build Plan Report
Generated: 2026-08-05 12:00:00 UTC
Root Artifact: org.apache.camel:camel-kafka:4.18.1
BOM: org.apache.camel:camel-bom:4.18.1

## Summary
- Total Dependencies Analyzed: 523
- Third-Party Dependencies: 187
- Already Productized: 142 (75.9%)
- Need to Build: 45 (24.1%)
- Excluded by Filters: 336

## Productization Status

### Already Productized (142)
| Artifact | Version | Productized Version | Repository |
|----------|---------|---------------------|------------|
| commons-io:commons-io | 2.11.0 | 2.11.0.redhat-00001 | pnc-builds |
| ... | ... | ... | ... |

### Need to Build (45)
| Artifact | Version | Reason | Estimated Build Time |
|----------|---------|--------|---------------------|
| com.example:lib-a | 1.0.0 | Not productized | 5 min |
| com.example:lib-b | 2.0.0 | Not productized | 8 min |
| ... | ... | ... | ... |

**Total Estimated Build Time:** 3.5 hours

## Filtering Details

### Excluded by Group (250)
- org.springframework.*: 120 artifacts
- org.testcontainers.*: 80 artifacts
- junit.*: 50 artifacts

### Excluded by Pattern (50)
- *-test: 30 artifacts
- *-bom: 20 artifacts

### Excluded by Scope (36)
- test: 30 artifacts
- provided: 6 artifacts

## Dependency Conflicts
| Artifact | Versions | Resolution |
|----------|----------|------------|
| jackson-databind | 2.15.2, 2.15.3 | Use 2.15.3 (highest) |

## Build Order (Topological Sort)
1. commons-io:commons-io:2.11.0
2. com.example:lib-a:1.0.0 (depends on commons-io)
3. com.example:lib-b:2.0.0 (depends on lib-a)
...

## Recommendations
- ✓ All dependencies have resolved SCM URLs
- ⚠ 3 artifacts have version conflicts (see above)
- ⚠ 5 artifacts may require manual build script adjustment
- ℹ Consider excluding org.springframework.* (already in Quarkus platform)
```

#### 5.2 Cost Estimation

**Proposed:** Estimate build time and resource costs

```python
# Build time estimation model
def estimate_build_time(artifact):
    base_time = 5  # minutes
    
    # Adjust based on artifact size (LOC)
    if artifact.lines_of_code > 10000:
        base_time += 5
    
    # Adjust based on dependencies
    base_time += len(artifact.dependencies) * 0.5
    
    # Adjust based on build type
    if artifact.build_type == "MVN":
        base_time *= 1.0
    elif artifact.build_type == "GRADLE":
        base_time *= 1.2
    
    return base_time

# Resource cost estimation
def estimate_resource_cost(artifacts):
    total_time = sum(estimate_build_time(a) for a in artifacts)
    
    # PNC resource costs (example)
    cost_per_hour = 10  # arbitrary units
    total_cost = (total_time / 60) * cost_per_hour
    
    return {
        "total_time_minutes": total_time,
        "total_time_hours": total_time / 60,
        "estimated_cost": total_cost,
        "parallel_time_hours": total_time / (60 * 4)  # Assume 4 parallel builds
    }
```

#### 5.3 Dependency Visualization

**Proposed:** Generate dependency graphs

```bash
# Generate dependency graph
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  --generate-graph output/dependency-graph.dot

# Convert to image
dot -Tpng output/dependency-graph.dot -o output/dependency-graph.png
```

**Graph Types:**
1. **Full Dependency Graph** - All transitive dependencies
2. **Build Order Graph** - Topological sort visualization
3. **Conflict Graph** - Version conflicts highlighted
4. **BOM Import Graph** - BOM hierarchy

---

## Implementation Plan

### Phase 1: Performance Optimization (Week 1-2)

**Priority:** HIGH  
**Effort:** Medium

#### Tasks:
1. ✅ Implement parallel productization checking
   - Use GNU parallel or Python multiprocessing
   - Batch size: 20-50 concurrent requests
   - Add progress bar for user feedback

2. ✅ Add persistent caching system
   - Create cache manager library
   - Implement TTL-based expiration
   - Add `--clear-cache` flag

3. ✅ Optimize Maven resolution
   - Implement chunked resolution
   - Add timeout handling
   - Add retry logic

4. ✅ Add incremental processing
   - Track processed artifacts in SQLite
   - Detect changes since last run
   - Merge results intelligently

**Deliverables:**
- `lib/cache_manager.sh` - Cache management library
- `lib/parallel_processor.sh` - Parallel processing utilities
- Updated `generate_build_configs.sh` with `--use-cache` flag
- Performance benchmarks document

**Success Criteria:**
- 5x faster for 500+ dependencies
- 20x faster on cached runs
- <5% timeout failures

---

### Phase 2: Smart Filtering (Week 3)

**Priority:** HIGH  
**Effort:** Low-Medium

#### Tasks:
1. ✅ Enhance exclude patterns
   - Add artifact pattern exclusion
   - Add scope-based exclusion
   - Add classifier exclusion

2. ✅ Implement smart deduplication
   - Version-aware deduplication
   - Conflict detection
   - Configurable resolution strategies

3. ✅ Add transitive depth limiting
   - Configurable max depth
   - Stop at productized dependencies
   - Min required-by threshold

**Deliverables:**
- Enhanced `build-config.yaml` schema
- Updated `lib/dependency_analyzer.sh`
- Filtering documentation

**Success Criteria:**
- Reduce false positives by 80%
- Clear conflict reporting
- Configurable filtering rules

---

### Phase 3: Recursive BOM Expansion (Week 4)

**Priority:** MEDIUM  
**Effort:** Medium-High

#### Tasks:
1. ✅ Implement recursive BOM parser
   - Detect BOM imports
   - Recursive expansion with cycle detection
   - Property resolution across BOMs

2. ✅ Add BOM dependency graph
   - Generate DOT format graph
   - Visualize BOM hierarchy
   - Detect circular imports

3. ✅ Implement version alignment
   - Detect version conflicts across BOMs
   - Configurable resolution strategies
   - Report mismatches

**Deliverables:**
- `lib/bom_expander.sh` - BOM expansion library
- `--expand-bom-recursive` flag
- BOM graph generation
- Version alignment report

**Success Criteria:**
- Handle 5+ levels of BOM imports
- Detect all circular imports
- Accurate version conflict detection

---

### Phase 4: Improved Productization Detection (Week 5)

**Priority:** MEDIUM  
**Effort:** Medium

#### Tasks:
1. ✅ Multi-repository checking
   - Check PNC, PSI, Maven Central
   - Configurable repository priority
   - Parallel repository queries

2. ✅ Wildcard suffix support
   - `redhat-*` pattern matching
   - `redhat-latest` detection
   - Range-based checking

3. ✅ Version range checking
   - Check if any version in range is productized
   - Suggest alternative versions
   - Smart version selection

**Deliverables:**
- Enhanced productization checker
- Multi-repository configuration
- Wildcard pattern support

**Success Criteria:**
- Find 95%+ of productized versions
- <3 seconds per artifact check
- Accurate latest version detection

---

### Phase 5: Enhanced Reporting (Week 6)

**Priority:** LOW-MEDIUM  
**Effort:** Medium

#### Tasks:
1. ✅ Detailed build plan report
   - Comprehensive summary
   - Filtering details
   - Conflict resolution
   - Build order

2. ✅ Cost estimation
   - Build time estimation
   - Resource cost calculation
   - Parallel build optimization

3. ✅ Dependency visualization
   - Generate DOT graphs
   - Multiple graph types
   - Interactive HTML reports

**Deliverables:**
- Enhanced report generator
- Cost estimation model
- Graph generation utilities
- HTML report template

**Success Criteria:**
- Actionable insights in reports
- Accurate cost estimates (±20%)
- Clear visualizations

---

## Configuration Examples

### Example 1: Camel Component with Aggressive Filtering

```yaml
# camel-config.yaml
dependencyResolutionConfig:
  # Exclude already-productized groups
  excludeGroups:
    - org.springframework
    - org.testcontainers
    - io.quarkus
    - org.jboss
  
  # Exclude test artifacts
  excludeArtifactPatterns:
    - "*-test"
    - "*-tests"
    - "*-bom"
  
  # Exclude test scope
  excludeScopes:
    - test
    - provided
  
  # Only include Camel and direct dependencies
  includeArtifacts:
    - org.apache.camel:*:*
    - org.apache.camel.quarkus:*:*
  
  # Limit transitive depth
  maxTransitiveDepth: 2
  
  # Stop at productized dependencies
  stopAtProductized: true

productization_check:
  # Check multiple repositories
  repositories:
    - name: pnc-builds
      url: https://indy.corp.redhat.com/api/content/maven/hosted/pnc-builds
    - name: psi-builds
      url: https://indy.psi.redhat.com/api/content/maven/group/builds-untested+shared-imports+public
  
  # Use wildcard to find any productized version
  suffix_pattern: "redhat-*"
  
  # Cache results for 6 hours
  cache_ttl: 21600

performance:
  # Enable parallel processing
  parallel_workers: 20
  
  # Enable caching
  use_cache: true
  cache_dir: ~/.bob/cache
  
  # Enable incremental processing
  incremental: true
```

**Usage:**
```bash
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  -b org.apache.camel:camel-bom:4.18.1 \
  -c camel-config.yaml \
  --check-productization \
  --expand-bom-recursive \
  --parallel 20 \
  --use-cache \
  -o ./camel-kafka-output
```

### Example 2: CEQ Full BOM Expansion

```yaml
# ceq-config.yaml
dependencyResolutionConfig:
  # Minimal exclusions (we want most dependencies)
  excludeGroups:
    - org.testcontainers
  
  excludeScopes:
    - test
  
  # No depth limit (full transitive)
  maxTransitiveDepth: -1
  
  # Don't stop at productized (we want full tree)
  stopAtProductized: false

bom_expansion:
  # Enable recursive expansion
  recursive: true
  max_depth: 10
  
  # Detect circular imports
  detect_cycles: true
  
  # Version alignment
  align_versions: true
  conflict_resolution: highest_version

productization_check:
  suffix_pattern: "redhat-*"
  check_version_range: true
  
performance:
  parallel_workers: 50
  use_cache: true
  incremental: true
```

**Usage:**
```bash
./generate_build_configs.sh \
  -b com.redhat.quarkus.platform:quarkus-camel-bom:3.2.0.redhat-00001 \
  -c ceq-config.yaml \
  --expand-bom-recursive \
  --check-productization \
  --parallel 50 \
  --use-cache \
  --generate-report \
  --generate-graph \
  -o ./ceq-output
```

---

## Testing Strategy

### Unit Tests

```bash
# Test individual components
tests/
  test_cache_manager.sh
  test_parallel_processor.sh
  test_bom_expander.sh
  test_productization_checker.sh
  test_filtering.sh
```

### Integration Tests

```bash
# Test full workflows
integration_tests/
  test_camel_component.sh      # Single Camel component
  test_camel_bom.sh            # Full Camel BOM
  test_ceq_bom.sh              # CEQ BOM
  test_large_bom.sh            # 1000+ dependencies
  test_circular_bom.sh         # Circular BOM imports
```

### Performance Benchmarks

```bash
# Benchmark different scenarios
benchmarks/
  benchmark_sequential_vs_parallel.sh
  benchmark_cache_hit_rate.sh
  benchmark_incremental_processing.sh
  benchmark_large_bom.sh
```

**Target Metrics:**
- 500 deps: <2 minutes (with cache: <30 seconds)
- 1000 deps: <4 minutes (with cache: <1 minute)
- Cache hit rate: >80% on second run
- Productization accuracy: >95%

---

## Migration Guide

### For Existing Users

#### Step 1: Update Configuration

```bash
# Backup existing config
cp build-config.yaml build-config.yaml.backup

# Add new configuration sections
cat >> build-config.yaml <<EOF

# NEW: Enhanced filtering
dependencyResolutionConfig:
  excludeArtifactPatterns:
    - "*-test"
    - "*-tests"
  excludeScopes:
    - test
  maxTransitiveDepth: -1
  stopAtProductized: false

# NEW: Performance settings
performance:
  parallel_workers: 20
  use_cache: true
  cache_dir: ~/.bob/cache
  incremental: true

# NEW: Productization settings
productization_check:
  suffix_pattern: "redhat-*"
  repositories:
    - name: pnc-builds
      url: https://indy.corp.redhat.com/api/content/maven/hosted/pnc-builds
EOF
```

#### Step 2: Update Scripts

```bash
# Old command
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  --check-productization \
  --redhat-suffix redhat-00001

# New command (with improvements)
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  --check-productization \
  --parallel 20 \
  --use-cache \
  --expand-bom-recursive
```

#### Step 3: Review Reports

```bash
# New detailed report location
cat output/build-report.txt

# New graph visualizations
open output/dependency-graph.png
open output/bom-graph.png
```

---

## Rollout Plan

### Phase 1: Internal Testing (Week 7)

- Deploy to test environment
- Run against known Camel/CEQ BOMs
- Validate results against manual analysis
- Performance benchmarking
- Bug fixes

### Phase 2: Limited Rollout (Week 8)

- Deploy to 2-3 pilot users
- Gather feedback
- Monitor performance metrics
- Iterate on improvements

### Phase 3: Full Rollout (Week 9)

- Deploy to all users
- Update documentation
- Provide training/demos
- Monitor adoption

### Phase 4: Optimization (Week 10+)

- Analyze usage patterns
- Optimize based on real-world data
- Add requested features
- Continuous improvement

---

## Success Metrics

### Performance Metrics

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| 500 deps processing time | 10 min | 2 min | Time to complete |
| 1000 deps processing time | 20 min | 4 min | Time to complete |
| Cache hit rate | 0% | 80% | Second run speed |
| Timeout failures | 30% | <5% | Failed resolutions |
| Parallel efficiency | N/A | 70% | Speedup vs sequential |

### Quality Metrics

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| Productization accuracy | 85% | 95% | False positives/negatives |
| SCM resolution rate | 90% | 95% | Successful resolutions |
| Conflict detection | 60% | 90% | Detected conflicts |
| False positive rate | 20% | <5% | Incorrectly included deps |

### User Experience Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| User satisfaction | >4/5 | Survey |
| Documentation clarity | >4/5 | Survey |
| Time to first success | <30 min | Onboarding time |
| Support tickets | <5/month | Ticket count |

---

## Risk Assessment

### Technical Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Cache corruption | High | Low | Validation, TTL, manual clear |
| Parallel processing bugs | Medium | Medium | Extensive testing, fallback to sequential |
| BOM circular imports | Medium | Low | Cycle detection, max depth limit |
| Repository timeouts | Low | High | Multiple repositories, retry logic |
| Version conflict resolution | Medium | Medium | Configurable strategies, manual override |

### Operational Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Breaking changes | High | Low | Backward compatibility, migration guide |
| Performance regression | Medium | Low | Benchmarking, performance tests |
| Increased complexity | Medium | High | Documentation, examples, training |
| User adoption | Medium | Medium | Gradual rollout, support, demos |

---

## Future Enhancements

### Post-MVP Features

1. **AI-Powered SCM Resolution**
   - Use LLM to suggest SCM URLs for unknown artifacts
   - Learn from user corrections
   - Confidence scoring

2. **Build Success Prediction**
   - Predict which builds are likely to fail
   - Suggest build script modifications
   - Historical success rate analysis

3. **Automated Build Submission**
   - Direct PNC build submission via bacon CLI
   - Batch build creation
   - Build monitoring and status updates

4. **Dependency Update Suggestions**
   - Suggest newer versions of dependencies
   - Security vulnerability scanning
   - License compliance checking

5. **Web UI Dashboard**
   - Interactive dependency explorer
   - Real-time build status
   - Historical analytics

6. **Integration with CI/CD**
   - GitHub Actions integration
   - GitLab CI integration
   - Automated PR creation for build configs

---

## Appendix

### A. Glossary

- **BOM (Bill of Materials):** Maven POM that manages dependency versions
- **PNC (Project Newcastle):** Red Hat's build system
- **Productization:** Process of building and releasing software with Red Hat branding
- **Transitive Dependency:** Dependency of a dependency
- **SCM (Source Code Management):** Version control system (Git, SVN, etc.)
- **GAV:** GroupId:ArtifactId:Version coordinate

### B. References

- [Maven Dependency Plugin](https://maven.apache.org/plugins/maven-dependency-plugin/)
- [PNC Documentation](https://project-ncl.github.io/)
- [Bacon CLI](https://project-ncl.github.io/bacon/)
- [Indy Repository Manager](https://github.com/Commonjava/indy)

### C. Contact

For questions or feedback:
- Email: build-automation-team@redhat.com
- Slack: #build-automation
- JIRA: BUILD project

---

**Document Version:** 1.0  
**Last Updated:** 2026-08-05  
**Next Review:** 2026-09-05
