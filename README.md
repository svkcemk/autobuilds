# PNC Build Config Generator

Automated toolset for generating PNC (Project Newcastle) build configurations for Maven artifacts and their transitive dependencies.

## 🚀 Quick Start

### Prerequisites

- **bash** 4.0+
- **Maven** 3.6+
- **Python** 3.8+
- **jq** (JSON processor)
- **yq** (YAML processor)
- **bacon CLI** (optional, for PNC integration)

### Installation

```bash
# Install required tools (macOS)
brew install maven jq yq

# Install bacon CLI (optional)
# See: https://project-ncl.github.io/bacon/

# Clone and setup
git clone <repository-url>
cd autobuilds
chmod +x *.sh lib/*.sh
```

### Basic Usage

```bash
# Generate build configs for a single artifact
./generate_build_configs.sh -a org.apache.camel:camel-kafka:4.18.1

# With BOM for dependency management
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  -b org.apache.camel:camel-bom:4.18.1

# With productization check
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  --check-productization \
  --redhat-suffix redhat-00001
```

---

## 📚 Main Scripts

### `generate_build_configs.sh` - **RECOMMENDED** Unified Generator

The main, unified script that replaces all older generation scripts.

**Features:**
- ✅ Transitive dependency analysis
- ✅ PNC integration (reuses existing build configs)
- ✅ Productization checking (identifies already-built .redhat versions)
- ✅ Environment auto-selection
- ✅ Build script reuse from similar artifacts
- ✅ Topological sorting
- ✅ Multiple output formats (individual YAMLs + combined YAML)
- ✅ SCM resolution from multiple sources

**Usage:**
```bash
./generate_build_configs.sh [OPTIONS]

Options:
  -a, --artifact GAV           Root artifact (groupId:artifactId:version)
  -b, --bom GAV               BOM for dependency management
  -r, --root-artifacts FILE   File with multiple root artifacts
  -c, --config FILE           Config file (default: build-config.yaml)
  -o, --output DIR            Output directory (default: ./output)
  --check-productization      Check if dependencies already have .redhat versions
  --redhat-suffix SUFFIX      RedHat version suffix (e.g., redhat-00001)
  --format FORMAT             Output format: individual|combined|both (default: both)
  --no-pnc                    Disable PNC integration
  --no-env-auto-select        Disable environment auto-selection
  --no-build-script-reuse     Disable build script reuse
  --no-topological-sort       Disable topological sorting
  -v, --verbose               Enable verbose output
  -h, --help                  Show help
```

**Examples:**

```bash
# Basic: Single artifact
./generate_build_configs.sh -a commons-io:commons-io:2.11.0

# With BOM: Camel component
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  -b org.apache.camel:camel-bom:4.18.1

# Productization check: Find what's already built
./generate_build_configs.sh \
  -a org.apache.camel:camel-flink:4.18.1 \
  --check-productization \
  --redhat-suffix redhat-00001

# Multiple artifacts from file
echo "org.apache.camel:camel-kafka:4.18.1" > artifacts.txt
echo "org.apache.camel:camel-flink:4.18.1" >> artifacts.txt
./generate_build_configs.sh -r artifacts.txt

# Combined YAML only (for PIG)
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  --format combined
```

**Output Structure:**
```
output/
├── all-dependencies.txt              # All transitive dependencies
├── third-party-dependencies.txt      # Filtered third-party deps
├── root-artifacts.txt                # Root artifacts analyzed
├── dependency-edges.txt              # Dependency graph edges
├── unresolved-artifacts.txt          # SCM resolution failures
├── build-from-source.txt             # Already productized (.redhat)
├── pending-productized.txt           # Need to be built
├── build-report.txt                  # Detailed generation report
├── combined-build-configs.yaml       # Single YAML with all configs
└── build-configs/                    # Individual YAML files
    ├── groupId_artifactId_version.yaml
    └── ...
```

---

## 🔄 Migration Guide

### From Old Scripts to Unified Script

| Old Script | New Command | Notes |
|------------|-------------|-------|
| `generate_third_party_combined_yaml.sh` | `generate_build_configs.sh` | Direct replacement |
| `generate_transitive_builds.sh` | `generate_build_configs.sh --format individual` | Use individual format |
| `generate_transitive_builds_v2.sh` | `generate_build_configs.sh` | All v2 features included |
| `generate_transitive_builds_v3.sh` | `generate_build_configs.sh` | All v3 features included |
| `generate_transitive_with_pnc.sh` | `generate_build_configs.sh --check-productization` | Use productization flag |

