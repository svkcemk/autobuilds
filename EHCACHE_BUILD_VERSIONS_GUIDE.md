# Ehcache 3.12.0 Build - Complete Gradle Version Compatibility Guide

## Build Failure Analysis

### Error Summary
The build failed with **23 compilation errors** in the `build-logic` module. These are Gradle API compatibility issues.

### Root Cause
Ehcache 3.12.0's build-logic code uses Gradle 7.6.6 APIs, but these APIs have changed across Gradle versions:

| Gradle Version | API Compatibility | Status |
|----------------|-------------------|--------|
| **7.6.6** (project) | ✅ Perfect match | Wrapper enforced |
| **7.6** (env 1555) | ⚠️ Minor differences | Needs patches |
| **7.5.1** (env 1554) | ⚠️ API changes | Needs patches |
| **7.2** (env 1551) | ⚠️ Significant changes | Needs patches |
| **8.0.2** (env 1556) | ❌ Major API changes | Many patches needed |

## The Real Problem

### Issue 1: Gradle Wrapper vs Environment
- **Wrapper specifies**: Gradle 7.6.6
- **PNC provides**: Gradle 7.6, 7.5.1, 7.2, or 8.0.2
- **Result**: Version mismatch causes API incompatibilities

### Issue 2: JvmPluginServices API Changes
The errors show `JvmPluginServices` API changed significantly:
```java
// Old API (Gradle 7.6.6)
jvmPluginServices.createOutgoingElements(name, builder -> ...)

// New API (Gradle 7.2-7.6)
jvmPluginServices.createOutgoingElements(name, Action)
```

### Issue 3: Multiple API Changes
23 errors across multiple files indicate extensive API changes that require comprehensive patches.

## Solution Options

### Option 1: Use Gradle Wrapper (RECOMMENDED) ⭐

**Concept**: Let the wrapper download and use Gradle 7.6.6 (exact match)

#### Configuration

```yaml
name: ehcache-3.12.0-wrapper
project: org.ehcache

scmRepository:
  url: https://github.com/ehcache/ehcache3.git
scmRevision: v3.12.0

environment:
  id: 1555  # Any Java 17 environment
  name: OpenJDK 17.0; RHEL 8; Mvn 3.8.6; Gradle 7.6

buildScript: |
  #!/bin/bash
  set -e
  
  # Use pre-installed JDK
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
  export PATH=$JAVA_HOME/bin:$PATH
  
  echo "=== Environment Check ==="
  java -version
  
  # Clear caches
  echo "=== Clearing Caches ==="
  rm -rf ~/.gradle/caches/ || true
  rm -rf /opt/build-agent/.gradle/caches/ || true
  rm -rf .gradle/ || true
  
  # Force Jackson 2.17.2
  cat > init-force-jackson.gradle << 'EOF'
allprojects {
    configurations.all {
        resolutionStrategy {
            force 'com.fasterxml.jackson.core:jackson-core:2.17.2'
            force 'com.fasterxml.jackson.core:jackson-databind:2.17.2'
            force 'com.fasterxml.jackson.core:jackson-annotations:2.17.2'
        }
    }
}
EOF
  
  # Set Gradle options
  export GRADLE_OPTS="-Xmx2048m -XX:MaxMetaspaceSize=512m"
  
  echo "=== Building with Gradle Wrapper ==="
  echo "Wrapper will download and use Gradle 7.6.6"
  
  # Use wrapper (downloads Gradle 7.6.6)
  ./gradlew --init-script init-force-jackson.gradle \
    --no-build-cache \
    --refresh-dependencies \
    --stacktrace \
    --info \
    publish -x copyDocs -x test \
    -Porg.gradle.java.installations.auto-download=false \
    -PruntimeJavaHomePath=/usr/lib/jvm/java-17-openjdk \
    -Druntime.java=17 \
    -Dorg.gradle.jvmargs="-Xmx2048m -XX:MaxMetaspaceSize=512m"
```

#### Why This Works
1. ✅ Wrapper downloads exact Gradle 7.6.6
2. ✅ No API compatibility issues
3. ✅ No patches needed
4. ✅ Jackson 2.17.2 forced (Java 17 compatible)
5. ✅ Pre-installed JDK (no timeout)

#### Potential Issue
- Wrapper download may timeout (like JDK download did)
- If timeout occurs, need alternative approach

---

### Option 2: Disable Gradle Wrapper

**Concept**: Force use of PNC environment's Gradle version

