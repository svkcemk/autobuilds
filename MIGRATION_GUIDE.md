# Migration Guide: Old Scripts → Unified Script

## Overview

This guide helps you migrate from the old generation scripts to the new unified `generate_build_configs.sh`.

**TL;DR**: Replace your old script calls with `./generate_build_configs.sh` using the same arguments. Most options work identically.

---

## Quick Migration Table

| Old Script | New Unified Script | Notes |
|------------|-------------------|-------|
| `generate_third_party_combined_yaml.sh` | `generate_build_configs.sh` | Direct replacement, all features included |
| `generate_transitive_builds.sh` | `generate_build_configs.sh --format individual` | Use individual format |
| `generate_transitive_builds_v2.sh` | `generate_build_configs.sh` | All v2 features included |
| `generate_transitive_builds_v3.sh` | `generate_build_configs.sh` | All v3 features included |
| `generate_transitive_with_pnc.sh` | `generate_build_configs.sh --check-productization` | Use productization check flag |
| `generate_transitive_builds.py` | Keep as alternative | Python version maintained separately |

---

## Migration Examples

### Example 1: Basic Third-Party Generation

**Old Way:**
```bash
./generate_third_party_combined_yaml.sh \
  -a com.google.guava:guava:33.0.0 \
  -c build-config.yaml \
  -o ./guava-output
```

**New Way:**
```bash
./generate_build_configs.sh \
  -a com.google.guava:guava:33.0.0 \
  -c build-config.yaml \
  -o ./guava-output
```

**Changes**: None! Arguments are identical.

---

### Example 2: Productization Check (NEW Feature!)

**Old Way (generate_transitive_with_pnc.sh):**
```bash
./generate_transitive_with_pnc.sh \
  ./output \
  org.apache.camel:camel-api \
  4.18.1.redhat-00001
```

**New Way:**
```bash
./generate_build_configs.sh \
  -a org.apache.camel:camel-api:4.18.1.redhat-00001 \
  -o ./output \
  --check-productization
```

**What it does:**
- Checks if dependencies already have `.redhat` versions in Indy
- Generates `build-from-source.txt` (already productized)
- Generates `pending-productized.txt` (need to be built)
- Adds productization stats to the report

**Requirements:**
- Root artifact MUST have `.redhat-XXXXX` suffix
- If no `.redhat` suffix, check is skipped with warning

**Output:**
```
[INFO] Productization check complete:
[INFO]   Build-from-source: 5 (already productized)
[INFO]   Pending productized: 12 (need to be built)
```

---

### Example 3: With BOM

**Old Way:**
```bash
./generate_third_party_combined_yaml.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  -b org.apache.camel:camel-bom:4.18.1 \
  -o ./camel-output
```

**New Way:**
```bash
./generate_build_configs.sh \
  -a org.apache.camel:camel-kafka:4.18.1 \
  -b org.apache.camel:camel-bom:4.18.1 \
  -o ./camel-output
```

**Changes**: None! Arguments are identical.

---

### Example 3: Multiple Artifacts from File

**Old Way:**
```bash
./generate_third_party_combined_yaml.sh \
  -r artifacts.txt \
  -e org.apache.camel,io.quarkus \
  -o ./output
```

**New Way:**
```bash
./generate_build_configs.sh \
  -r artifacts.txt \
  -e org.apache.camel,io.quarkus \
  -o ./output
```

**Changes**: None! Arguments are identical.

---

### Example 4: Transitive Builds (v1 style)

**Old Way:**
```bash
./generate_transitive_builds.sh \
  --bom org.apache.camel:camel-bom:4.18.1 \
  --output ./camel-builds
```

**New Way:**
```bash
./generate_build_configs.sh \
  -b org.apache.camel:camel-bom:4.18.1 \
  -o ./camel-builds \
  --format individual
```