### Migration Examples

#### Example 1: Basic Third-Party Generation

**Old:**
```bash
./generate_third_party_combined_yaml.sh \
  -a com.google.guava:guava:33.0.0 \
  -o ./guava-output
```

**New:**
```bash
./generate_build_configs.sh \
  -a com.google.guava:guava:33.0.0 \
  -o ./guava-output
```

#### Example 2: With Productization Check

**Old:**
```bash
./generate_transitive_with_pnc.sh \
  ./output \
  org.apache.camel:camel-api \
  4.18.1.redhat-00001
```

**New:**
```bash
./generate_build_configs.sh \
  -a org.apache.camel:camel-api:4.18.1.redhat-00001 \
  -o ./output \
  --check-productization
```

#### Example 3: With BOM

**Old:**
```bash
./generate_third_party_combined_yaml.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  -b org.apache.camel:camel-bom:4.18.1
```

**New:**
```bash
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  -b org.apache.camel:camel-bom:4.18.1
```

---

## 🔧 Configuration

### `build-config.yaml`

Main configuration file for dependency filtering and build settings.

```yaml
# Dependency filtering
dependencyResolutionConfig:
  # Patterns to include (supports wildcards)
  includeArtifacts:
    - org.apache.camel:*:*
    - org.apache.cxf:*:*
  
  # Patterns to exclude
  excludeArtifacts:
    - org.springframework:*:*
    - org.testcontainers:*:*
  
  # Include optional dependencies
  includeOptionalDependencies: true

# Build configuration defaults
buildConfigGeneratorConfig:
  defaultValues:
    environmentName: "OpenJDK 11.0; Mvn 3.9.6"
    buildScript: "mvn -DskipTests clean deploy"
  
  # SCM URL transformations
  scmPattern:
    "git@github.com:": "https://github.com/"
    "git://github.com/": "https://github.com/"
```

### Environment Database (`env-database.json`)

Auto-selects build environments based on artifact patterns.

```json
{
  "environments": [
    {
      "name": "OpenJDK 11.0; Mvn 3.9.6",
      "patterns": ["org.apache.camel:*", "org.apache.cxf:*"]
    },
    {
      "name": "OpenJDK 17.0; Mvn 3.9.6",
      "patterns": ["org.springframework.boot:*"]
    }
  ]
}
```

---

## 🎯 Features

### 1. Productization Checking

Identifies which dependencies already have `.redhat` versions in Indy/Maven repositories.

```bash
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  --check-productization \
  --redhat-suffix redhat-00001
```

**Output:**
- `build-from-source.txt` - Already productized (skip building)
- `pending-productized.txt` - Need to be built

### 2. PNC Integration

Reuses SCM information from existing PNC build configs.

**Priority order for SCM resolution:**
1. PNC existing builds (via bacon CLI)
2. Family rules (hardcoded patterns)
3. JVM build data cache
4. Camel Spring Boot data
5. Maven Central POM

### 3. Environment Auto-Selection

Automatically selects the correct build environment based on artifact patterns.

### 4. Build Script Reuse

Reuses build scripts from similar artifacts in the same family.

### 5. Topological Sorting

Orders build configs based on dependency relationships.

---

## 📖 Additional Documentation

- **[MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)** - Detailed migration from old scripts
- **[TRANSITIVE_DEPENDENCY_GUIDE.md](TRANSITIVE_DEPENDENCY_GUIDE.md)** - Understanding transitive dependencies
- **[CAMEL_ANALYSIS_GUIDE.md](CAMEL_ANALYSIS_GUIDE.md)** - Apache Camel specific guidance

---

## 🛠️ Utility Scripts

### `bacon_utils.sh`

Helper functions for bacon CLI integration.

```bash
source bacon_utils.sh

# Fetch SCM from Maven Central
fetch_scm_from_maven "org.example" "artifact" "1.0.0"

# Create build config
create_build_config \
  "my-build" \
  "https://github.com/example/repo.git" \
  "v1.0.0" \
  "mvn clean deploy" \
  "OpenJDK 11" \
  "output.yaml"
```

### `validate_config.sh`

Validates `build-config.yaml` before generation.

```bash
./validate_config.sh build-config.yaml
```

### `env_selector.sh`

Interactive environment selection tool.

```bash
./env_selector.sh org.apache.camel:camel-kafka:4.18.1
```

---

## 🐛 Troubleshooting