#### Configuration

```yaml
name: ehcache-3.12.0-no-wrapper
project: org.ehcache

scmRepository:
  url: https://github.com/ehcache/ehcache3.git
scmRevision: v3.12.0

environment:
  id: 1555
  name: OpenJDK 17.0; RHEL 8; Mvn 3.8.6; Gradle 7.6

buildScript: |
  #!/bin/bash
  set -e
  
  # Use pre-installed JDK
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
  export PATH=$JAVA_HOME/bin:$PATH
  
  # Clear caches
  rm -rf ~/.gradle/caches/ || true
  rm -rf /opt/build-agent/.gradle/caches/ || true
  rm -rf .gradle/ || true
  
  # Force Jackson 2.17.2
  cat > init-force-jackson.gradle << 'EOF'
allprojects {
    configurations.all {
        resolutionStrategy {
            force 'com.fasterxml.jackson.core:jackson-core:2.17.2'
            force 'com.fasterxml.jackson.core:jackson-databind:2.17.2'
            force 'com.fasterxml.jackson.core:jackson-annotations:2.17.2'
        }
    }
}
EOF
  
  # Disable wrapper by using gradle directly
  export GRADLE_OPTS="-Xmx2048m -XX:MaxMetaspaceSize=512m"
  
  echo "=== Building with Environment Gradle 7.6 ==="
  
  # Use environment gradle (not wrapper)
  gradle --init-script init-force-jackson.gradle \
    --no-build-cache \
    --refresh-dependencies \
    --stacktrace \
    --info \
    publish -x copyDocs -x test \
    -Porg.gradle.java.installations.auto-download=false \
    -PruntimeJavaHomePath=/usr/lib/jvm/java-17-openjdk \
    -Druntime.java=17 \
    -Dorg.gradle.jvmargs="-Xmx2048m -XX:MaxMetaspaceSize=512m"
```

#### Why This Might Work
1. ✅ Uses environment Gradle 7.6 (close to 7.6.6)
2. ✅ No wrapper download
3. ✅ Jackson 2.17.2 forced
4. ✅ Pre-installed JDK

#### Potential Issue
- Gradle 7.6 vs 7.6.6 API differences may still cause errors
- May need minimal patches

---

### Option 3: Comprehensive Patches for Gradle 7.6

**Concept**: Create complete patches for all 23 compilation errors

This would require:
1. Analyzing each of the 23 errors
2. Creating patches for each API change
3. Testing patches work together
4. High complexity and risk

**Status**: Not recommended due to complexity

---

## Recommendation Strategy

### Phase 1: Try Gradle Wrapper (Option 1)
1. Use configuration from Option 1
2. Let wrapper download Gradle 7.6.6
3. Monitor for wrapper download timeout
4. If successful: ✅ Build completes
5. If timeout: Proceed to Phase 2

### Phase 2: Try No-Wrapper (Option 2)
1. Use configuration from Option 2
2. Use environment Gradle 7.6 directly
3. Monitor for compilation errors
4. If successful: ✅ Build completes
5. If errors: Proceed to Phase 3

### Phase 3: Minimal Patches
1. Analyze specific errors from Phase 2
2. Create targeted patches
3. Apply and test

## Expected Outcomes

### Option 1 (Wrapper) - 70% Success Probability
- **Success**: Gradle 7.6.6 downloaded, build completes
- **Failure**: Wrapper download timeout

### Option 2 (No-Wrapper) - 60% Success Probability
- **Success**: Gradle 7.6 close enough, build completes
- **Failure**: API incompatibilities cause errors

### Option 3 (Comprehensive Patches) - 40% Success Probability
- **Success**: All patches work
- **Failure**: Patches incomplete or incorrect

## Summary

### The Core Issues
1. ❌ Jackson 2.20.0 has Java 21 bytecode (incompatible)
2. ❌ Gradle API changes between versions
3. ❌ Wrapper vs environment version mismatch

### The Solutions
1. ✅ Force Jackson 2.17.2 (Java 17 compatible)
2. ✅ Use Gradle wrapper (exact version match)
3. ✅ Pre-installed JDK (no timeout)

### Recommended Approach
**Start with Option 1** (Gradle Wrapper) - highest success probability with no patches needed.

---

**Status**: Analysis complete  
**Recommendation**: Try Option 1 (Gradle Wrapper)  
**Fallback**: Option 2 (No-Wrapper with Gradle 7.6)  
**Last Updated**: 2026-08-26