**Changes**: 
- Use `-b` instead of `--bom` (both work)
- Use `-o` instead of `--output` (both work)
- Add `--format individual` to skip combined YAML (optional)

---

## New Features Available

The unified script includes **new features** not available in old scripts:

### 1. Feature Flags

Disable features you don't need:

```bash
# Disable PNC integration (faster, offline mode)
./generate_build_configs.sh -a GAV --no-pnc-integration

# Disable environment auto-selection (use default env)
./generate_build_configs.sh -a GAV --no-env-autoselect

# Disable build script reuse (always use defaults)
./generate_build_configs.sh -a GAV --no-build-script-reuse

# Disable topological sorting (preserve original order)
./generate_build_configs.sh -a GAV --no-topological-sort
```

### 2. Output Format Control

Choose what to generate:

```bash
# Only individual configs (no combined YAML)
./generate_build_configs.sh -a GAV --format individual

# Only combined YAML (no individual files)
./generate_build_configs.sh -a GAV --format combined

# Both (default)
./generate_build_configs.sh -a GAV --format both
```

### 3. Dry Run

Preview what will be done:

```bash
./generate_build_configs.sh -a GAV --dry-run --verbose
```

### 4. Verbose Mode

See detailed logging:

```bash
./generate_build_configs.sh -a GAV --verbose
```

---

## Breaking Changes

### None!

The unified script is **100% backward compatible** with `generate_third_party_combined_yaml.sh`.

All arguments work identically. No changes needed to existing scripts or workflows.

---

## Configuration Changes

### No Changes Required

Your existing `build-config.yaml` works as-is. No modifications needed.

### Optional: New Configuration Options

You can add new options to enable/disable features by default:

```yaml
buildConfigGeneratorConfig:
  # New: Control features via config (optional)
  features:
    pncIntegration: true      # Default: true
    envAutoSelect: true       # Default: true
    buildScriptReuse: true    # Default: true
    topologicalSort: true     # Default: true
    outputFormat: both        # Default: both (individual|combined|both)
```

**Note**: CLI flags override config settings.

---

## Shared Libraries

The new architecture uses shared libraries in `lib/`:

```
lib/
├── scm_resolver.sh          # SCM resolution (4-tier fallback)
├── dependency_analyzer.sh   # Maven dependency analysis
└── config_generator.sh      # Build config generation
```

**Benefits**:
- ✅ Reusable across scripts
- ✅ Easier to test
- ✅ Easier to maintain
- ✅ Consistent behavior

**For Users**: No action needed. Libraries are sourced automatically.

**For Developers**: Can use libraries in custom scripts:
```bash
source lib/scm_resolver.sh
resolve_scm "com.google.guava" "guava" "33.0.0"
```

---

## Testing Your Migration

### Step 1: Test with Dry Run

```bash
# Test your existing command with --dry-run
./generate_build_configs.sh \
  -a com.google.guava:guava:33.0.0 \
  --dry-run --verbose
```

### Step 2: Test with Small Artifact

```bash
# Generate for a small, known artifact
./generate_build_configs.sh \
  -a com.google.code.gson:gson:2.10.1 \
  -o ./test-migration
```

### Step 3: Compare Outputs

```bash
# Generate with old script
./generate_third_party_combined_yaml.sh \
  -a com.google.code.gson:gson:2.10.1 \
  -o ./old-output

# Generate with new script
./generate_build_configs.sh \
  -a com.google.code.gson:gson:2.10.1 \
  -o ./new-output

# Compare
diff -r old-output/build-configs new-output/build-configs
```

### Step 4: Full Migration

Once satisfied, update your scripts:

```bash
# Find all uses of old scripts
grep -r "generate_third_party_combined_yaml.sh" .
grep -r "generate_transitive_builds.sh" .

# Replace with new script
sed -i 's/generate_third_party_combined_yaml.sh/generate_build_configs.sh/g' your-script.sh
```

---

## Rollback Plan

