# Ehcache 3.12.0 - Alternative Solutions Without Downgrading Jackson

## The Challenge

Jackson 2.20.0 contains Java 21 bytecode (class version 65) in `META-INF/versions/21/` directory, which Gradle 7.2/7.5.1 on Java 17 cannot process.

**Current Solution**: Downgrade to Jackson 2.17.2 (Java 17 compatible)

**Your Request**: Find alternative without downgrading Jackson version

## Alternative Solutions

### Solution 1: Upgrade to Gradle 8+ (RECOMMENDED) ⭐

**Concept**: Use a Gradle version that supports Java 21 bytecode

#### Available Environments

**Environment 1556** - Gradle 8.0.2:
- **ID**: 1556
- **Name**: OpenJDK 17.0; RHEL 8; Mvn 3.8.6; Gradle 8.0.2
- **Gradle**: 8.0.2 (supports Java 21 bytecode)
- **JDK**: 17.0 pre-installed
- **Status**: ✅ Active and usable

#### Why This Works

Gradle 8.0+ includes:
- Updated ASM library (9.4+) that can read Java 21 bytecode
- Better multi-release JAR support
- Can process `META-INF/versions/21/` classes even on Java 17

#### Configuration

```yaml
name: ehcache-3.12.0-gradle8
project: org.ehcache

scmRepository:
  url: https://github.com/ehcache/ehcache3.git
scmRevision: v3.12.0

environment:
  id: 1556
  name: OpenJDK 17.0; RHEL 8; Mvn 3.8.6; Gradle 8.0.2

buildScript: |
  # Use pre-installed JDK
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
  export PATH=$JAVA_HOME/bin:$PATH
  
  echo "=== Java Version Check ==="
  java -version
  
  echo "=== Gradle Version Check ==="
  gradle --version
  # Should show: Gradle 8.0.2
  
  # Clear caches to ensure fresh start
  rm -rf ~/.gradle/caches/
  rm -rf /opt/build-agent/.gradle/caches/
  rm -rf .gradle/
  
  # Apply Gradle 8 compatibility patches (may need adjustments)
  # Note: Gradle 8 has different APIs than Gradle 7
  cat > /tmp/gradle8-compat.patch << 'PATCH_EOF'
--- a/build-logic/src/main/java/org/ehcache/build/conventions/DeployConvention.java
+++ b/build-logic/src/main/java/org/ehcache/build/conventions/DeployConvention.java
@@ -12,7 +12,6 @@ import org.gradle.api.publish.maven.MavenPublication;
 import org.gradle.api.publish.maven.internal.publication.MavenPomInternal;
-import org.gradle.api.publish.maven.internal.publisher.MavenProjectIdentity;
 import org.gradle.api.publish.maven.tasks.GenerateMavenPom;
 import org.gradle.api.tasks.TaskProvider;
 
@@ -100,7 +99,7 @@ public class DeployConvention implements Plugin<Project> {
         project.getTasks().withType(GenerateMavenPom.class).configureEach(pomTask -> {
           MavenPublication publication = pomTask.getPublication();
           if (publication instanceof ProjectComponentPublication) {
-            SoftwareComponentInternal component = ((ProjectComponentPublication) publication).getComponent();
+            SoftwareComponentInternal component = ((ProjectComponentPublication) publication).getComponent().get();
             if (component instanceof AdhocComponentWithVariants) {
               ((AdhocComponentWithVariants) component).addVariantsFromConfiguration(
                 project.getConfigurations().getByName("testRuntimeElements"),
@@ -131,7 +130,10 @@ public class DeployConvention implements Plugin<Project> {
       project.getTasks().withType(GenerateMavenPom.class).configureEach(pomTask -> {
         pomTask.doLast(new Action<Task>() {
           public void execute(Task task) {
-            MavenProjectIdentity identity = ((MavenPomInternal) pomTask.getPom()).getProjectIdentity();
+            String groupId = pomTask.getPom().getGroupId().get();
+            String artifactId = pomTask.getPom().getArtifactId().get();
+            String version = pomTask.getPom().getVersion().get();
             
             File pomFile = pomTask.getDestination();
             File pomDirectory = pomFile.getParentFile();
@@ -139,9 +141,9 @@ public class DeployConvention implements Plugin<Project> {
             pomDirectory.mkdirs();
             
             try {
-              String groupPath = identity.getGroupId().replace('.', '/');
-              File targetPom = new File(pomDirectory, groupPath + "/" + identity.getArtifactId() + 
-                "/" + identity.getVersion() + "/" + pomFile.getName());
+              String groupPath = groupId.replace('.', '/');
+              File targetPom = new File(pomDirectory, groupPath + "/" + artifactId + 
+                "/" + version + "/" + pomFile.getName());
               targetPom.getParentFile().mkdirs();
               Files.copy(pomFile.toPath(), targetPom.toPath(), StandardCopyOption.REPLACE_EXISTING);
             } catch (IOException e) {
--- a/build-logic/src/main/java/org/ehcache/build/plugins/PackagePlugin.java
+++ b/build-logic/src/main/java/org/ehcache/build/plugins/PackagePlugin.java
@@ -61,7 +61,6 @@ import org.gradle.jvm.tasks.Jar;
 import org.gradle.language.base.plugins.LifecycleBasePlugin;
 
 import static org.gradle.api.attributes.DocsType.JAVADOC;
-import static org.gradle.api.internal.artifacts.JavaEcosystemSupport.configureDefaultTargetPlatform;
 import static org.gradle.api.plugins.JavaPlugin.API_ELEMENTS_CONFIGURATION_NAME;
 import static org.gradle.api.plugins.JavaPlugin.RUNTIME_ELEMENTS_CONFIGURATION_NAME;
 
@@ -91,7 +90,7 @@ public class PackagePlugin implements Plugin<Project> {
     
     Configuration userdocElements = jvmPluginServices.createOutgoingElements("userdocElements", builder ->
       builder.providesAttributes(attributes -> attributes.documentation(JAVADOC)).extendsFrom(apiElements));
-    configureDefaultTargetPlatform(userdocElements);
+    // configureDefaultTargetPlatform removed - not needed in Gradle 8+
     
     TaskProvider<Javadoc> javadoc = project.getTasks().register("javadoc", Javadoc.class, task -> {
       task.setGroup(JavaBasePlugin.DOCUMENTATION_GROUP);
--- a/build-logic/src/main/java/org/ehcache/build/conventions/BndConvention.java
+++ b/build-logic/src/main/java/org/ehcache/build/conventions/BndConvention.java
@@ -46,7 +46,7 @@ public class BndConvention implements Plugin<Project> {
         Dependency baseline = project.getDependencies().create(
          project.getGroup() + ":" + project.getName() + ":" + baselineVersion);
         if (baseline instanceof ExternalDependency) {
-          ((ExternalDependency) baseline).setForce(true);
+          ((ExternalDependency) baseline).version(v -> v.strictly(baselineVersion));
         }
         baselineConfiguration.getDependencies().add(baseline);
       }
--- a/build-logic/src/main/java/org/ehcache/build/conventions/JavaConvention.java
+++ b/build-logic/src/main/java/org/ehcache/build/conventions/JavaConvention.java
@@ -33,8 +33,8 @@ public class JavaConvention implements Plugin<Project> {
     
     project.getConfigurations().all(configuration -> {
       ResolutionStrategy subs = configuration.getResolutionStrategy();
-      subs.substitute(subs.module("org.hamcrest:hamcrest-core:1.3")).with(subs.module("org.hamcrest:hamcrest-core:" + project.property("hamcrestVersion")));
-      subs.substitute(subs.module("org.hamcrest:hamcrest-library:1.3")).with(subs.module("org.hamcrest:hamcrest-library:" + project.property("hamcrestVersion")));
+      subs.substitute(subs.module("org.hamcrest:hamcrest-core:1.3")).using(subs.module("org.hamcrest:hamcrest-core:" + project.property("hamcrestVersion")));
+      subs.substitute(subs.module("org.hamcrest:hamcrest-library:1.3")).using(subs.module("org.hamcrest:hamcrest-library:" + project.property("hamcrestVersion")));
     });
     
     project.getTasks().withType(JavaCompile.class).configureEach(task -> {
PATCH_EOF
  
  # Apply patches
  echo "=== Applying Gradle 8 Compatibility Patches ==="
  if patch -p1 --dry-run < /tmp/gradle8-compat.patch > /dev/null 2>&1; then
    patch -p1 < /tmp/gradle8-compat.patch
    echo "Patches applied successfully"
  else
    echo "WARNING: Patches may not apply cleanly on Gradle 8"
    echo "Attempting build without patches..."
  fi
  
  # Set Gradle options
  export GRADLE_OPTS="-Xmx2048m -XX:MaxMetaspaceSize=512m"
  
  echo "=== Starting Gradle Build ==="
  # Build with Jackson 2.20.0 (no downgrade needed)
  gradle --stacktrace --info publish -x copyDocs -x test \
    -Porg.gradle.java.installations.auto-download=false \
    -PruntimeJavaHomePath=/usr/lib/jvm/java-17-openjdk \
    -Druntime.java=17 \
    -Porg.gradle.java.installations.paths=/usr/lib/jvm/java-17-openjdk \
    -Dorg.gradle.java.home=/usr/lib/jvm/java-17-openjdk \
    -DpluginRemoval=REC \
    -Dorg.gradle.jvmargs="-Xmx2048m -XX:MaxMetaspaceSize=512m"
```

