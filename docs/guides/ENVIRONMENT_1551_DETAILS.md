# Environment 1551 - Complete Details

## Overview

**Environment ID**: 1551  
**Name**: OpenJDK 17.0; RHEL 8; Mvn 3.6.3; Gradle 7.2  
**Status**: ✅ Active (not deprecated, usable)

## Builder Image

- **Repository**: quay.io/rh-newcastle
- **Image**: builder-rhel-8-j17-mvn3.6.3-gradle7.2:1.0.9
- **Digest**: builder-rhel-8-j17-mvn3.6.3-gradle7.2@sha256:636e8819a919c747bc2029baba64007deb7b90a91bd4e73643a75cfde3eb9e97
- **Manifest URL**: https://sbomer.pnc.engineering.redhat.com/api/v1beta1/manifests/9C7CA5E5D7BD434/bom

## Pre-installed Software

| Component | Version | Location |
|-----------|---------|----------|
| **Java (JDK)** | 17.0 | `/usr/lib/jvm/java-17-openjdk` |
| **Maven** | 3.6.3 | Pre-installed |
| **Gradle** | 7.2 | Pre-installed |
| **Operating System** | RHEL 8 | Linux |

## Capabilities

- ✅ Java
- ✅ Maven
- ✅ Gradle

## Why This Environment is Perfect for Ehcache 3.12.0

### 1. Java 17 Pre-installed
- **No download needed** - Eliminates the timeout issue from build BQ34PKTRU3AAA
- **Path**: `/usr/lib/jvm/java-17-openjdk`
- **Compatible with Jackson 2.20.0** - Can handle Java 21 bytecode

### 2. Gradle 7.2 Included
- **Matches Ehcache requirements** - Ehcache 3.12.0 uses Gradle 7.x
- **Pre-installed** - No setup time required
- **Compatible** - With our Gradle API compatibility patches

### 3. Maven 3.6.3
- **Modern version** - Supports all required features
- **Stable** - Well-tested in PNC environment

### 4. RHEL 8 Base
- **Modern OS** - Better library support
- **Stable** - Enterprise-grade reliability
- **Compatible** - With all build tools

## Usage in Build Configuration

### Setting Environment
```yaml
environment:
  id: 1551
  name: OpenJDK 17.0; RHEL 8; Mvn 3.6.3; Gradle 7.2
```

### Using Pre-installed JDK
```bash
# Set JAVA_HOME to pre-installed JDK
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH=$JAVA_HOME/bin:$PATH

# Verify Java version
java -version
# Expected output: openjdk version "17.0.x"
```

### Gradle Configuration
```bash
# Gradle is already available
gradle --version
# Expected: Gradle 7.2

# Use with Java 17 parameters
gradle build \
  -Porg.gradle.java.installations.auto-download=false \
  -PruntimeJavaHomePath=/usr/lib/jvm/java-17-openjdk \
  -Druntime.java=17
```

## Comparison with Other Environments

| Feature | Env 1551 (Java 17) | Env 660 (Java 11) | Env 919 (Java 8) |
|---------|-------------------|-------------------|------------------|
| JDK Version | 17.0 ✅ | 11.0 | 1.8.0 |
| Gradle | 7.2 ✅ | 7.2 | 6.x |
| RHEL Version | 8 ✅ | 8 | 7 |
| Jackson 2.20.0 | ✅ Compatible | ⚠️ Workaround needed | ❌ Incompatible |
| Ehcache 3.12.0 | ✅ Recommended | ⚠️ Alternative | ❌ Not recommended |

## Build Configuration Examples

### Minimal Configuration (No Patches)
```yaml
name: ehcache-3.12.0-simple
environment:
  id: 1551

buildScript: |
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
  export PATH=$JAVA_HOME/bin:$PATH
  
  gradle publish -x test
```