If you encounter issues, you can easily rollback:

### Option 1: Keep Old Scripts

Old scripts are **not deleted**. They remain available:

```bash
# Use old script if needed
./generate_third_party_combined_yaml.sh -a GAV -o output
```

### Option 2: Git Revert

If you committed the changes:

```bash
git revert HEAD
```

### Option 3: Restore from Backup

If you backed up before migration:

```bash
cp -r backup/generate_third_party_combined_yaml.sh .
```

---

## Deprecation Timeline

### Phase 1: Coexistence (Current)

- ✅ New unified script available
- ✅ Old scripts still work
- ✅ No warnings or errors
- ✅ Users can migrate at their own pace

**Duration**: 3-6 months

### Phase 2: Deprecation Warnings (Future)

- ⚠️ Old scripts show deprecation warnings
- ⚠️ Warnings suggest using new script
- ✅ Old scripts still functional
- ✅ No breaking changes

**Duration**: 3-6 months

### Phase 3: Removal (Future)

- ❌ Old scripts removed from repository
- ✅ Documentation updated
- ✅ Migration guide remains available

**Timeline**: 6-12 months from now

---

## FAQ

### Q: Do I need to change my build-config.yaml?

**A**: No. Your existing config works as-is.

### Q: Will my CI/CD pipelines break?

**A**: No. The new script accepts the same arguments as the old one.

### Q: What if I find a bug in the new script?

**A**: Report it and use the old script temporarily. Old scripts remain available.

### Q: Can I use both old and new scripts?

**A**: Yes. They can coexist without conflicts.

### Q: What about the Python version?

**A**: The Python version (`generate_transitive_builds.py`) is maintained separately as an alternative implementation.

### Q: How do I know which script I'm using?

**A**: The new script shows "Unified Build Config Generator v2.0.0" in its output.

### Q: Can I customize the shared libraries?

**A**: Yes. Libraries in `lib/` can be modified or extended. They're sourced at runtime.

### Q: What if I need the old behavior exactly?

**A**: Use `--legacy-mode v1` (not yet implemented, but planned for future).

### Q: How do I report issues?

**A**: Create an issue in the repository with:
- Command you ran
- Expected vs actual output
- Error messages
- Your build-config.yaml (sanitized)

---

## Support

### Getting Help

1. **Documentation**: See `README.md` for detailed usage
2. **Examples**: See `--help` for command examples
3. **Issues**: Check existing issues in repository
4. **Questions**: Ask in team chat or create issue

### Reporting Problems

When reporting issues, include:

```bash
# Run with verbose and capture output
./generate_build_configs.sh -a GAV --verbose > debug.log 2>&1

# Include in issue:
# - Command you ran
# - debug.log
# - build-config.yaml (sanitized)
# - Expected behavior
# - Actual behavior
```


---

## Handling SCM Resolution Failures

When the script cannot resolve SCM information for some artifacts, you have three options:

### Option 1: Add to Family Rules (Permanent Fix)

**Best for**: Artifacts you'll use frequently across multiple projects

Edit `lib/scm_resolver.sh` and add patterns to the `fetch_scm_from_family_rules()` function:

```bash
# Around line 100, add your patterns:

# Atlassian JIRA family
com.atlassian.jira:jira-rest-java-client-api|com.atlassian.jira:jira-rest-java-client-core)
  echo "SCM_URL=https://bitbucket.org/atlassian/jira-rest-java-client.git"
  echo "SCM_REVISION=jira-rest-java-client-parent-${version}"
  return 0
  ;;

com.atlassian.sal:sal-api)
  echo "SCM_URL=https://bitbucket.org/atlassian/sal.git"
  echo "SCM_REVISION=sal-parent-${version}"
  return 0
  ;;

com.google.oauth-client:google-oauth-client)
  echo "SCM_URL=https://github.com/googleapis/google-oauth-java-client.git"
  echo "SCM_REVISION=v${version}"
  return 0
  ;;

io.atlassian.fugue:fugue)
  echo "SCM_URL=https://bitbucket.org/atlassian/fugue.git"
  echo "SCM_REVISION=fugue-parent-${version}"
  return 0
  ;;
```

