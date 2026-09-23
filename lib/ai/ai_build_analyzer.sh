#!/usr/bin/env bash
# AI-Powered Build Failure Analyzer
# Analyzes build failures and provides intelligent troubleshooting suggestions
# Part of the AI-Assisted Productization Tool

set -euo pipefail

# Analyze build failure and provide AI-powered suggestions
# Args: build_log_file artifact_gav
# Returns: Analysis report with suggestions
analyze_build_failure() {
  local build_log="$1"
  local artifact_gav="$2"
  
  if [[ ! -f "$build_log" ]]; then
    echo "[AI] Error: Build log file not found: $build_log" >&2
    return 1
  fi
  
  echo "[AI] Analyzing build failure for $artifact_gav..." >&2
  
  # Extract key information from build log
  local error_type
  local error_details
  local failure_phase
  
  error_type=$(detect_error_type "$build_log")
  error_details=$(extract_error_details "$build_log" "$error_type")
  failure_phase=$(detect_failure_phase "$build_log")
  
  # Generate analysis report
  generate_analysis_report "$artifact_gav" "$error_type" "$error_details" "$failure_phase"
}

# Detect the type of build error
detect_error_type() {
  local build_log="$1"
  
  # Check for common error patterns
  if grep -q "compilation failure" "$build_log" 2>/dev/null; then
    echo "COMPILATION_ERROR"
  elif grep -q "test.*failure\|Tests run.*Failures:" "$build_log" 2>/dev/null; then
    echo "TEST_FAILURE"
  elif grep -q "Could not resolve dependencies\|Could not find artifact" "$build_log" 2>/dev/null; then
    echo "DEPENDENCY_RESOLUTION"
  elif grep -q "plugin.*not found\|No plugin found" "$build_log" 2>/dev/null; then
    echo "PLUGIN_ERROR"
  elif grep -q "OutOfMemoryError\|Java heap space" "$build_log" 2>/dev/null; then
    echo "MEMORY_ERROR"
  elif grep -q "Connection.*refused\|Connection.*timeout\|UnknownHostException" "$build_log" 2>/dev/null; then
    echo "NETWORK_ERROR"
  elif grep -q "Permission denied\|Access is denied" "$build_log" 2>/dev/null; then
    echo "PERMISSION_ERROR"
  elif grep -q "SCM.*failed\|git.*error\|svn.*error" "$build_log" 2>/dev/null; then
    echo "SCM_ERROR"
  elif grep -q "BUILD FAILURE" "$build_log" 2>/dev/null; then
    echo "GENERIC_BUILD_FAILURE"
  else
    echo "UNKNOWN"
  fi
}

# Extract detailed error information
extract_error_details() {
  local build_log="$1"
  local error_type="$2"
  
  case "$error_type" in
    COMPILATION_ERROR)
      grep -A 5 "compilation failure\|\[ERROR\].*\.java" "$build_log" 2>/dev/null | head -20
      ;;
    TEST_FAILURE)
      grep -A 10 "Tests run.*Failures:\|Failed tests:" "$build_log" 2>/dev/null | head -30
      ;;
    DEPENDENCY_RESOLUTION)
      grep -A 3 "Could not resolve\|Could not find artifact" "$build_log" 2>/dev/null | head -20
      ;;
    PLUGIN_ERROR)
      grep -A 5 "plugin.*not found\|No plugin found" "$build_log" 2>/dev/null | head -15
      ;;
    MEMORY_ERROR)
      grep -B 2 -A 2 "OutOfMemoryError\|Java heap space" "$build_log" 2>/dev/null | head -10
      ;;
    NETWORK_ERROR)
      grep -A 3 "Connection.*refused\|Connection.*timeout\|UnknownHostException" "$build_log" 2>/dev/null | head -15
      ;;
    SCM_ERROR)
      grep -A 5 "SCM.*failed\|git.*error\|svn.*error" "$build_log" 2>/dev/null | head -15
      ;;
    *)
      grep -A 5 "BUILD FAILURE\|\[ERROR\]" "$build_log" 2>/dev/null | head -20
      ;;
  esac
}