### Full Configuration (With Patches)
```yaml
name: ehcache-3.12.0-complete
environment:
  id: 1551

buildScript: |
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
  export PATH=$JAVA_HOME/bin:$PATH
  
  # Apply Gradle 7 compatibility patches
  # [patches here]
  
  gradle --stacktrace publish -x test \
    -Porg.gradle.java.installations.auto-download=false \
    -PruntimeJavaHomePath=/usr/lib/jvm/java-17-openjdk \
    -Druntime.java=17
```

## Advantages Over Previous Attempts

### Build BQ34PKTRU3AAA Issues
| Issue | Previous Approach | Environment 1551 Solution |
|-------|------------------|---------------------------|
| JDK Download | Downloaded during build | ✅ Pre-installed |
| Network Timeout | 58MB download interrupted | ✅ No download needed |
| Build Time | Slow (download + build) | ✅ Fast (build only) |
| Reliability | Network-dependent | ✅ Reliable |

## Technical Specifications

### Java Details
- **Version**: OpenJDK 17.0
- **Vendor**: Red Hat
- **Type**: HotSpot JVM
- **Architecture**: x64
- **Installation Path**: `/usr/lib/jvm/java-17-openjdk`

### Gradle Details
- **Version**: 7.2
- **Release Date**: August 2021
- **Features**: 
  - Java 17 support
  - Improved dependency resolution
  - Better performance
  - Configuration cache

### Maven Details
- **Version**: 3.6.3
- **Release Date**: November 2019
- **Features**:
  - Stable and mature
  - Good plugin compatibility
  - Reliable dependency resolution

## Verification Commands

### Check Java Installation
```bash
# Verify Java is installed
ls -la /usr/lib/jvm/java-17-openjdk

# Check Java version
/usr/lib/jvm/java-17-openjdk/bin/java -version

# Verify JAVA_HOME
echo $JAVA_HOME
```

### Check Gradle Installation
```bash
# Verify Gradle is available
which gradle

# Check Gradle version
gradle --version

# Test Gradle with Java 17
gradle --version | grep "JVM:"
```

### Check Maven Installation
```bash
# Verify Maven is available
which mvn

# Check Maven version
mvn --version

# Verify Maven uses correct Java
mvn --version | grep "Java version"
```

## Troubleshooting

### If Java Not Found
```bash
# List available Java installations
ls -la /usr/lib/jvm/

# Use alternatives to set Java
alternatives --list | grep java

# Manually set JAVA_HOME
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
```

### If Gradle Fails
```bash
# Check Gradle daemon
gradle --stop

# Clear Gradle cache
rm -rf ~/.gradle/caches/

# Run with debug
gradle --debug --stacktrace
```

### If Build Times Out
```bash
# Increase memory
export GRADLE_OPTS="-Xmx2048m"

# Disable daemon
gradle --no-daemon

# Run with parallel execution
gradle --parallel
```

## Related Documentation

- **PNC Environment API**: https://orch.pnc.engineering.redhat.com/pnc-rest/v2/environments/1551
- **Builder Image Manifest**: https://sbomer.pnc.engineering.redhat.com/api/v1beta1/manifests/9C7CA5E5D7BD434/bom
- **Gradle 7.2 Docs**: https://docs.gradle.org/7.2/release-notes.html
- **OpenJDK 17 Docs**: https://openjdk.org/projects/jdk/17/

## Summary

Environment 1551 is the **ideal choice** for building Ehcache 3.12.0 because:

1. ✅ **Java 17 pre-installed** - No download, no timeout
2. ✅ **Gradle 7.2 included** - Perfect version match
3. ✅ **RHEL 8 base** - Modern, stable platform
4. ✅ **Jackson compatible** - Handles Java 21 bytecode
5. ✅ **Fast builds** - No setup overhead
6. ✅ **Reliable** - No network dependencies

**Use this environment for all Ehcache 3.12.0 builds.**

---

**Last Updated**: 2026-08-26  
**Environment Status**: Active  
**Recommended**: ✅ Yes
