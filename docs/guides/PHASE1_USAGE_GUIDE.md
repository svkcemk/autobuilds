# Phase 1: Performance Optimization - Usage Guide

**Version:** 1.0  
**Date:** 2026-08-05  
**Status:** Implemented

This guide covers the usage of Phase 1 performance optimization features: caching, parallel processing, and incremental updates.

---

## Overview

Phase 1 introduces three major performance improvements:

1. **Persistent Caching** - Cache Maven trees, SCM data, and productization status
2. **Parallel Processing** - Concurrent productization checks and SCM resolution
3. **Incremental Processing** - Skip unchanged artifacts between runs

### Expected Performance Gains

| Scenario | Baseline | With Optimizations | Speedup |
|----------|----------|-------------------|---------|
| 500 deps (first run) | 10 min | 2 min | 5x |
| 500 deps (cached) | 10 min | 30 sec | 20x |
| 500 deps (incremental, no changes) | 10 min | 10 sec | 60x |
| 1000 deps (first run) | 20 min | 4 min | 5x |
| 1000 deps (cached) | 20 min | 1 min | 20x |

---

## Feature 1: Persistent Caching

### What Gets Cached?

- **Maven Dependency Trees** (TTL: 24 hours)
- **Productization Status** (TTL: 6 hours)
- **SCM Resolution Data** (TTL: 7 days)
- **BOM Expansions** (TTL: 24 hours)

### Basic Usage

```bash
# Enable caching
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  -b org.apache.camel:camel-bom:4.18.1 \
  --use-cache \
  -o ./output
```

### Cache Management

```bash
# Clear all caches
./generate_build_configs.sh --clear-cache

# Set custom cache directory
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  --use-cache \
  --cache-dir /custom/cache/path \
  -o ./output

# View cache statistics
source lib/cache_manager.sh
get_cache_stats
```

### Cache Configuration

Set custom TTLs via environment variables:

```bash
# Set custom TTLs (in seconds)
export MAVEN_TREE_TTL=43200        # 12 hours
export PRODUCTIZATION_TTL=10800    # 3 hours
export SCM_TTL=259200              # 3 days
export BOM_EXPANSION_TTL=43200     # 12 hours

./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  --use-cache \
  -o ./output
```

### Cache Location

Default: `~/.bob/cache/`

Structure:
```
~/.bob/cache/
├── maven-trees/          # Dependency tree cache
├── productization/       # Productization status cache
├── scm/                  # SCM resolution cache
├── bom-expansion/        # BOM expansion cache
└── metadata.json         # Cache metadata
```

---

## Feature 2: Parallel Processing

### Parallel Productization Checks

Check multiple artifacts concurrently for productized versions.

```bash
# Use 20 parallel workers for productization checks
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  --check-productization \
  --redhat-suffix "redhat-*" \
  --max-parallel 20 \
  -o ./output
```

### Optimal Worker Count

| Dependency Count | Recommended Workers | Expected Time |
|-----------------|---------------------|---------------|
| < 100 | 10 | < 1 min |
| 100-500 | 20 | 1-2 min |
| 500-1000 | 30 | 2-4 min |
| > 1000 | 50 | 4-8 min |

### Combined with Caching

```bash
# Best performance: parallel + cache
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  --check-productization \
  --redhat-suffix "redhat-*" \
  --use-cache \
  --max-parallel 20 \
  -o ./output
```

---

## Feature 3: Incremental Processing

### What is Incremental Processing?

Incremental processing tracks which artifacts have been processed and skips unchanged ones on subsequent runs.

### Basic Usage

```bash
# First run (processes all artifacts)
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  --incremental \
  -o ./output

# Second run (skips unchanged artifacts)
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  --incremental \
  -o ./output
```

### Force Full Reprocessing

```bash
# Ignore incremental state and reprocess everything
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  --incremental \
  --force-full \
  -o ./output
```

### Incremental State Management

```bash
# View processed artifacts statistics
source lib/incremental_processor.sh
get_processed_stats ./output

# Query processed artifacts
query_processed_artifacts ./output all
query_processed_artifacts ./output productized
query_processed_artifacts ./output non-productized
query_processed_artifacts ./output by-date 2026-08-05
query_processed_artifacts ./output by-gav "camel"

# Export processed artifacts to CSV
export_processed_artifacts ./output ./processed-artifacts.csv

# Clear incremental state
clear_state ./output
```

