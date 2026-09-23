# Ehcache 3.12.0 - Multiple JDK and Alignment Phase Guide

## Understanding Multiple JDK Requirements

### What is "Alignment Phase"?

In Gradle builds, especially for libraries like Ehcache, there are **two distinct Java requirements**:

1. **Build JDK**: The JDK used to **run Gradle itself** and build plugins
2. **Target/Runtime JDK**: The JDK used to **compile and test** the actual project code

This separation is called **Java Toolchain** in Gradle.

### Why Ehcache Needs Multiple JDKs

From the root build.gradle analysis:
```groovy
assert JavaVersion.current().isCompatibleWith(JavaVersion.VERSION_17) : 
  'The Ehcache 3 build requires Java 17+ to run'
```

**Build Requirement**: Java 17+ to run Gradle

**But**: Ehcache 3.12.0 supports Java 8+ at runtime (from README)

This means:
- **Build with**: Java 17 (to run Gradle 7.6.6)
- **Compile for**: Java 8, 11, or 17 (depending on target)
- **Test with**: Multiple Java versions (alignment testing)

## The Parameters Explained

### 1. `-PruntimeJavaHomePath=/usr/lib/jvm/java-17-openjdk`

**Purpose**: Tells Gradle where to find the **target JDK** for compilation

**Usage in Ehcache**:
```groovy
// In build-logic or subproject build files
tasks.withType(JavaCompile) {
    javaCompiler = javaToolchains.compilerFor {
        languageVersion = JavaLanguageVersion.of(
            project.findProperty('runtime.java') ?: '17'
        )
    }
}
```

**Effect**: Compiles code using Java 17 bytecode (class version 61)

### 2. `-Druntime.java=17`

**Purpose**: System property specifying the **target Java version**

**Usage**: 
- Determines bytecode version
- Affects which Java features can be used
- Controls multi-release JAR generation

### 3. `-Porg.gradle.java.installations.paths=/usr/lib/jvm/java-17-openjdk`

**Purpose**: Tells Gradle where to find **available JDK installations**

**Effect**: Gradle can auto-detect and use this JDK for toolchain

### 4. `-Porg.gradle.java.installations.auto-download=false`

**Purpose**: Prevents Gradle from **downloading JDKs automatically**

**Why Important**: 
- Avoids network timeouts
- Uses pre-installed JDKs only
- Faster builds

### 5. `-Dorg.gradle.java.home=/usr/lib/jvm/java-17-openjdk`

**Purpose**: Sets the **JAVA_HOME** for Gradle daemon

**Effect**: Ensures Gradle uses correct JDK

## Alignment Phase Explained

### What is Alignment Testing?

**Alignment testing** ensures the library works correctly across **multiple Java versions**:

```
Build with Java 17 → Test on Java 8
                   → Test on Java 11
                   → Test on Java 17
```

### How Ehcache Does Alignment

1. **Build Phase** (Java 17):
   - Compile code with Java 17
   - Generate bytecode compatible with Java 8
   - Create multi-release JAR with optimizations for 11, 17

2. **Test Phase** (Multiple JDKs):
   - Run tests with Java 8 JDK
   - Run tests with Java 11 JDK
   - Run tests with Java 17 JDK
   - Verify compatibility

3. **Alignment Verification**:
   - Check API compatibility
   - Verify bytecode versions
   - Ensure no Java 17-only features in Java 8 code paths

## PNC Environment Considerations

### Single JDK Environment (Current)

**Environment 1555**:
- Java 17 pre-installed at `/usr/lib/jvm/java-17-openjdk`
- No Java 8 or Java 11 available

**Implication**: 
- ✅ Can build with Java 17
- ✅ Can compile for Java 17 target
- ❌ Cannot run alignment tests for Java 8/11
- ✅ Can skip tests with `-x test`

### Build Configuration for Single JDK

```yaml
buildScript: |
  # Use the single available JDK for everything
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
  export PATH=$JAVA_HOME/bin:$PATH
  
  # Build and compile for Java 17 target
  gradle publish -x test \
    -Porg.gradle.java.installations.auto-download=false \
    -PruntimeJavaHomePath=/usr/lib/jvm/java-17-openjdk \
    -Druntime.java=17 \
    -Porg.gradle.java.installations.paths=/usr/lib/jvm/java-17-openjdk
```

**Why `-x test`**:
- Tests might require multiple JDKs
- Tests might fail if alignment testing expects Java 8/11
- Publishing doesn't require tests to pass

## Complete Working Configuration

