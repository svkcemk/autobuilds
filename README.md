# PNC Autobuilder

Automated toolset for generating [PNC (Project Newcastle)](https://project-ncl.github.io/pnc/) build configurations for Maven artifacts and their transitive dependencies. Outputs BACON-ready `combined-build-configs.yaml` / `pig-config.yaml` files.

---

## Repository Layout

```
autobuilds/
├── generate_build_configs.sh   ← main entry point (v2.0.0)
├── build-config.yaml           ← active CEQ/Quarkus pig-config  ⚠ DO NOT use as -c arg
├── test-config.yaml            ← safe config for -c arg (no template placeholders)
│
├── config/                     ← batch lists, per-product build configs, env DB
├── lib/                        ← runtime shell libraries
│   └── ai/                     ← AI/ML resolver layer
├── scripts/
│   ├── analysis/               ← Camel productization & comparison scripts
│   ├── fix/                    ← one-off fix and migration scripts
│   └── utils/                  ← reusable helpers (bacon, env, pom, validate)
├── tools/
│   ├── pnc/                    ← PNC API harvesters and config generators
│   └── scm/                    ← SCM URL correction and normalization utilities
└── docs/                       ← all documentation  →  see docs/index.md
    ├── guides/                 ← how-to and reference guides
    ├── camel/                  ← Apache Camel 4.22 specific docs
    ├── ehcache/                ← ehcache build diagnostic docs
    └── planning/               ← improvement and planning docs
```

---

## Quick Start

### Prerequisites

| Tool | Version | Required |
|------|---------|----------|
| bash | 4.0+ | ✅ |
| Maven (mvn) | 3.6+ | ✅ |
| Python | 3.8+ | ✅ |
| jq | any | ✅ |
| yq | any | ✅ |
| bacon CLI | any | optional (PNC integration) |

```bash
# macOS
brew install maven jq yq
```

### Run the Generator

```bash
# Single artifact
./generate_build_configs.sh -c test-config.yaml \
  -a org.apache.camel:camel-kafka:4.18.1

# Batch from file (current active batch: 63 artifacts)
ENABLE_AI_ASSISTANT=true ./generate_build_configs.sh \
  -c test-config.yaml \
  -r config/batch-artifacts.txt \
  --direct-artifacts \
  --force-full \
  -o output-batch-v8

# With BOM
./generate_build_configs.sh -c test-config.yaml \
  -a org.apache.camel:camel-kafka:4.18.1 \
  -b org.apache.camel:camel-bom:4.18.1

# Skip PNC network calls (avoids hanging)
SKIP_PNC_QUERIES=true ./generate_build_configs.sh \
  -c test-config.yaml -a <groupId:artifactId:version>
```

### Output

```
output/
├── combined-build-configs.yaml   ← submit this to BACON
├── pig-config.yaml               ← PIG format
├── build-configs/                ← per-artifact YAML/JSON
├── build-report.txt              ← run summary
└── unresolved-artifacts.txt      ← SCM failures (should be empty)
```

---

## CLI Reference

```
./generate_build_configs.sh [OPTIONS]

Input:
  -a, --artifact GAV          Single root artifact (groupId:artifactId:version)
  -r, --root-artifacts FILE   File with one artifact per line
  -b, --bom GAV               BOM for dependency management
  --direct-artifacts          Treat -r file as final list (no transitive expansion)

Config:
  -c, --config FILE           Config file  [use test-config.yaml]
  -o, --output DIR            Output directory  [default: ./output]
  --format FORMAT             individual | combined | both  [default: both]

Behavior:
  --check-productization      Skip artifacts already built with .redhat-XXXXX suffix
  --redhat-suffix SUFFIX      e.g. redhat-00001
  --force-full                Bypass incremental state cache
  --no-pnc                    Disable PNC integration

Environment variables:
  SKIP_PNC_QUERIES=true       Skip all PNC API calls (avoids network hangs)
  ENABLE_AI_ASSISTANT=true    Enable AI metadata + SCM resolution layer
  VERBOSE=true                Verbose output
```

---

## How It Works

```
generate_build_configs.sh
        │
        ├─► lib/dependency_analyzer.sh   Maven dep:tree → filtered artifact list
        │
        ├─► lib/scm_resolver.sh          6-priority SCM chain:
        │       └─► lib/scm_resolver_ai.sh   1. PNC existing builds (bacon)
        │               └─► lib/ai/           2. Hardcoded family rules
        │                   ai_scm_resolver.sh 3. JVM build data cache
        │                   unified_predictor.py 4. Maven Central POM
        │                                     5. ML prediction (5785 PNC records)
        │
        ├─► lib/ai/ai_build_metadata_resolver.sh
        │       └─► lib/ai/ai-build-metadata-training.jsonl
        │                   Per-groupId: envId + buildScript + alignmentParams
        │
        ├─► lib/parallel_processor.sh    Parallel productization checks
        ├─► lib/cache_manager.sh         Persistent cache (~/.bob/cache)
        ├─► lib/incremental_processor.sh Skip unchanged artifacts
        │
        └─► lib/config_generator.sh      Emit per-artifact YAML + combined output
```

---

## Configuration

### `test-config.yaml` (use with `-c`)
Safe defaults — no template placeholders. Always pass this as the `-c` argument.

### `build-config.yaml` ⚠
Active Quarkus/CEQ pig-config with `{{template}}` variables. **Do not pass as `-c`** — the parser will fail.

### `config/env-database.json`
966 PNC build environments (209 active). Used for environment auto-selection.

### `lib/ai/ai-build-metadata-training.jsonl`
154 training entries covering ~130 groupIds. Each entry specifies:

```json
{
  "groupId": "org.apache.commons",
  "artifactIdPattern": "*",
  "environmentId": 1593,
  "buildType": "MVN",
  "buildScript": "mvn clean deploy -DskipTests -Dgpg.skip=true -Dmaven.javadoc.skip=true -DskipNexusStagingDeployMojo=true",
  "alignmentParameters": ["-DdependencySource=NONE", "-DrepoRemovalBackup=repositories-backup.xml"],
  "confidence": "high",
  "reason": "POM inspection: maven.compiler.source=1.8"
}
```

> **Note:** `alignmentParameters` is required in every entry — BACON will reject configs without it.

### Active PNC Environments

| ID | Java | Maven | Notes |
|----|------|-------|-------|
| 660 | 8 | 3.6.3 | curator, fury |
| 1593 | 8 | 3.9.5 | **preferred Java 8** — commons, flink, cassandra |
| 435 | 11 | 3.6.3 | drill, daffodil |
| 1663 | 17 | 3.9.11 | **preferred Java 17** — netty, httpcomponents |
| 1612 | 17 | 3.9.9 | Java 17 + Gradle 9.2.1 |

---

## Documentation

See **[docs/index.md](docs/index.md)** for the full documentation index.

| Topic | Location |
|-------|----------|
| Migration from old scripts | [docs/guides/MIGRATION_GUIDE.md](docs/guides/MIGRATION_GUIDE.md) |
| Transitive dependency handling | [docs/guides/TRANSITIVE_DEPENDENCY_GUIDE.md](docs/guides/TRANSITIVE_DEPENDENCY_GUIDE.md) |
| AI features & training | [docs/guides/AI_FEATURES.md](docs/guides/AI_FEATURES.md) |
| Performance & caching | [docs/guides/PERFORMANCE_IMPROVEMENTS_README.md](docs/guides/PERFORMANCE_IMPROVEMENTS_README.md) |
| Camel 4.22 quick start | [docs/camel/QUICK_START_CAMEL_4.22.md](docs/camel/QUICK_START_CAMEL_4.22.md) |
| Ehcache build fixes | [docs/ehcache/](docs/ehcache/) |

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Script hangs | `SKIP_PNC_QUERIES=true` |
| `{{template}}` parse error | You passed `build-config.yaml` — use `test-config.yaml` |
| Wrong Java environment selected | Check POM for `maven.compiler.release/source`; update training entry |
| Missing `alignmentParameters` in output | Add field to matching entry in `lib/ai/ai-build-metadata-training.jsonl` |
| SCM URL wrong | Fix family rule in `lib/scm_resolver.sh` |
| SCM unresolved | Check `grep "<artifactId>" pnc-bulk-harvest.jsonl`; add family rule |
| `declare -A` / `wait -n` error | Already fixed (bash 3 compat in parallel_processor.sh) |

---

**Version:** 2.0.0 | **Last updated:** 2026-09-08