### Incremental State Location

State is stored in: `<output_dir>/.state/`

Structure:
```
output/.state/
├── processed-artifacts.db    # SQLite database
├── dependency-graph.json     # Dependency graph
├── last-run.json            # Last run metadata
├── to-process.txt           # Artifacts to process
└── skipped.txt              # Skipped artifacts
```

---

## Combined Usage: All Features

### Optimal Configuration

```bash
# Maximum performance: cache + parallel + incremental
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  -b org.apache.camel:camel-bom:4.18.1 \
  --check-productization \
  --redhat-suffix "redhat-*" \
  --use-cache \
  --incremental \
  --max-parallel 20 \
  -o ./output
```

### Workflow Example

```bash
# Day 1: Initial run (10 minutes)
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  -b org.apache.camel:camel-bom:4.18.1 \
  --check-productization \
  --redhat-suffix "redhat-*" \
  --use-cache \
  --incremental \
  --max-parallel 20 \
  -o ./camel-kafka-output

# Day 1: Second run, no changes (30 seconds)
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  -b org.apache.camel:camel-bom:4.18.1 \
  --check-productization \
  --redhat-suffix "redhat-*" \
  --use-cache \
  --incremental \
  --max-parallel 20 \
  -o ./camel-kafka-output

# Day 2: Run with updated version (2 minutes - only new deps)
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.2 \
  -b org.apache.camel:camel-bom:4.18.2 \
  --check-productization \
  --redhat-suffix "redhat-*" \
  --use-cache \
  --incremental \
  --max-parallel 20 \
  -o ./camel-kafka-output
```

---

## Performance Benchmarking

### Run Benchmarks

```bash
# Run full benchmark suite
chmod +x benchmark_performance.sh
./benchmark_performance.sh
```

### Benchmark Tests

1. **Baseline** - No optimizations (1 worker, no cache, no incremental)
2. **Parallel** - 20 parallel workers
3. **Cache (First Run)** - Cold cache
4. **Cache (Second Run)** - Warm cache
5. **Incremental (First Run)** - Initial state
6. **Incremental (Second Run)** - No changes

### Expected Results

```
Baseline Duration: 10m 0s

Performance Improvements:
  Parallel Processing (20 workers): 5.0x faster
  Caching (warm cache): 20.0x faster than baseline
  Incremental (no changes): 60.0x faster than baseline

Best Case Scenario (incremental + cache):
  Duration: 10s
  Speedup: 60.0x faster than baseline
```

---

## Troubleshooting

### Cache Issues

**Problem:** Cache not being used

```bash
# Check cache statistics
source lib/cache_manager.sh
get_cache_stats

# Verify cache directory exists and is writable
ls -la ~/.bob/cache/

# Clear and rebuild cache
./generate_build_configs.sh --clear-cache
./generate_build_configs.sh -a <artifact> --use-cache -o ./output
```

**Problem:** Stale cache data

```bash
# Clear specific cache type
source lib/cache_manager.sh
clear_cache_type maven          # Clear Maven tree cache
clear_cache_type productization # Clear productization cache
clear_cache_type scm            # Clear SCM cache
clear_cache_type bom            # Clear BOM expansion cache

# Or clear all caches
clear_all_caches
```

### Parallel Processing Issues

**Problem:** Too many parallel workers causing timeouts

```bash
# Reduce parallel workers
./generate_build_configs.sh \
  -a <artifact> \
  --max-parallel 10 \
  -o ./output
```

**Problem:** Network connection issues

```bash
# Increase timeout (edit lib/parallel_processor.sh)
export PARALLEL_TIMEOUT=10  # Default is 5 seconds

./generate_build_configs.sh \
  -a <artifact> \
  --max-parallel 20 \
  -o ./output
```

### Incremental Processing Issues

**Problem:** Incremental state corrupted

```bash
# Clear incremental state and start fresh
source lib/incremental_processor.sh
clear_state ./output

# Or use --force-full flag
./generate_build_configs.sh \
  -a <artifact> \
  --incremental \
  --force-full \
  -o ./output
```

