# PNC Environment Comparison - Gradle Versions for Ehcache 3.12.0

## Available Java 17 + Gradle Environments

Based on the PNC environment database, here are the available Java 17 environments with different Gradle versions:

### Environment 1551 (Gradle 7.2) ⭐ RECOMMENDED
- **ID**: 1551
- **Name**: OpenJDK 17.0; RHEL 8; Mvn 3.6.3; Gradle 7.2
- **Image**: builder-rhel-8-j17-mvn3.6.3-gradle7.2:1.0.9
- **Status**: ✅ Active, usable
- **Gradle**: 7.2
- **Maven**: 3.6.3
- **JDK Path**: `/usr/lib/jvm/java-17-openjdk`

### Environment 1552 (Gradle 7.3.2)
- **ID**: 1552
- **Name**: OpenJDK 17.0; RHEL 8; Mvn 3.6.3; Gradle 7.3.2
- **Image**: builder-rhel-8-j17-mvn3.6.3-gradle7.3.2:1.0.6
- **Status**: ✅ Active, usable
- **Gradle**: 7.3.2
- **Maven**: 3.6.3
- **JDK Path**: `/usr/lib/jvm/java-17-openjdk`

### Environment 1554 (Gradle 7.5.1) 🆕
- **ID**: 1554
- **Name**: OpenJDK 17.0; RHEL 8; Mvn 3.8.6; Gradle 7.5.1
- **Image**: builder-rhel-8-j17-mvn3.8.6-gradle7.5.1:1.0.3
- **Status**: ✅ Active, usable
- **Gradle**: 7.5.1
- **Maven**: 3.8.6
- **JDK Path**: `/usr/lib/jvm/java-17-openjdk`
- **Note**: Newer Maven version (3.8.6 vs 3.6.3)

### Environment 1555 (Gradle 7.6)
- **ID**: 1555
- **Name**: OpenJDK 17.0; RHEL 8; Mvn 3.8.6; Gradle 7.6
- **Image**: builder-rhel-8-j17-mvn3.8.6-gradle7.6:1.0.3
- **Status**: ✅ Active, usable
- **Gradle**: 7.6
- **Maven**: 3.8.6
- **JDK Path**: `/usr/lib/jvm/java-17-openjdk`

## Build BQ33EGIMM3AAA Analysis

Based on the build log analysis:
- **JDK Download**: ✅ Successful (unlike BQ34PKTRU3AAA)
- **Environment**: Likely used one of the Java 17 environments
- **Issue**: Log appears truncated/incomplete
- **Status**: Cannot determine final build result from incomplete log

## Comparison Matrix

| Feature | Env 1551 | Env 1552 | Env 1554 | Env 1555 |
|---------|----------|----------|----------|----------|
| **Gradle** | 7.2 | 7.3.2 | 7.5.1 | 7.6 |
| **Maven** | 3.6.3 | 3.6.3 | 3.8.6 | 3.8.6 |
| **JDK** | 17.0 | 17.0 | 17.0 | 17.0 |
| **RHEL** | 8 | 8 | 8 | 8 |
| **Status** | Active | Active | Active | Active |
| **Ehcache 3.12.0** | ✅ Tested | ⚠️ Untested | ⚠️ Untested | ⚠️ Untested |

## Gradle Version Compatibility

### Gradle 7.2 (Environment 1551)
- **Release**: August 2021
- **Java Support**: Up to Java 17
- **Ehcache 3.12.0**: ✅ Compatible (with patches)
- **Stability**: Mature, well-tested
- **Recommendation**: ⭐ **Use this for Ehcache 3.12.0**

### Gradle 7.3.2 (Environment 1552)
- **Release**: December 2021
- **Java Support**: Up to Java 17
- **Ehcache 3.12.0**: ✅ Likely compatible
- **Stability**: Stable
- **Recommendation**: Alternative if 7.2 fails

### Gradle 7.5.1 (Environment 1554)
- **Release**: August 2022
- **Java Support**: Up to Java 18
- **Ehcache 3.12.0**: ⚠️ May need different patches
- **Stability**: Stable, newer APIs
- **Recommendation**: Test if 7.2/7.3.2 fail
- **Note**: Maven 3.8.6 may have different behavior

### Gradle 7.6 (Environment 1555)
- **Release**: November 2022
- **Java Support**: Up to Java 19
- **Ehcache 3.12.0**: ⚠️ May need different patches
- **Stability**: Latest in 7.x series
- **Recommendation**: Use only if others fail