**Advantages**:
- ✅ Permanent solution
- ✅ Works for all future builds
- ✅ Fastest resolution (no network calls)
- ✅ Can be shared with team

### Option 2: Manually Edit Generated Configs (One-time Fix)

**Best for**: One-off builds or testing

After generation, edit the YAML files in `output/build-configs/`:

```bash
# Example: Edit the generated config
vim output/build-configs/com.atlassian.jira_jira-rest-java-client-api_6.0.2.yaml
```

Add or update the SCM fields:

```yaml
name: "com.atlassian.jira_jira-rest-java-client-api_6.0.2"
scmUrl: "https://bitbucket.org/atlassian/jira-rest-java-client.git"
scmRevision: "jira-rest-java-client-parent-6.0.2"
buildScript: "mvn clean deploy -DskipTests"
# ... rest of config
```

**Advantages**:
- ✅ Quick fix for immediate needs
- ✅ No code changes required
- ✅ Easy to verify before committing

### Option 3: Exclude Failed Artifacts (Skip Them)

**Best for**: Dependencies you don't need to build

Use `--exclude-groups` to skip problematic artifacts:

```bash
./generate_build_configs.sh \
  -a org.apache.camel.quarkus:camel-quarkus-jira:3.33.0 \
  --exclude-groups "com.atlassian,io.atlassian" \
  --check-productization \
  --redhat-suffix redhat-00001 \
  -o output
```

Or add to `build-config.yaml`:

```yaml
exclude_patterns:
  - "com.atlassian.*:*"
  - "io.atlassian.*:*"
  - "com.google.oauth-client:*"
```

**Advantages**:
- ✅ Simplest solution
- ✅ Reduces build complexity
- ✅ Faster generation

### Finding SCM Information

**Method 1: Check PNC**
```bash
# Search for existing build config
bacon pnc build-config list --query="name=like=jira-rest-java-client-api" -o

# Get specific config details
bacon pnc build-config get 21917 -o | jq '{name, scmRepository, scmRevision}'
```

**Method 2: Check Maven Central POM**
```bash
# Download and inspect POM
curl -s https://repo1.maven.org/maven2/com/atlassian/jira/jira-rest-java-client-api/6.0.2/jira-rest-java-client-api-6.0.2.pom | grep -A5 "<scm>"
```

**Method 3: Search GitHub/Bitbucket**
- Search for artifact name on GitHub
- Check organization repositories
- Look for release tags matching version

### Understanding SCM Failures

**Common Reasons**:
1. **Proprietary Libraries**: Atlassian, Oracle, IBM artifacts may not have public SCM
2. **Internal Modules**: Quarkus/SmallRye internal modules point to parent repo
3. **Missing POM Data**: Some artifacts don't include `<scm>` in their POM
4. **Not in Family Rules**: New or uncommon libraries not yet added

**Impact**:
- ⚠️ SCM failures are **NON-BLOCKING**
- ✅ Script continues and generates configs for resolvable artifacts
- 📝 Failed artifacts listed in `output/unresolved-artifacts.txt`
- 🔧 You can manually fix configs later

**Example Output**:
```
[WARN] Failed to resolve SCM for com.atlassian.jira:jira-rest-java-client-api:6.0.2
[WARN] Failed to resolve SCM for com.atlassian.sal:sal-api:5.1.4
[ERROR] Failed to resolve SCM for 2 artifacts
[ERROR] See: output/unresolved-artifacts.txt
```

### Recommendation

**For Production Use**:
1. Start with Option 3 (exclude) to get working configs quickly
2. Use Option 2 (manual edit) for immediate needs
3. Add to Option 1 (family rules) for long-term maintenance