**Problem:** Changes not detected

```bash
# Force full reprocessing
./generate_build_configs.sh \
  -a <artifact> \
  --incremental \
  --force-full \
  -o ./output
```

---

## Best Practices

### 1. Always Use Caching

```bash
# Enable caching for all runs
./generate_build_configs.sh \
  -a <artifact> \
  --use-cache \
  -o ./output
```

### 2. Use Appropriate Parallel Workers

- Small projects (< 100 deps): 10 workers
- Medium projects (100-500 deps): 20 workers
- Large projects (> 500 deps): 30-50 workers

### 3. Enable Incremental for Repeated Runs

```bash
# For CI/CD pipelines or repeated analysis
./generate_build_configs.sh \
  -a <artifact> \
  --use-cache \
  --incremental \
  --max-parallel 20 \
  -o ./output
```

### 4. Periodic Cache Cleanup

```bash
# Weekly cleanup of expired cache entries
source lib/cache_manager.sh
cleanup_expired_caches
```

### 5. Monitor Cache Size

```bash
# Check cache size regularly
source lib/cache_manager.sh
get_cache_stats

# If cache is too large (> 1GB), clear old entries
cleanup_expired_caches
```

---

## Configuration Examples

### Camel Component (Aggressive Optimization)

```bash
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  -b org.apache.camel:camel-bom:4.18.1 \
  --check-productization \
  --redhat-suffix "redhat-*" \
  --use-cache \
  --incremental \
  --max-parallel 30 \
  --no-pnc-integration \
  -o ./camel-kafka-output
```

### CEQ BOM (Large Scale)

```bash
./generate_build_configs.sh \
  -b com.redhat.quarkus.platform:quarkus-camel-bom:3.2.0.redhat-00001 \
  --expand-bom \
  --check-productization \
  --redhat-suffix "redhat-*" \
  --use-cache \
  --incremental \
  --max-parallel 50 \
  --no-pnc-integration \
  -o ./ceq-output
```

### CI/CD Pipeline

```bash
#!/bin/bash
# ci-build-configs.sh

# Set cache directory to CI workspace
export CACHE_DIR="$CI_WORKSPACE/.bob-cache"

# Run with all optimizations
./generate_build_configs.sh \
  -a "$ARTIFACT_GAV" \
  -b "$BOM_GAV" \
  --check-productization \
  --redhat-suffix "redhat-*" \
  --use-cache \
  --incremental \
  --max-parallel 20 \
  -o ./output

# Archive cache for next run
tar -czf bob-cache.tar.gz "$CACHE_DIR"
```

---

## Environment Variables

### Cache Configuration

```bash
export CACHE_DIR="~/.bob/cache"           # Cache base directory
export MAVEN_TREE_TTL=86400               # Maven tree cache TTL (24h)
export PRODUCTIZATION_TTL=21600           # Productization cache TTL (6h)
export SCM_TTL=604800                     # SCM cache TTL (7d)
export BOM_EXPANSION_TTL=86400            # BOM expansion cache TTL (24h)
```

### Parallel Processing Configuration

```bash
export MAX_PARALLEL_WORKERS=20            # Max parallel workers
export PARALLEL_TIMEOUT=5                 # Timeout per request (seconds)
export PARALLEL_RETRY_COUNT=2             # Retry count for failed requests
```

---

## Migration from Old Scripts

### Before (No Optimizations)

```bash
./generate_third_party_combined_yaml.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  -o ./output
```

### After (With Optimizations)

```bash
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  --use-cache \
  --incremental \
  --max-parallel 20 \
  -o ./output
```

---

## Next Steps

After Phase 1, consider:

1. **Phase 2: Smart Filtering** - Enhanced exclude patterns and deduplication
2. **Phase 3: Recursive BOM Expansion** - Handle nested BOM imports
3. **Phase 4: Improved Productization Detection** - Multi-repository checking
4. **Phase 5: Enhanced Reporting** - Detailed build plans and cost estimates

---

## Support

For issues or questions:
- Check logs in `<output_dir>/*.log`
- Run with `--verbose` flag for detailed output
- Review cache statistics with `get_cache_stats`
- Check incremental state with `get_processed_stats`

---

**Last Updated:** 2026-08-05  
**Version:** 1.0