## Why Environment 1551 (Gradle 7.2) is Recommended

### 1. Proven Compatibility
- Gradle 7.2 is the version Ehcache 3.12.0 was likely developed with
- Our patches are specifically designed for Gradle 7.2 APIs
- Lower risk of unexpected API changes

### 2. Maven 3.6.3
- Stable, well-tested version
- Known behavior in PNC environment
- Less likely to have dependency resolution changes

### 3. Tested Configuration
- We have working patches for this environment
- Known issues are documented and solved
- Lower risk of new problems

## When to Use Gradle 7.5.1 (Environment 1554)

Consider using environment 1554 if:

1. **Gradle 7.2 fails** with API compatibility issues
2. **Newer Gradle features** are needed
3. **Maven 3.8.6** is specifically required
4. **Testing newer toolchain** for future compatibility

### Potential Advantages
- Newer Gradle may have bug fixes
- Better Java 17 support
- Improved dependency resolution
- More recent security patches

### Potential Risks
- API changes may break our patches
- Maven 3.8.6 may resolve dependencies differently
- Less tested with Ehcache 3.12.0
- May need patch adjustments

## Configuration Differences

### For Environment 1551 (Gradle 7.2)
```yaml
environment:
  id: 1551
  name: OpenJDK 17.0; RHEL 8; Mvn 3.6.3; Gradle 7.2

buildScript: |
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
  # Use existing patches (tested)
  gradle --version  # Shows: Gradle 7.2
```

### For Environment 1554 (Gradle 7.5.1)
```yaml
environment:
  id: 1554
  name: OpenJDK 17.0; RHEL 8; Mvn 3.8.6; Gradle 7.5.1

buildScript: |
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
  # May need adjusted patches
  gradle --version  # Shows: Gradle 7.5.1
```

## Recommendation Strategy

### Phase 1: Start with Environment 1551 (Gradle 7.2)
1. Use the configuration from `EHCACHE_BQ34PKTRU3AAA_ACTION_PLAN.md`
2. Apply the 5 Gradle API compatibility patches
3. Use pre-installed JDK (no download)
4. Monitor build for success

### Phase 2: If 1551 Fails, Try 1554 (Gradle 7.5.1)
1. Use same configuration structure
2. Test if patches still apply
3. Adjust patches if needed for Gradle 7.5.1 APIs
4. Monitor for Maven 3.8.6 dependency changes

### Phase 3: If Both Fail, Try 1552 or 1555
1. Environment 1552 (Gradle 7.3.2) - middle ground
2. Environment 1555 (Gradle 7.6) - latest 7.x

## Build BQ33EGIMM3AAA Insights

The build log shows:
- ✅ JDK download **succeeded** (unlike BQ34PKTRU3AAA)
- ✅ Git clone successful
- ⚠️ Log truncated before showing Gradle version
- ⚠️ Cannot confirm which environment was used
- ⚠️ Cannot confirm final build result

**Hypothesis**: If BQ33EGIMM3AAA used Gradle 7.5, the JDK download success suggests the environment setup works, but we need the complete log to see if the build itself succeeded.

## Action Plan

### Immediate Action (Recommended)
1. **Use Environment 1551** (Gradle 7.2)
   - Configuration: `EHCACHE_BQ34PKTRU3AAA_ACTION_PLAN.md`
   - Patches: All 5 Gradle API fixes
   - JDK: Pre-installed (no download)

### Alternative Action (If Requested)
1. **Use Environment 1554** (Gradle 7.5.1)
   - Same configuration structure
   - Test patch compatibility
   - Monitor for differences

### Fallback Actions
1. Try Environment 1552 (Gradle 7.3.2)
2. Try Environment 1555 (Gradle 7.6)
3. Adjust patches for newer Gradle APIs if needed

## Summary

| Environment | Gradle | Recommendation | Risk Level |
|-------------|--------|----------------|------------|
| **1551** | 7.2 | ⭐ **Primary** | Low |
| **1552** | 7.3.2 | Alternative | Low-Medium |
| **1554** | 7.5.1 | Test if needed | Medium |
| **1555** | 7.6 | Last resort | Medium-High |

**Bottom Line**: Start with **Environment 1551 (Gradle 7.2)** as documented in the action plan. It has the lowest risk and highest chance of success with our tested patches.

---

**Last Updated**: 2026-08-26  
**Recommended**: Environment 1551 (Gradle 7.2)  
**Alternative**: Environment 1554 (Gradle 7.5.1) if specifically needed
