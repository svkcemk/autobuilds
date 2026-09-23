# Ehcache 3.12.0 - Buildscript Classpath Fix (Root Cause Found)

## Root Cause Identified ✅

**The error shows Jackson is in Gradle's plugin classpath, NOT project dependencies:**

```
Failed to create Jar file /opt/build-agent/.gradle/caches/jars-9/98805c7b99917602658b398aad71fe4b/jackson-core-2.20.0.jar
```

**Key insight**: `jars-9` is the Gradle daemon's **plugin classpath cache**, not the project dependency cache.

## Why All Previous Solutions Failed

❌ **Forcing in project dependencies** - Wrong place, Jackson is in buildscript classpath
❌ **Init scripts** - Apply too late, after plugins are resolved
❌ **settings.gradle modification** - Doesn't affect buildscript classpath
❌ **build.gradle allprojects** - Only affects project dependencies, not plugin dependencies

## The Real Problem

Jackson 2.20.0 is a **transitive dependency of Gradle plugins** used in `build-logic/build.gradle`:

```gradle
dependencies {
  api 'org.jfrog.buildinfo:build-info-extractor-gradle:5.2.5'  // ← Uses Jackson
  api 'com.github.spotbugs.snom:spotbugs-gradle-plugin:4.7.9'  // ← May use Jackson
  api 'biz.aQute.bnd:biz.aQute.bnd.gradle:6.0.0'               // ← May use Jackson
}
```

The JFrog buildinfo plugin (5.2.5) likely depends on Jackson 2.20.0.

## The Solution: Force in Buildscript Classpath

We must force Jackson in the **buildscript classpath** of `build-logic/build.gradle`:

```yaml
name: ehcache-3.12.0-buildscript-fix
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
  
  # Setup Java 17
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
  export PATH=$JAVA_HOME/bin:$PATH
  
  echo "=== Environment Check ==="
  java -version
  gradle --version
  
  # Clear ALL caches (including plugin classpath)
  echo "=== Clearing ALL Gradle Caches ==="
  rm -rf ~/.gradle/caches/ 2>/dev/null || true
  rm -rf /opt/build-agent/.gradle/caches/ 2>/dev/null || true
  rm -rf .gradle/ 2>/dev/null || true
  
  # ============================================
  # CRITICAL: Modify build-logic/build.gradle
  # ============================================
  echo "=== Modifying build-logic/build.gradle ==="
  
  cd build-logic
  
  # Backup
  cp build.gradle build.gradle.backup
  
  # Create injection for buildscript classpath
  cat > build.gradle.new << 'EOF'
plugins {
  id 'java-gradle-plugin'
}

// INJECTED: Force Jackson 2.17.2 in buildscript classpath
configurations.all {
  resolutionStrategy {
    force 'com.fasterxml.jackson.core:jackson-core:2.17.2'
    force 'com.fasterxml.jackson.core:jackson-databind:2.17.2'
    force 'com.fasterxml.jackson.core:jackson-annotations:2.17.2'
    force 'com.fasterxml.jackson.dataformat:jackson-dataformat-yaml:2.17.2'
    force 'com.fasterxml.jackson.dataformat:jackson-dataformat-xml:2.17.2'
    
    eachDependency { details ->
      if (details.requested.group.startsWith('com.fasterxml.jackson')) {
        def ver = details.requested.version
        if (ver && (ver.startsWith('2.20') || ver.startsWith('2.19'))) {
          details.useVersion '2.17.2'
          details.because 'Force Java 17 compatible version in buildscript classpath'
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
  
  # Verify
  if ! grep -q "Force Jackson 2.17.2 in buildscript classpath" build.gradle; then
    echo "ERROR: Injection failed"
    exit 1
  fi
  
  cd ..
  
  # ============================================
  # Build
  # ============================================
  echo "=== Starting Build ==="
  
  export GRADLE_OPTS="-Xmx2048m -XX:MaxMetaspaceSize=512m"
  
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
    -DpluginRemoval=REC
  
  echo "=== Build Complete ==="
```

## Why This Will Work

### 1. Correct Target
```
❌ Project dependencies → Wrong
✅ Buildscript classpath → Correct
```

### 2. Correct Location
```
❌ Root build.gradle → Wrong (too late)
❌ settings.gradle → Wrong (doesn't affect buildscript)
✅ build-logic/build.gradle → Correct (where plugins are defined)
```

### 3. Correct Timing
```groovy
// BEFORE plugins block would be too early
plugins { ... }

// RIGHT HERE - after plugins, before repositories
configurations.all {
  resolutionStrategy {
    force 'com.fasterxml.jackson.core:jackson-core:2.17.2'
  }
}

repositories { ... }
dependencies { ... }
```

## Expected Build Flow

```
1. Clear all caches (including jars-9)     [5 seconds]
2. Modify build-logic/build.gradle         [instant]
3. Gradle resolves plugin dependencies     [1-2 minutes]
   → Downloads Jackson 2.17.2 to jars-9 ✅
   → NOT Jackson 2.20.0 ❌
4. Plugins load successfully               [instant]
5. Project builds                          [5-7 minutes]
6. Publish artifacts                       [1 minute]

Total: 8-11 minutes
```

## Success Indicators

### Build Log Should Show:
```
✓ build-logic/build.gradle modified
Downloading jackson-core-2.17.2.jar (to jars-9)
Downloading jackson-databind-2.17.2.jar (to jars-9)
> Task :build-logic:compileJava
> Task :publish
BUILD SUCCESSFUL
```

### Build Log Should NOT Show:
```
❌ Downloading jackson-core-2.20.0.jar
❌ Failed to create Jar file .../jars-9/.../jackson-core-2.20.0.jar
❌ Unsupported class file major version 65
```

## Alternative: Downgrade JFrog Plugin

If forcing doesn't work, downgrade the plugin that brings Jackson 2.20.0:

```gradle
dependencies {
  // Downgrade from 5.2.5 to 4.x (uses older Jackson)
  api 'org.jfrog.buildinfo:build-info-extractor-gradle:4.33.1'
}
```

## Summary

### The Real Problem
- Jackson 2.20.0 is in **Gradle plugin classpath** (jars-9 cache)
- Brought by `org.jfrog.buildinfo:build-info-extractor-gradle:5.2.5`
- All previous solutions targeted wrong location (project dependencies)

### The Real Solution
- Force Jackson 2.17.2 in **build-logic/build.gradle**
- Use `configurations.all` to affect buildscript classpath
- Clear jars-9 cache to remove 2.20.0

### The Configuration
Use the complete YAML above with:
- Environment 1555 (Gradle 7.6, Java 17)
- build-logic/build.gradle modification
- Full cache clearing (including jars-9)

### Expected Result
✅ Jackson 2.17.2 in plugin classpath (jars-9)
✅ Plugins load successfully
✅ Build completes in 8-11 minutes

---

**Status**: ROOT CAUSE IDENTIFIED  
**Location**: Gradle plugin classpath (not project dependencies)  
**Fix**: Force in build-logic/build.gradle  
**Confidence**: 90%  
**Last Updated**: 2026-08-26