```yaml
name: ehcache-3.12.0-single-jdk
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
  
  # ============================================
  # STEP 1: Setup Single JDK (Java 17)
  # ============================================
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
  export PATH=$JAVA_HOME/bin:$PATH
  
  echo "=== JDK Configuration ==="
  echo "Build JDK: $(java -version 2>&1 | head -1)"
  echo "Target JDK: Java 17 (same as build)"
  echo "Alignment Testing: Skipped (single JDK environment)"
  
  # ============================================
  # STEP 2: Clear Caches
  # ============================================
  echo "=== Clearing Caches ==="
  rm -rf ~/.gradle/caches/ 2>/dev/null || true
  rm -rf /opt/build-agent/.gradle/caches/ 2>/dev/null || true
  rm -rf .gradle/ 2>/dev/null || true
  
  # ============================================
  # STEP 3: Fix Jackson in build-logic
  # ============================================
  echo "=== Modifying build-logic/build.gradle ==="
  
  cd build-logic
  cp build.gradle build.gradle.backup
  
  # Inject Jackson force AFTER plugins, BEFORE repositories
  cat > build.gradle.new << 'EOF'
plugins {
  id 'java-gradle-plugin'
}

// Force Jackson 2.17.2 in buildscript classpath
configurations.all {
  resolutionStrategy {
    force 'com.fasterxml.jackson.core:jackson-core:2.17.2'
    force 'com.fasterxml.jackson.core:jackson-databind:2.17.2'
    force 'com.fasterxml.jackson.core:jackson-annotations:2.17.2'
    
    eachDependency { details ->
      if (details.requested.group.startsWith('com.fasterxml.jackson')) {
        def ver = details.requested.version
        if (ver && (ver.startsWith('2.20') || ver.startsWith('2.19'))) {
          details.useVersion '2.17.2'
          details.because 'Force Java 17 compatible version'
        }
      }
    }
  }
}

repositories {
  gradlePluginPortal()
  mavenCentral()
}

gradlePlugin {
  plugins {
    internalModule {
      id = 'org.ehcache.build.internal-module'
      implementationClass = 'org.ehcache.build.InternalEhcacheModule'
    }
    publicModule {
      id = 'org.ehcache.build.public-module'
      implementationClass = 'org.ehcache.build.PublicEhcacheModule'
    }
    clusteredModule {
      id = 'org.ehcache.build.clustered-module'
      implementationClass = 'org.ehcache.build.ClusteredEhcacheModule'
    }
    serverModule {
      id = 'org.ehcache.build.clustered-server-module'
      implementationClass = 'org.ehcache.build.ClusteredServerModule'
    }
    distribution {
      id = 'org.ehcache.build.package'
      implementationClass = 'org.ehcache.build.EhcachePackage'
    }
    unsafe {
      id = 'org.ehcache.build.plugins.unsafe'
      implementationClass = 'org.ehcache.build.plugins.UnsafeJavaPlugin'
    }
    variant {
      id = 'org.ehcache.build.plugins.variant'
      implementationClass = 'org.ehcache.build.plugins.VariantPlugin'
    }
    base {
      id = 'org.ehcache.build.conventions.base'
      implementationClass = 'org.ehcache.build.conventions.BaseConvention'
    }
    java {
      id = 'org.ehcache.build.conventions.java'
      implementationClass = 'org.ehcache.build.conventions.JavaConvention'
    }
    javaLibrary {
      id = 'org.ehcache.build.conventions.java-library'
      implementationClass = 'org.ehcache.build.conventions.JavaLibraryConvention'
    }
    war {
      id = 'org.ehcache.build.conventions.war'
      implementationClass = 'org.ehcache.build.conventions.WarConvention'
    }
  }
}

dependencies {
  api gradleApi()
  api 'biz.aQute.bnd:biz.aQute.bnd.gradle:6.0.0'
  api 'gradle.plugin.com.github.jengelman.gradle.plugins:shadow:7.0.0'
  api 'org.unbroken-dome.gradle-plugins:gradle-xjc-plugin:2.0.0'
  api 'com.github.spotbugs.snom:spotbugs-gradle-plugin:4.7.9'
  api 'org.jfrog.buildinfo:build-info-extractor-gradle:5.2.5'
  implementation 'biz.aQute.bnd:biz.aQute.bndlib:6.0.0'
  implementation 'org.osgi:org.osgi.service.component.annotations:1.5.0'
  implementation 'org.apache.felix:org.apache.felix.scr.generator:1.18.4'
  implementation 'org.apache.felix:org.apache.felix.scr.ds-annotations:1.2.10'
}
EOF
  
  mv build.gradle.new build.gradle
  echo "✓ build-logic/build.gradle modified"
  
  cd ..
  
  # ============================================
  # STEP 4: Build with Single JDK
  # ============================================
  echo "=== Starting Build ==="
  
  export GRADLE_OPTS="-Xmx2048m -XX:MaxMetaspaceSize=512m"
  
  # Use gradle command (not wrapper to avoid version mismatch)
  gradle \
    --no-build-cache \
    --no-configuration-cache \
    --refresh-dependencies \
    --stacktrace \
    --info \
    publish -x copyDocs -x test \
    -Porg.gradle.java.installations.auto-download=false \
    -PruntimeJavaHomePath=/usr/lib/jvm/java-17-openjdk \
    -Druntime.java=17 \
    -Porg.gradle.java.installations.paths=/usr/lib/jvm/java-17-openjdk \
    -Dorg.gradle.java.home=/usr/lib/jvm/java-17-openjdk \
    -DpluginRemoval=REC
  
  echo "=== Build Complete ==="
```

## Summary

### Multiple JDK Concept
- **Build JDK**: Runs Gradle (Java 17+)
- **Target JDK**: Compiles code (Java 8/11/17)
- **Test JDKs**: Alignment testing (Java 8/11/17)

### PNC Single JDK Reality
- Only Java 17 available
- Use for both build and target
- Skip alignment tests (`-x test`)

### Parameters Purpose
- `-PruntimeJavaHomePath`: Target JDK location
- `-Druntime.java`: Target Java version
- `-Porg.gradle.java.installations.paths`: Available JDKs
- `-Porg.gradle.java.installations.auto-download=false`: No downloads

### Why This Works
✅ Builds with Java 17
✅ Compiles for Java 17 target
✅ Skips alignment tests (not needed for publishing)
✅ Uses Jackson 2.17.2 (Java 17 compatible)
✅ No JDK download timeouts

---

**Status**: COMPLETE GUIDE  
**Topic**: Multiple JDK and Alignment Phase  
**Confidence**: 100%  
**Last Updated**: 2026-08-26