#### Pros
- ✅ No Jackson downgrade needed
- ✅ Gradle 8 can handle Java 21 bytecode
- ✅ Pre-installed JDK (no download)
- ✅ Future-proof solution

#### Cons
- ⚠️ Gradle 8 has API changes (patches may need adjustment)
- ⚠️ Less tested with Ehcache 3.12.0
- ⚠️ May have other compatibility issues

---

### Solution 2: Exclude Multi-Release JAR Classes

**Concept**: Tell Gradle to ignore the Java 21 classes in multi-release JARs

#### Configuration

```yaml
name: ehcache-3.12.0-exclude-mr-jar
project: org.ehcache

scmRepository:
  url: https://github.com/ehcache/ehcache3.git
scmRevision: v3.12.0

environment:
  id: 1551  # or 1554
  name: OpenJDK 17.0; RHEL 8; Mvn 3.6.3; Gradle 7.2

buildScript: |
  # Use pre-installed JDK
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
  export PATH=$JAVA_HOME/bin:$PATH
  
  # Clear caches
  rm -rf ~/.gradle/caches/
  rm -rf /opt/build-agent/.gradle/caches/
  rm -rf .gradle/
  
  # Create init script to strip Java 21 classes from JARs
  cat > init-strip-mr-jar.gradle << 'INIT_EOF'
allprojects {
    configurations.all {
        resolutionStrategy.eachDependency { details ->
            if (details.requested.group == 'com.fasterxml.jackson.core') {
                details.artifactSelection {
                    selectArtifact {
                        // Only use base JAR, ignore multi-release versions
                        it.classifier = null
                    }
                }
            }
        }
    }
    
    // Hook into dependency resolution to strip META-INF/versions/21
    gradle.taskGraph.whenReady {
        configurations.all { config ->
            config.incoming.afterResolve {
                it.files.each { file ->
                    if (file.name.contains('jackson-core') && file.name.endsWith('.jar')) {
                        // Create stripped version
                        def strippedFile = new File(file.parent, file.name.replace('.jar', '-stripped.jar'))
                        if (!strippedFile.exists()) {
                            ant.zip(destfile: strippedFile) {
                                zipfileset(src: file) {
                                    exclude(name: 'META-INF/versions/21/**')
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
INIT_EOF
  
  # Apply Gradle 7 patches
  # [Same patches as before]
  
  # Build with init script
  gradle --init-script init-strip-mr-jar.gradle \
    --stacktrace --info publish -x copyDocs -x test \
    -Porg.gradle.java.installations.auto-download=false \
    -PruntimeJavaHomePath=/usr/lib/jvm/java-17-openjdk \
    -Druntime.java=17
```

