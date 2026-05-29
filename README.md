# Transitive Build Config Generator for PNC

Automated tool for generating PNC (Project Newcastle) build configurations for transitive dependencies using the bacon CLI.

## Overview

This toolset helps automate the process of:
1. Analyzing transitive dependencies from a BOM (Bill of Materials)
2. Filtering dependencies based on include/exclude patterns
3. Generating PNC build configurations using bacon CLI
4. Creating build groups and managing build order

## Prerequisites

### Required Tools

1. **bacon CLI** - PNC command-line interface
   ```bash
   # Install bacon CLI
   # See: https://project-ncl.github.io/bacon/
   ```

2. **Maven** - For dependency analysis
   ```bash
   brew install maven  # macOS
   # or
   sudo apt-get install maven  # Linux
   ```

3. **yq** - YAML processor
   ```bash
   pip install yq
   ```

4. **jq** - JSON processor (optional, for advanced features)
   ```bash
   brew install jq  # macOS
   # or
   sudo apt-get install jq  # Linux
   ```

## Files

- `generate_transitive_builds.sh` - Main automation script
- `bacon_utils.sh` - Utility functions for bacon CLI integration
- `validate_config.sh` - Configuration validator
- `build-config.yaml` - Configuration file with dependency rules
- `README.md` - This documentation

## Configuration

Edit `build-config.yaml` to configure:

### Dependency Resolution

```yaml
dependencyResolutionConfig:
  # BOM to analyze
  analyzeBOM: org.apache.camel.quarkus:camel-quarkus-bom:3.33.0
  
  # Include optional dependencies
  includeOptionalDependencies: true
  
  # Patterns to include (supports wildcards)
  includeArtifacts:
    - org.apache.camel:*:*
    - org.apache.cxf:*:*
  
  # Patterns to exclude
  excludeArtifacts:
    - org.springframework:*:*
    - org.testcontainers:*:*
  
  # Recipe repositories to check for existing builds
  recipeRepos:
    - https://github.com/redhat-appstudio/jvm-build-data
```

### Build Config Generation

```yaml
buildConfigGeneratorConfig:
  defaultValues:
    environmentName: "OpenJDK 11.0; Mvn 3.5.4"
    buildScript: "mvn -DskipTests clean deploy"
  
  # SCM URL transformations
  scmPattern:
    "git@github.com:": "https://github.com/"
  
  # PIG (Product Integration Group) template
  pigTemplate:
    product:
      name: Camel Extensions for Quarkus Third Party Components
      abbreviation: ceq-third-party
    version: 4.18.1
    milestone: DR1
```

## Usage

### 1. Validate Configuration

First, validate your configuration file:

```bash
./validate_config.sh build-config.yaml
```

### 2. Generate Build Configs

Run the main script to generate build configurations:

```bash
# Basic usage (uses build-config.yaml)
./generate_transitive_builds.sh

# With custom config file
./generate_transitive_builds.sh --config my-config.yaml

# Specify output directory
./generate_transitive_builds.sh --output ./my-builds

# Dry run (show what would be done)
./generate_transitive_builds.sh --dry-run

# Verbose output
./generate_transitive_builds.sh --verbose

# Specify BOM directly
./generate_transitive_builds.sh --bom org.example:my-bom:1.0.0
```

### 3. Review Generated Configs

Check the output directory for generated files:

```
generated-configs/
├── all-dependencies.txt          # All transitive dependencies
├── filtered-dependencies.txt     # After include/exclude filtering
├── build-configs/                # Individual build configs
│   ├── org.example_artifact1_1.0.0.yaml
│   ├── org.example_artifact2_2.0.0.yaml
│   └── ...
├── pig-config.yaml               # Product Integration Group config
└── build-report.txt              # Summary report
```

### 4. Create Builds in PNC

Use bacon CLI to create builds in PNC:

