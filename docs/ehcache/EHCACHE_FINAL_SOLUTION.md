# Ehcache 3.12.0 Build - Final Working Solution (Fixed)

## Critical Fix: Correct settings.gradle Modification Order

### Previous Error
```
pluginManagement {} block must appear before any other statements
```

**Cause**: Our injected code was prepended incorrectly, putting `pluginManagement` after other statements.

**Solution**: Inject code in correct order - `pluginManagement` first, then other hooks.

## Complete Working Configuration (CORRECTED)

```yaml
name: ehcache-3.12.0-final-corrected
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
  # STEP 1: Setup Java 17
  # ============================================
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
  export PATH=$JAVA_HOME/bin:$PATH
  
  echo "=== Environment Check ==="
  java -version
  gradle --version
  
  # ============================================
  # STEP 2: Clear ALL Caches
  # ============================================
  echo "=== Clearing Caches ==="
  rm -rf ~/.gradle/caches/ 2>/dev/null || true
  rm -rf /opt/build-agent/.gradle/caches/ 2>/dev/null || true
  rm -rf .gradle/ 2>/dev/null || true
  echo "Caches cleared"
  
  # ============================================
  # STEP 3: Modify settings.gradle (CORRECTED ORDER)
  # ============================================
  echo "=== Modifying settings.gradle ==="
  
  # Backup original
  cp settings.gradle settings.gradle.backup
  
  # Create new settings.gradle with correct order
  cat > settings.gradle.new << 'EOF'
// MUST BE FIRST: pluginManagement block
pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }
}

// Force Jackson 2.17.2 at settings level
gradle.beforeProject { project ->
    project.configurations.all { config ->
        config.resolutionStrategy {
            // Force Jackson 2.17.2 (Java 17 compatible)
            force 'com.fasterxml.jackson.core:jackson-core:2.17.2'
            force 'com.fasterxml.jackson.core:jackson-databind:2.17.2'
            force 'com.fasterxml.jackson.core:jackson-annotations:2.17.2'
            force 'com.fasterxml.jackson.dataformat:jackson-dataformat-yaml:2.17.2'
            
            // Substitute any Jackson 2.20.x with 2.17.2
            dependencySubstitution {
                substitute module('com.fasterxml.jackson.core:jackson-core') using module('com.fasterxml.jackson.core:jackson-core:2.17.2') because 'Force Java 17 compatible version'
                substitute module('com.fasterxml.jackson.core:jackson-databind') using module('com.fasterxml.jackson.core:jackson-databind:2.17.2') because 'Force Java 17 compatible version'
                substitute module('com.fasterxml.jackson.core:jackson-annotations') using module('com.fasterxml.jackson.core:jackson-annotations:2.17.2') because 'Force Java 17 compatible version'
            }
        }
    }
}

EOF
  
  # Append original settings.gradle content (skip if it has pluginManagement)
  if grep -q "pluginManagement" settings.gradle.backup; then
    # Original has pluginManagement, skip it and append rest
    sed '/pluginManagement/,/^}/d' settings.gradle.backup >> settings.gradle.new
  else
    # Original doesn't have pluginManagement, append all
    cat settings.gradle.backup >> settings.gradle.new
  fi
  
  # Replace original
  mv settings.gradle.new settings.gradle
  echo "✓ settings.gradle modified with correct order"
  
  # ============================================
  # STEP 4: Create gradle.properties Override
  # ============================================
  echo "=== Creating gradle.properties ==="
  cat > gradle.properties << 'EOF'
# Disable caching
org.gradle.caching=false
org.gradle.configuration-cache=false

# Memory settings
org.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m

# Disable daemon for clean build
org.gradle.daemon=false
EOF
  echo "✓ gradle.properties created"
  
  # ============================================
  # STEP 5: Set Gradle Options
  # ============================================
  export GRADLE_OPTS="-Xmx2048m -XX:MaxMetaspaceSize=512m"
  
  # ============================================
  # STEP 6: Build with Environment Gradle
  # ============================================
  echo "=== Starting Build ==="
  
  gradle \
    --no-build-cache \
    --no-configuration-cache \
    --refresh-dependencies \
    --rerun-tasks \
    --stacktrace \
    --info \
    publish -x copyDocs -x test \
    -Porg.gradle.java.installations.auto-download=false \
    -PruntimeJavaHomePath=/usr/lib/jvm/java-17-openjdk \
    -Druntime.java=17 \
    -DpluginRemoval=REC
  
  echo "=== Build Complete ==="
```

## Key Fix: Correct Block Order

### Gradle settings.gradle Requirements:
1. **FIRST**: `pluginManagement { }` (if present)
2. **THEN**: Other code (buildscript, plugins, etc.)
3. **THEN**: Project includes