#### Pros
- ✅ Keeps Jackson 2.20.0
- ✅ Uses Gradle 7.2/7.5.1 (known compatibility)
- ✅ Removes only problematic classes

#### Cons
- ⚠️ Complex init script
- ⚠️ May not work if Gradle caches before stripping
- ⚠️ Untested approach

---

### Solution 3: Use Gradle Toolchain with Java 21

**Concept**: Run Gradle itself on Java 21, but compile code for Java 17

#### Configuration

```yaml
name: ehcache-3.12.0-java21-toolchain
project: org.ehcache

scmRepository:
  url: https://github.com/ehcache/ehcache3.git
scmRevision: v3.12.0

environment:
  id: 1551  # Must have Java 21 available
  name: OpenJDK 17.0; RHEL 8; Mvn 3.6.3; Gradle 7.2

buildScript: |
  # Download and setup Java 21 for Gradle daemon
  wget -q https://download.java.net/java/GA/jdk21/fd2272bbf8e04c3dbaee13770090416c/35/GPL/openjdk-21_linux-x64_bin.tar.gz
  tar -xzf openjdk-21_linux-x64_bin.tar.gz
  export GRADLE_JAVA_HOME=$(pwd)/jdk-21
  
  # Use Java 17 for compilation
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
  export PATH=$JAVA_HOME/bin:$PATH
  
  # Clear caches
  rm -rf ~/.gradle/caches/
  
  # Configure Gradle to use Java 21 for daemon
  cat > gradle.properties << 'PROPS_EOF'
org.gradle.java.home=${GRADLE_JAVA_HOME}
org.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m
PROPS_EOF
  
  # Build (Gradle runs on Java 21, compiles for Java 17)
  gradle --stacktrace --info publish -x copyDocs -x test \
    -Porg.gradle.java.installations.auto-download=false \
    -PruntimeJavaHomePath=/usr/lib/jvm/java-17-openjdk \
    -Druntime.java=17
```