```bash
# Source utility functions
source bacon_utils.sh

# Create individual build config
bacon pnc build-config create \
  --file generated-configs/build-configs/org.example_artifact_1.0.0.yaml

# Or use the utility function
create_pnc_build \
  "generated-configs/build-configs/org.example_artifact_1.0.0.yaml" \
  "PRODUCT_VERSION_ID"

# Trigger a build
trigger_pnc_build "BUILD_CONFIG_ID"

# Wait for build completion
wait_for_build "BUILD_ID" 3600 30
```

## Advanced Usage

### Using Utility Functions

The `bacon_utils.sh` provides helper functions:

```bash
# Source the utilities
source bacon_utils.sh

# Fetch SCM info from Maven Central
fetch_scm_from_maven "org.example" "artifact" "1.0.0"

# Transform SCM URL using config patterns
transform_scm_url "git@github.com:example/repo.git" "build-config.yaml"

# Create build config
create_build_config \
  "my-build" \
  "https://github.com/example/repo.git" \
  "v1.0.0" \
  "mvn clean deploy" \
  "OpenJDK 11" \
  "output.yaml"

# Create build group
create_build_group \
  "My Build Group" \
  "PRODUCT_VERSION_ID" \
  "CONFIG_ID_1" "CONFIG_ID_2" "CONFIG_ID_3"
```

### Customizing Build Scripts

You can customize build scripts per artifact by modifying the generated configs:

```yaml
name: org.example_artifact_1.0.0
description: Auto-generated build config
scmRepository:
  url: https://github.com/example/artifact.git
  revision: v1.0.0
buildScript: |
  mvn -DskipTests clean deploy
  # Add custom steps here
environment:
  name: OpenJDK 11.0; Mvn 3.5.4
buildType: MVN
```

## Workflow Example

Complete workflow for generating and creating builds:

```bash
# 1. Validate configuration
./validate_config.sh

# 2. Generate build configs (dry run first)
./generate_transitive_builds.sh --dry-run --verbose

# 3. Generate actual configs
./generate_transitive_builds.sh --output ./my-builds

# 4. Review the report
cat my-builds/build-report.txt

# 5. Update SCM URLs in generated configs if needed
# Edit files in my-builds/build-configs/

# 6. Create builds in PNC using bacon
for config in my-builds/build-configs/*.yaml; do
  echo "Creating build from $config"
  bacon pnc build-config create --file "$config"
done

# 7. Create build group
bacon pnc build-group create \
  --name "My Transitive Builds" \
  --file my-builds/pig-config.yaml
```

## Troubleshooting

### Maven Dependency Analysis Fails

If Maven fails to resolve dependencies:
- Check your Maven settings.xml
- Ensure you have access to required repositories
- Try running with `--verbose` to see detailed errors

### SCM URLs Not Found

If SCM information cannot be fetched:
- Manually update the generated configs with correct SCM URLs
- Add SCM mappings to your build-config.yaml:
  ```yaml
  scmMapping:
    "github.com/old/repo.git": "github.com/new/repo.git"
  ```

### Bacon CLI Errors

If bacon commands fail:
- Verify bacon is installed: `bacon --version`
- Check PNC authentication: `bacon pnc auth`
- Ensure you have proper permissions in PNC

## Tips

1. **Start with dry-run**: Always use `--dry-run` first to see what will be generated
2. **Use verbose mode**: Add `--verbose` for detailed logging
3. **Validate before generating**: Run `validate_config.sh` to catch config errors early
4. **Review generated configs**: Check SCM URLs and build scripts before creating in PNC
5. **Test with small BOMs**: Start with a small BOM to test your configuration

## References

- [Bacon CLI Documentation](https://project-ncl.github.io/bacon/)
- [PNC Documentation](https://project-ncl.github.io/)
- [Maven Dependency Plugin](https://maven.apache.org/plugins/maven-dependency-plugin/)

## Support

For issues or questions:
1. Check the build-report.txt for detailed information
2. Run with `--verbose` for debugging
3. Review bacon CLI logs
4. Consult PNC documentation

## License

This toolset is provided as-is for automating PNC build configuration generation.