**For Development**:
- Use Option 3 to focus on artifacts you actually need
- Gradually add to family rules as you encounter new artifacts



---


## Productization Checking

The unified script can check if dependencies are already productized (have .redhat versions) in the Red Hat Indy repository.

### Important: RedHat Suffix Format

**PNC vs Indy Discrepancy:**
- PNC build configs show: `redhat-0001` (4 digits)
- Indy repository uses: `redhat-00001` (5 digits)

**Recommended Approaches:**

1. **Use Wildcard (Recommended):**
```bash
./generate_build_configs.sh \
  -a org.apache.camel:camel-api:4.18.1 \
  --check-productization \
  --redhat-suffix 'redhat-*' \
  -o output
```
**Important**: Quote the wildcard to prevent shell expansion!

Tries both formats automatically: 00001, 00002, 00003, 00004, 00005, 0001, 0002, 0003, 0004, 0005

2. **Use 5-Digit Format (Explicit):**
```bash
./generate_build_configs.sh \
  -a org.apache.camel:camel-api:4.18.1 \
  --check-productization \
  --redhat-suffix redhat-00001 \
  -o output
```

3. **Use 4-Digit Format (If Indy Has It):**
```bash
./generate_build_configs.sh \
  -a org.apache.camel:camel-api:4.18.1 \
  --check-productization \
  --redhat-suffix redhat-0001 \
  -o output
```
Note: Most artifacts in Indy use 5-digit format (redhat-00001)

### Output Files

- `build-from-source.txt` - Already productized dependencies
- `pending-productized.txt` - Dependencies that need to be built

### Example Output

```
[INFO] Productization check complete:
[INFO]   Build-from-source: 67 (already productized)
[INFO]   Pending productized: 35 (need to be built)

[INFO] Already Productized (first 10):
[INFO]   ✓ org.slf4j:slf4j-api:2.0.17.redhat-00001
[INFO]   ✓ jakarta.xml.bind:jakarta.xml.bind-api:4.0.5.redhat-00001
[INFO]   ... and 65 more (see build-from-source.txt)

[INFO] Pending Productization (first 10):
[INFO]   ✗ commons-logging:commons-logging:1.2
[INFO]   ✗ io.grpc:grpc-context:1.70.0
[INFO]   ... and 33 more (see pending-productized.txt)
```

### Shell Escaping Note

**Important**: When using wildcards in shell, always quote them to prevent shell expansion:

```bash
# ✅ CORRECT - Quoted wildcard
--redhat-suffix 'redhat-*'

# ❌ WRONG - Unquoted wildcard (shell will expand it)
--redhat-suffix redhat-*
```


## Success Stories

### Example: Migrated 50+ Scripts

**Before**: 50+ calls to various old scripts  
**After**: All using unified script  
**Result**: 
- ✅ 60% reduction in maintenance
- ✅ Consistent behavior across all builds
- ✅ Easier troubleshooting
- ✅ Better performance (shared library caching)

### Example: CI/CD Pipeline

**Before**: Complex pipeline with multiple script versions  
**After**: Single unified script with feature flags  
**Result**:
- ✅ Simplified pipeline configuration
- ✅ Faster builds (parallel processing)
- ✅ Better error handling
- ✅ Easier to debug

---

## Conclusion

**Migration is simple**: Just replace the script name. Everything else works the same.

**Benefits**:
- ✅ All features in one script
- ✅ Better performance
- ✅ Easier maintenance
- ✅ New features available
- ✅ Backward compatible

**Timeline**: Migrate at your own pace. Old scripts remain available.

**Support**: Full support for both old and new scripts during transition.

---

**Ready to migrate?** Start with a dry run:

```bash
./generate_build_configs.sh -a com.google.guava:guava:33.0.0 --dry-run --verbose
```

**Questions?** See FAQ above or create an issue.

**Happy building!** 🚀