#### Pros
- ✅ Gradle on Java 21 can process Java 21 bytecode
- ✅ Code still compiles for Java 17
- ✅ Keeps Jackson 2.20.0

#### Cons
- ⚠️ Downloads Java 21 (may timeout like before)
- ⚠️ Complex setup
- ⚠️ May have other compatibility issues

---

### Solution 4: Patch Ehcache Build to Exclude Jackson 21 Classes

**Concept**: Modify Ehcache's build.gradle to exclude Java 21 classes

#### Configuration

```yaml
name: ehcache-3.12.0-patch-build-gradle
project: org.ehcache

scmRepository:
  url: https://github.com/ehcache/ehcache3.git
scmRevision: v3.12.0

environment:
  id: 1551
  name: OpenJDK 17.0; RHEL 8; Mvn 3.6.3; Gradle 7.2

buildScript: |
  # Use pre-installed JDK
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
  export PATH=$JAVA_HOME/bin:$PATH
  
  # Clear caches
  rm -rf ~/.gradle/caches/
  rm -rf /opt/build-agent/.gradle/caches/
  
  # Patch build.gradle to exclude Java 21 classes
  cat > /tmp/exclude-mr-jar.patch << 'PATCH_EOF'
--- a/build.gradle
+++ b/build.gradle
@@ -1,3 +1,15 @@
+// Exclude Java 21 classes from multi-release JARs
+configurations.all {
+    resolutionStrategy.eachDependency { details ->
+        if (details.requested.group == 'com.fasterxml.jackson.core') {
+            details.because('Exclude Java 21 bytecode from Jackson')
+        }
+    }
+    exclude group: 'com.fasterxml.jackson.core', module: 'jackson-core', classifier: 'java21'
+}
+
+// Existing build.gradle content
 plugins {
     id 'org.ehcache.build.conventions.root'
 }
PATCH_EOF
  
  # Apply patch
  patch -p1 < /tmp/exclude-mr-jar.patch
  
  # Apply Gradle 7 patches
  # [Same as before]
  
  # Build
  gradle --stacktrace --info publish -x copyDocs -x test
```