### SCM Resolution Failures

If you see warnings like:
```
[WARN] Failed to resolve SCM for org.example:artifact:1.0.0
```

**Solutions:**

1. **Check if bacon CLI is configured:**
   ```bash
   bacon pnc build-config list --query="name==*artifact*"
   ```

2. **Add family rules** to `lib/scm_resolver.sh`:
   ```bash
   org.example:artifact*)
     echo "SCM_URL=https://github.com/example/artifact.git"
     echo "SCM_REVISION=v${version}"
     return 0
     ;;
   ```

3. **Add manual SCM mapping** to `build-config.yaml`:
   ```yaml
   scmMapping:
     "org.example:artifact": "https://github.com/example/artifact.git"
   ```

### Maven Dependency Resolution

If Maven fails to resolve dependencies:
- Check your `~/.m2/settings.xml`
- Ensure you have access to required repositories
- Try with `--verbose` flag for detailed errors

### Productization Check Failures

If productization check fails:
- Ensure artifact version has `.redhat-XXXXX` suffix
- Check Indy/Maven repository accessibility
- Verify `--redhat-suffix` matches your organization's convention

---

## 📝 Examples

### Complete Workflow: Camel Component

```bash
# 1. Generate configs with productization check
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  -b org.apache.camel:camel-bom:4.18.1 \
  --check-productization \
  --redhat-suffix redhat-00001 \
  -o ./camel-kafka-output

# 2. Review the report
cat ./camel-kafka-output/build-report.txt

# 3. Check what needs to be built
cat ./camel-kafka-output/pending-productized.txt

# 4. Review generated configs
ls -la ./camel-kafka-output/build-configs/

# 5. Create builds in PNC using bacon
for config in ./camel-kafka-output/build-configs/*.yaml; do
  echo "Creating build from $config"
  bacon pnc build-config create --file "$config"
done
```

### Batch Processing Multiple Artifacts

```bash
# Create artifact list
cat > artifacts.txt <<EOF
org.apache.camel:camel-kafka:4.18.1
org.apache.camel:camel-flink:4.18.1
org.apache.camel:camel-aws2-s3:4.18.1
EOF

# Generate all configs
./generate_build_configs.sh \
  -r artifacts.txt \
  -b org.apache.camel:camel-bom:4.18.1 \
  --check-productization \
  --redhat-suffix redhat-00001 \
  -o ./batch-output
```

---

## 🔐 Security

- Never commit sensitive credentials to git
- Use environment variables for authentication
- Review generated configs before creating in PNC
- Validate SCM URLs before building

---

## 📄 License

This toolset is provided as-is for automating PNC build configuration generation.

---

## 🤝 Contributing

When adding new features:
1. Update this README
2. Add examples to relevant guides
3. Update migration guide if changing existing behavior
4. Test with multiple artifact types

---

## 📞 Support

For issues or questions:
1. Check the build-report.txt for detailed information
2. Run with `--verbose` for debugging
3. Review relevant documentation guides
4. Check bacon CLI logs for PNC integration issues

---

## 🗂️ File Structure

```
autobuilds/
├── README.md                              # This file
├── MIGRATION_GUIDE.md                     # Migration from old scripts
├── TRANSITIVE_DEPENDENCY_GUIDE.md         # Transitive dependency handling
├── CAMEL_ANALYSIS_GUIDE.md                # Camel-specific guidance
├── generate_build_configs.sh              # ⭐ Main unified script
├── build-config.yaml                      # Main configuration
├── env-database.json                      # Environment auto-selection
├── custom_modes.yaml                      # Bob Shell custom modes
├── bacon_utils.sh                         # Bacon CLI utilities
├── validate_config.sh                     # Config validator
├── env_selector.sh                        # Environment selector
├── env_parser.sh                          # Environment parser
├── pom_analyzer.sh                        # POM analysis utilities
├── lib/                                   # Shared libraries
│   ├── config_generator.sh                # Config generation logic
│   ├── dependency_analyzer.sh             # Dependency analysis
│   └── scm_resolver.sh                    # SCM resolution (PNC + family rules)
└── [Legacy Scripts]                       # Kept for reference
    ├── generate_third_party_combined_yaml.sh
    ├── generate_transitive_builds.sh
    ├── generate_transitive_builds_v2.sh
    ├── generate_transitive_builds_v3.sh
    └── generate_transitive_with_pnc.sh
```

---

**Last Updated:** 2026-06-30  
**Version:** 2.0.0