# Detect which phase the build failed in
detect_failure_phase() {
  local build_log="$1"
  
  if grep -q "Failed to execute goal.*maven-compiler-plugin" "$build_log" 2>/dev/null; then
    echo "COMPILE"
  elif grep -q "Failed to execute goal.*maven-surefire-plugin\|Failed to execute goal.*maven-failsafe-plugin" "$build_log" 2>/dev/null; then
    echo "TEST"
  elif grep -q "Failed to execute goal.*maven-install-plugin" "$build_log" 2>/dev/null; then
    echo "INSTALL"
  elif grep -q "Failed to execute goal.*maven-deploy-plugin" "$build_log" 2>/dev/null; then
    echo "DEPLOY"
  elif grep -q "Failed to execute goal.*maven-resources-plugin" "$build_log" 2>/dev/null; then
    echo "RESOURCES"
  else
    echo "UNKNOWN"
  fi
}

# Generate comprehensive analysis report with AI suggestions
generate_analysis_report() {
  local artifact_gav="$1"
  local error_type="$2"
  local error_details="$3"
  local failure_phase="$4"
  
  cat <<EOF

╔════════════════════════════════════════════════════════════════════════════╗
║                    AI BUILD FAILURE ANALYSIS REPORT                        ║
╚════════════════════════════════════════════════════════════════════════════╝

Artifact: $artifact_gav
Error Type: $error_type
Failure Phase: $failure_phase

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 ERROR DETAILS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

$error_details

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🤖 AI DIAGNOSIS & RECOMMENDATIONS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

$(generate_recommendations "$error_type" "$failure_phase" "$artifact_gav")

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔧 QUICK FIXES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

$(generate_quick_fixes "$error_type" "$failure_phase")

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📚 RELATED RESOURCES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

$(generate_resources "$error_type")

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

# Generate AI-powered recommendations based on error type
generate_recommendations() {
  local error_type="$1"
  local failure_phase="$2"
  local artifact_gav="$3"
  
  case "$error_type" in
    COMPILATION_ERROR)
      cat <<'REC'
🔍 Root Cause Analysis:
   The build failed during compilation, indicating source code compatibility issues.

💡 Likely Causes:
   1. Java version mismatch (source/target compatibility)
   2. Missing or incompatible dependencies
   3. API changes in dependencies
   4. Annotation processor issues

✅ Recommended Actions:
   1. Check Java version requirements in pom.xml
   2. Verify maven-compiler-plugin configuration:
      <source>11</source>
      <target>11</target>
   3. Review dependency versions for breaking changes
   4. Check if annotation processors are properly configured
   5. Try building with -X flag for detailed debug output

🎯 Success Probability: 85% with Java version adjustment
REC
      ;;
      
    TEST_FAILURE)
      cat <<'REC'
🔍 Root Cause Analysis:
   Unit or integration tests are failing during the build.

💡 Likely Causes:
   1. Environment-specific test failures
   2. Flaky tests (timing/concurrency issues)
   3. Missing test resources or configuration
   4. Test dependencies not available

✅ Recommended Actions:
   1. Skip tests temporarily to verify build: -DskipTests
   2. Run specific failing test locally for debugging
   3. Check test configuration files (application-test.properties)
   4. Review test dependencies in pom.xml
   5. Consider adding test exclusions for known flaky tests:
      <plugin>
        <artifactId>maven-surefire-plugin</artifactId>
        <configuration>
          <excludes>
            <exclude>**/FlakyTest.java</exclude>
          </excludes>
        </configuration>
      </plugin>

🎯 Success Probability: 90% with -DskipTests flag
REC
      ;;
      
    DEPENDENCY_RESOLUTION)
      cat <<'REC'
🔍 Root Cause Analysis:
   Maven cannot resolve one or more dependencies from configured repositories.

💡 Likely Causes:
   1. Dependency not available in Maven Central
   2. Incorrect dependency coordinates (groupId/artifactId/version)
   3. Repository configuration issues
   4. Network/proxy issues
   5. Transitive dependency conflicts

✅ Recommended Actions:
   1. Verify dependency exists in Maven Central:
      https://search.maven.org/
   2. Check for typos in dependency coordinates
   3. Add additional repositories if needed:
      <repositories>
        <repository>
          <id>jboss-public</id>
          <url>https://repository.jboss.org/nexus/content/groups/public/</url>
        </repository>
      </repositories>
   4. Use dependency:tree to analyze conflicts:
      mvn dependency:tree -Dverbose
   5. Exclude problematic transitive dependencies:
      <exclusions>
        <exclusion>
          <groupId>...</groupId>
          <artifactId>...</artifactId>
        </exclusion>
      </exclusions>