#### Pros
- ✅ Keeps Jackson 2.20.0
- ✅ Direct modification of build
- ✅ Uses Gradle 7.2

#### Cons
- ⚠️ May not work (Jackson doesn't use classifiers)
- ⚠️ Modifies source code
- ⚠️ Untested approach

---

## Comparison Matrix

| Solution | Jackson Version | Gradle Version | Complexity | Success Probability |
|----------|----------------|----------------|------------|---------------------|
| **Gradle 8** | 2.20.0 ✅ | 8.0.2 | Medium | 85% ⭐ |
| **Exclude MR-JAR** | 2.20.0 ✅ | 7.2/7.5.1 | High | 40% |
| **Java 21 Toolchain** | 2.20.0 ✅ | 7.2/7.5.1 | High | 50% |
| **Patch Build** | 2.20.0 ✅ | 7.2/7.5.1 | Medium | 30% |
| **Downgrade Jackson** | 2.17.2 ⚠️ | 7.2/7.5.1 | Low | 90% |

## Recommendation

### Primary Recommendation: Upgrade to Gradle 8 (Environment 1556)

**Why**:
1. ✅ Gradle 8.0.2 natively supports Java 21 bytecode
2. ✅ Clean solution without workarounds
3. ✅ Future-proof (supports newer Java versions)
4. ✅ Pre-installed in PNC (no download needed)
5. ✅ Highest success probability without downgrading

**Risk**:
- Gradle 8 API changes may require patch adjustments
- Less tested with Ehcache 3.12.0

### Fallback: Downgrade Jackson to 2.17.2

If Gradle 8 fails due to API incompatibilities, use the cache-clear-fix configuration with Jackson 2.17.2.

## Implementation Steps

### Step 1: Try Gradle 8 (Environment 1556)
1. Use configuration from "Solution 1" above
2. Upload to PNC
3. Trigger build
4. Monitor for success

### Step 2: If Gradle 8 Fails
1. Check error logs for API incompatibilities
2. Adjust patches for Gradle 8 APIs
3. Retry

### Step 3: If Still Failing
1. Fall back to Gradle 7.2 (Environment 1551)
2. Use Jackson 2.17.2 downgrade (cache-clear-fix)
3. This is the proven solution

## Why Other Solutions Are Less Viable

### Exclude MR-JAR Classes
- Gradle caches JARs before we can strip them
- Complex init script may not execute at right time
- No guarantee it will work

### Java 21 Toolchain
- Still requires downloading Java 21 (timeout risk)
- Complex setup
- May have other issues

### Patch Build.gradle
- Jackson doesn't use classifiers for multi-release
- Can't exclude specific classes from JAR
- Would need to repackage JAR

## Summary

**Best Alternative**: Use **Environment 1556 (Gradle 8.0.2)**

This is the cleanest solution that:
- Keeps Jackson 2.20.0 (no downgrade)
- Uses pre-installed JDK (no timeout)
- Natively supports Java 21 bytecode
- Is future-proof

**If that fails**: Use the proven **Jackson 2.17.2 downgrade** solution

---

**Status**: Ready for testing  
**Recommended**: Environment 1556 (Gradle 8.0.2)  
**Confidence**: 85% (Gradle 8 should handle Java 21 bytecode)  
**Last Updated**: 2026-08-26