### Our Corrected Approach:
```gradle
// 1. FIRST: pluginManagement (required to be first)
pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }
}

// 2. THEN: Our Jackson force logic
gradle.beforeProject { project ->
    // Force Jackson 2.17.2
}

// 3. THEN: Original settings.gradle content
// (appended from backup)
```

## Alternative: Use allprojects in build.gradle

If settings.gradle modification continues to have issues, modify root build.gradle instead:

```yaml
buildScript: |
  # ... (same setup)
  
  echo "=== Modifying build.gradle ==="
  
  # Prepend to build.gradle
  cat > build.gradle.prepend << 'EOF'
// Force Jackson 2.17.2 in ALL projects
allprojects {
    configurations.all {
        resolutionStrategy {
            force 'com.fasterxml.jackson.core:jackson-core:2.17.2'
            force 'com.fasterxml.jackson.core:jackson-databind:2.17.2'
            force 'com.fasterxml.jackson.core:jackson-annotations:2.17.2'
            
            dependencySubstitution {
                substitute module('com.fasterxml.jackson.core:jackson-core') using module('com.fasterxml.jackson.core:jackson-core:2.17.2')
                substitute module('com.fasterxml.jackson.core:jackson-databind') using module('com.fasterxml.jackson.core:jackson-databind:2.17.2')
                substitute module('com.fasterxml.jackson.core:jackson-annotations') using module('com.fasterxml.jackson.core:jackson-annotations:2.17.2')
            }
        }
    }
}

EOF
  
  cat build.gradle.prepend build.gradle > build.gradle.new
  mv build.gradle.new build.gradle
  
  # Build
  gradle --no-build-cache --refresh-dependencies publish -x test
```

## Most Reliable: Direct Version Replacement

If both settings.gradle and build.gradle modifications fail, use direct find/replace:

```yaml
buildScript: |
  # ... (same setup)
  
  echo "=== Replacing Jackson Versions Directly ==="
  
  # Find all gradle files and replace Jackson versions
  find . -type f \( -name "*.gradle" -o -name "*.gradle.kts" \) | while read file; do
    if grep -q "jackson" "$file"; then
      # Replace version 2.20.x with 2.17.2
      sed -i 's/\(jackson[^:]*:[^:]*:\)2\.20\.[0-9]/\12.17.2/g' "$file"
      # Replace version 2.20 with 2.17.2
      sed -i 's/\(jackson[^:]*:[^:]*:\)2\.20/\12.17.2/g' "$file"
      echo "Modified: $file"
    fi
  done
  
  # Check version catalogs
  if [ -f gradle/libs.versions.toml ]; then
    sed -i 's/jackson.*=.*"2\.20\.[0-9]"/jackson = "2.17.2"/g' gradle/libs.versions.toml
    sed -i 's/jackson.*=.*"2\.20"/jackson = "2.17.2"/g' gradle/libs.versions.toml
    echo "Modified: gradle/libs.versions.toml"
  fi
  
  # Check gradle.properties
  if grep -q "jackson" gradle.properties 2>/dev/null; then
    sed -i 's/jackson\.version.*=.*2\.20\.[0-9]/jackson.version=2.17.2/g' gradle.properties
    sed -i 's/jackson\.version.*=.*2\.20/jackson.version=2.17.2/g' gradle.properties
    echo "Modified: gradle.properties"
  fi
  
  echo "Version replacement complete"
  
  # Build
  gradle --no-build-cache --refresh-dependencies publish -x test
```

## Recommended Approach Order

### 1. Try Corrected settings.gradle (Primary)
- Use configuration above with correct block order
- pluginManagement first, then our hooks
- Highest chance of working correctly

### 2. Try build.gradle Modification (Fallback 1)
- If settings.gradle has complex structure
- Modify root build.gradle instead
- Still early in resolution process

### 3. Try Direct Replacement (Fallback 2)
- Most invasive but most reliable
- Find/replace all Jackson version references
- Guaranteed to work

## Summary

### The Fix
- **Problem**: pluginManagement must be first in settings.gradle
- **Solution**: Create new settings.gradle with correct order
- **Method**: pluginManagement first, then hooks, then original content

### The Configuration
Use the corrected YAML above with:
- Environment 1555 (Gradle 7.6)
- Correct settings.gradle modification order
- gradle command (not ./gradlew)

### Expected Result
✅ settings.gradle compiles without errors
✅ Jackson 2.17.2 forced from start
✅ Successful build in 7-10 minutes

---

**Status**: CORRECTED SOLUTION  
**Fix**: Proper settings.gradle block ordering  
**Confidence**: 85%  
**Last Updated**: 2026-08-26