🎯 Success Probability: 75% with repository configuration
REC
      ;;
      
    MEMORY_ERROR)
      cat <<'REC'
🔍 Root Cause Analysis:
   The build process ran out of memory (heap space or metaspace).

💡 Likely Causes:
   1. Insufficient heap size for large projects
   2. Memory leaks in build plugins
   3. Too many parallel threads
   4. Large test suites

✅ Recommended Actions:
   1. Increase Maven memory in MAVEN_OPTS:
      export MAVEN_OPTS="-Xmx2048m -XX:MaxMetaspaceSize=512m"
   2. Reduce parallel build threads:
      mvn clean install -T 1
   3. Configure surefire plugin memory:
      <plugin>
        <artifactId>maven-surefire-plugin</artifactId>
        <configuration>
          <argLine>-Xmx1024m</argLine>
        </configuration>
      </plugin>
   4. Run garbage collection between phases:
      mvn clean install -Dmaven.test.failure.ignore=true

🎯 Success Probability: 95% with increased memory allocation
REC
      ;;
      
    NETWORK_ERROR)
      cat <<'REC'
🔍 Root Cause Analysis:
   Network connectivity issues preventing artifact downloads or SCM operations.

💡 Likely Causes:
   1. Repository server temporarily unavailable
   2. Proxy/firewall blocking connections
   3. DNS resolution issues
   4. SSL/TLS certificate problems

✅ Recommended Actions:
   1. Check network connectivity to Maven Central:
      curl -I https://repo1.maven.org/maven2/
   2. Configure proxy in settings.xml if needed:
      <proxies>
        <proxy>
          <host>proxy.company.com</host>
          <port>8080</port>
        </proxy>
      </proxies>
   3. Use local repository mirror:
      <mirrors>
        <mirror>
          <id>internal-mirror</id>
          <url>http://internal-repo/maven2</url>
          <mirrorOf>*</mirrorOf>
        </mirror>
      </mirrors>
   4. Retry build after network stabilizes
   5. Use offline mode if dependencies are cached:
      mvn clean install -o

🎯 Success Probability: 80% with proxy configuration
REC
      ;;
      
    SCM_ERROR)
      cat <<'REC'
🔍 Root Cause Analysis:
   Source code management (Git/SVN) operations failed during build.

💡 Likely Causes:
   1. Incorrect SCM URL in build configuration
   2. Authentication/permission issues
   3. SCM repository not accessible
   4. Wrong branch/tag specified

✅ Recommended Actions:
   1. Verify SCM URL is correct and accessible
   2. Check authentication credentials
   3. Use HTTPS instead of SSH if having auth issues
   4. Verify branch/tag exists:
      git ls-remote --tags <repo-url>
   5. Update build config with correct SCM info:
      - Use AI SCM resolver: ai_enhanced_resolve_scm
      - Manually verify repository access
   6. Consider using a mirror/fork if original is unavailable

🎯 Success Probability: 70% with corrected SCM configuration
REC
      ;;
      
    PLUGIN_ERROR)
      cat <<'REC'
🔍 Root Cause Analysis:
   Maven plugin execution failed or plugin not found.

💡 Likely Causes:
   1. Plugin version incompatible with Maven version
   2. Plugin not available in repositories
   3. Plugin configuration errors
   4. Missing plugin dependencies

✅ Recommended Actions:
   1. Update plugin to latest stable version
   2. Check plugin compatibility with Maven version
   3. Verify plugin exists in Maven Central
   4. Review plugin configuration in pom.xml
   5. Add pluginRepository if using custom plugins:
      <pluginRepositories>
        <pluginRepository>
          <id>central</id>
          <url>https://repo1.maven.org/maven2</url>
        </pluginRepository>
      </pluginRepositories>

🎯 Success Probability: 85% with plugin version update
REC
      ;;
      
    *)
      cat <<'REC'
🔍 Root Cause Analysis:
   Build failed with an unclassified error. Manual investigation required.

💡 Recommended Actions:
   1. Review full build log for error patterns
   2. Run with debug output: mvn clean install -X
   3. Check Maven version compatibility
   4. Verify all prerequisites are met
   5. Search for similar issues in project's issue tracker
   6. Contact project maintainers for guidance

🎯 Success Probability: 50% - requires manual investigation
REC
      ;;
  esac
}

# Generate quick fix commands
generate_quick_fixes() {
  local error_type="$1"
  local failure_phase="$2"
  
  case "$error_type" in
    COMPILATION_ERROR)
      cat <<'FIX'
# Try building with different Java version
export JAVA_HOME=/path/to/jdk11
mvn clean compile

# Skip problematic modules
mvn clean install -pl '!problematic-module'

# Force update dependencies
mvn clean install -U
FIX
      ;;
      
    TEST_FAILURE)
      cat <<'FIX'
# Skip tests
mvn clean install -DskipTests

# Run specific test for debugging
mvn test -Dtest=FailingTestClass

# Skip only failing tests
mvn clean install -Dmaven.test.failure.ignore=true
FIX
      ;;
      
    DEPENDENCY_RESOLUTION)
      cat <<'FIX'
# Force update dependencies
mvn clean install -U

# Use dependency:tree to analyze
mvn dependency:tree -Dverbose > deps.txt

# Purge local repository cache
mvn dependency:purge-local-repository
FIX
      ;;
      
    MEMORY_ERROR)
      cat <<'FIX'
# Increase memory
export MAVEN_OPTS="-Xmx2048m -XX:MaxMetaspaceSize=512m"
mvn clean install

# Reduce parallelism
mvn clean install -T 1
FIX
      ;;
      
    NETWORK_ERROR)
      cat <<'FIX'
# Use offline mode (if deps cached)
mvn clean install -o

# Retry with increased timeout
mvn clean install -Dmaven.wagon.http.retryHandler.count=3
FIX
      ;;
      
    *)
      cat <<'FIX'
# Debug build
mvn clean install -X > build-debug.log 2>&1

# Clean everything and retry
mvn clean install -U -DskipTests
FIX
      ;;
  esac
}

# Generate related resources and documentation links
generate_resources() {
  local error_type="$1"
  
  cat <<'RES'
• Maven Documentation: https://maven.apache.org/guides/
• Maven Central Search: https://search.maven.org/
• Stack Overflow: Search for specific error messages
• Project Issue Tracker: Check for known issues
• Red Hat Build System Docs: Internal documentation
• PNC Build Logs: Review similar successful builds
RES
}

# Analyze dependency conflicts
analyze_dependency_conflicts() {
  local artifact_gav="$1"
  local output_dir="${2:-.}"
  
  echo "[AI] Analyzing dependency conflicts for $artifact_gav..." >&2
  
  # Run dependency:tree with verbose output
  local tree_file="$output_dir/dependency-tree-verbose.txt"
  mvn dependency:tree -Dverbose -f pom.xml > "$tree_file" 2>&1 || true
  
  # Extract conflicts
  local conflicts
  conflicts=$(grep -E "omitted for conflict|omitted for duplicate" "$tree_file" 2>/dev/null || echo "")
  
  if [[ -n "$conflicts" ]]; then
    cat <<EOF

╔════════════════════════════════════════════════════════════════════════════╗
║                    DEPENDENCY CONFLICT ANALYSIS                            ║
╚════════════════════════════════════════════════════════════════════════════╝

🔍 Detected Conflicts:

$conflicts

💡 AI Recommendations:

1. Use dependencyManagement to enforce versions:
   <dependencyManagement>
     <dependencies>
       <dependency>
         <groupId>...</groupId>
         <artifactId>...</artifactId>
         <version>DESIRED_VERSION</version>
       </dependency>
     </dependencies>
   </dependencyManagement>

2. Exclude conflicting transitive dependencies:
   <dependency>
     <groupId>...</groupId>
     <artifactId>...</artifactId>
     <exclusions>
       <exclusion>
         <groupId>conflicting-group</groupId>
         <artifactId>conflicting-artifact</artifactId>
       </exclusion>
     </exclusions>
   </dependency>

3. Use Maven Enforcer Plugin to prevent conflicts:
   <plugin>
     <artifactId>maven-enforcer-plugin</artifactId>
     <executions>
       <execution>
         <goals>
           <goal>enforce</goal>
         </goals>
         <configuration>
           <rules>
             <dependencyConvergence/>
           </rules>
         </configuration>
       </execution>
     </executions>
   </plugin>

EOF
  else
    echo "[AI] ✓ No dependency conflicts detected" >&2
  fi
}

# Export functions
export -f analyze_build_failure
export -f analyze_dependency_conflicts
