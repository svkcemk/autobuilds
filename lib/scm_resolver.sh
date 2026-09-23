#!/usr/bin/env bash
# SCM Resolution Library
# Shared library for resolving SCM URLs and revisions for Maven artifacts
# Part of the PNC Build Config Generator consolidation effort

set -euo pipefail

# Source cache manager if available
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/cache_manager.sh" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/cache_manager.sh"
  CACHE_ENABLED=true
else
  CACHE_ENABLED=false
fi

# Portable timeout function for macOS/Linux compatibility
run_with_timeout() {
  local timeout_seconds="$1"
  shift
  local command=("$@")
  
  # Run command in background
  "${command[@]}" &
  local pid=$!
  
  # Wait with timeout
  local elapsed=0
  while kill -0 $pid 2>/dev/null && [[ $elapsed -lt $timeout_seconds ]]; do
    sleep 0.5
    elapsed=$((elapsed + 1))
  done
  
  # Kill if still running
  if kill -0 $pid 2>/dev/null; then
    kill -9 $pid 2>/dev/null
    wait $pid 2>/dev/null || true
    return 124  # Timeout exit code
  fi
  
  # Get result
  wait $pid 2>/dev/null
  return $?
}

# Main entry point for SCM resolution
# Tries multiple sources in order: family rules, JVM build data, Camel data, Maven Central
# Args: group_id artifact_id version
# Returns: SCM_URL=... and SCM_REVISION=... and SCM_SOURCE=... on stdout, or exits with error
resolve_scm() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"
  
  # Check cache first if enabled
  if [[ "$CACHE_ENABLED" == "true" ]]; then
    local cached_result
    if cached_result=$(get_cached_scm_resolution "$group_id" "$artifact_id" "$version"); then
      echo "$cached_result"
      echo "SCM_SOURCE=Cache"
      return 0
    fi
  fi
  
  local scm_data=""
  
  # PRIORITY 1: Try PNC existing build configs FIRST (copy from existing builds)
  # This is the most reliable source - if it's already built in PNC, reuse that SCM info
  scm_data="$(fetch_scm_from_pnc "$group_id" "$artifact_id" "$version" 2>/dev/null || true)"
  if [[ -n "$scm_data" ]]; then
    echo "$scm_data"
    echo "SCM_SOURCE=PNC Build Config"
    return 0
  fi
  
  # PRIORITY 2: PNC SCM Repository Registry (searches SCM repos when build configs don't exist)
  scm_data="$(fetch_scm_from_pnc_scm_registry "$group_id" "$artifact_id" "$version" 2>/dev/null || true)"
  if [[ -n "$scm_data" ]]; then
    echo "$scm_data"
    echo "SCM_SOURCE=PNC SCM Registry"
    return 0
  fi
  
  # PRIORITY 3: Family Rules (fast, hardcoded patterns for common libraries)
  scm_data="$(fetch_scm_from_family_rules "$group_id" "$artifact_id" "$version" 2>/dev/null || true)"
  if [[ -n "$scm_data" ]]; then
    echo "$scm_data"
    echo "SCM_SOURCE=Family Rules"
    return 0
  fi
  
  # PRIORITY 4: JVM Build Data (cached from previous builds)
  scm_data="$(fetch_scm_from_jvm_build_data "$group_id" "$artifact_id" "$version" 2>/dev/null || true)"
  if [[ -n "$scm_data" ]]; then
    echo "$scm_data"
    echo "SCM_SOURCE=JVM Build Data"
    return 0
  fi
  
  # PRIORITY 5: Camel Spring Boot Data (Camel-specific)
  scm_data="$(fetch_scm_from_camel_spring_boot_data "$group_id" "$artifact_id" "$version" 2>/dev/null || true)"
  if [[ -n "$scm_data" ]]; then
    echo "$scm_data"
    echo "SCM_SOURCE=Camel Spring Boot Data"
    return 0
  fi
  
  # PRIORITY 6: Maven Central POM (slowest, downloads and parses POM)
  # Use timeout wrapper to prevent hanging
  scm_data="$(fetch_scm_from_maven_with_timeout "$group_id" "$artifact_id" "$version" 2>/dev/null || true)"
  if [[ -n "$scm_data" ]]; then
    # Cache successful resolution
    if [[ "$CACHE_ENABLED" == "true" ]]; then
      local scm_url scm_revision
      scm_url=$(echo "$scm_data" | grep "^SCM_URL=" | cut -d= -f2-)
      scm_revision=$(echo "$scm_data" | grep "^SCM_REVISION=" | cut -d= -f2-)
      if [[ -n "$scm_url" && -n "$scm_revision" ]]; then
        cache_scm_resolution "$group_id" "$artifact_id" "$version" "$scm_url" "$scm_revision"
      fi
    fi
    
    echo "$scm_data"
    echo "SCM_SOURCE=Maven Central POM"
    return 0
  fi
  
  return 1
}

# Wrapper for fetch_scm_from_maven with enforced timeout
fetch_scm_from_maven_with_timeout() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"
  # Each loop iteration sleeps 0.5s; max_ticks = timeout_seconds / 0.5
  local timeout_seconds=15
  local max_ticks=$(( timeout_seconds * 2 ))
  
  # Create temp file for result
  local temp_result=$(mktemp)
  
  # Run fetch in background with timeout
  (fetch_scm_from_maven "$group_id" "$artifact_id" "$version" > "$temp_result" 2>/dev/null) &
  local fetch_pid=$!
  
  # Wait with timeout: each tick = 0.5s, so max_ticks ticks = timeout_seconds wall-clock seconds
  local ticks=0
  while kill -0 $fetch_pid 2>/dev/null && [[ $ticks -lt $max_ticks ]]; do
    sleep 0.5
    ticks=$((ticks + 1))
  done
  
  # Kill if still running
  if kill -0 $fetch_pid 2>/dev/null; then
    kill -9 $fetch_pid 2>/dev/null
    wait $fetch_pid 2>/dev/null || true
    rm -f "$temp_result"
    return 1
  fi
  
  # Get result
  wait $fetch_pid 2>/dev/null
  local exit_code=$?
  
  if [[ $exit_code -eq 0 && -s "$temp_result" ]]; then
    cat "$temp_result"
    rm -f "$temp_result"
    return 0
  fi
  
  rm -f "$temp_result"
  return 1
}

# Fetch SCM from PNC existing build configs (5th tier fallback)
# Queries PNC via bacon CLI to find existing build configs with SCM info
fetch_scm_from_pnc() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"
  
  # Check if bacon CLI is available
  if ! command -v bacon &> /dev/null; then
    return 1
  fi
  
  # Skip PNC queries if they're known to hang (can be controlled via env var)
  if [[ "${SKIP_PNC_QUERIES:-false}" == "true" ]]; then
    return 1
  fi
  
  # Search for build config matching the artifact
  # PNC build config names follow pattern: groupId_artifactId_version (with dots replaced by underscores)
  local search_pattern="${group_id//./_}_${artifact_id}_${version}"
  local pnc_output
  local temp_output=$(mktemp)
  
  # Try exact match first with 10 second timeout using our portable function
  (bacon pnc build-config list --query="name==${search_pattern}" -o > "$temp_output" 2>/dev/null) &
  local pid=$!
  local elapsed=0
  while kill -0 $pid 2>/dev/null && [[ $elapsed -lt 20 ]]; do
    sleep 0.5
    elapsed=$((elapsed + 1))
  done
  
  if kill -0 $pid 2>/dev/null; then
    kill -9 $pid 2>/dev/null
    wait $pid 2>/dev/null || true
    rm -f "$temp_output"
    return 1
  fi
  
  wait $pid 2>/dev/null || true
  pnc_output=$(cat "$temp_output" 2>/dev/null || echo '[]')
  rm -f "$temp_output"
  
  # Check if we got results, if not try wildcard patterns
  local result_count
  result_count=$(echo "$pnc_output" | jq 'length' 2>/dev/null || echo "0")
  
  if [[ "$result_count" -eq 0 ]]; then
    # Skip additional PNC queries - they're too slow
    return 1
  fi
  
  # Parse JSON to extract SCM URL and revision from first matching config
  local scm_url scm_revision
  scm_url=$(echo "$pnc_output" | jq -r '.[0].scmRepository.internalUrl // .[0].scmRepository.externalUrl // empty' 2>/dev/null)
  scm_revision=$(echo "$pnc_output" | jq -r '.[0].scmRevision // empty' 2>/dev/null)
  
  if [[ -n "$scm_url" && -n "$scm_revision" ]]; then
    echo "SCM_URL=$scm_url"
    echo "SCM_REVISION=$scm_revision"
    return 0
  fi
  
  return 1
}

# Fetch SCM from PNC SCM repository registry (1.5th tier fallback)
# Searches PNC's SCM repository list when build configs don't exist
# Only provides URL, revision must be inferred from version
fetch_scm_from_pnc_scm_registry() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"
  
  # Check if bacon CLI is available
  if ! command -v bacon &> /dev/null; then
    return 1
  fi
  
  # Skip PNC queries - they're causing hangs
  return 1
}

# Fetch SCM from hardcoded family rules (200+ patterns)
# This is the fastest method and covers most common libraries
fetch_scm_from_family_rules() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"

  case "$group_id:$artifact_id" in
    # Jackson family
    com.fasterxml.jackson.core:jackson-annotations|com.fasterxml.jackson.core:jackson-core|com.fasterxml.jackson.core:jackson-databind)
      echo "SCM_URL=https://github.com/FasterXML/${artifact_id}.git"
      echo "SCM_REVISION=jackson-${artifact_id}-${version}"
      return 0
      ;;
    com.fasterxml.jackson.datatype:jackson-datatype-jdk8|com.fasterxml.jackson.datatype:jackson-datatype-jsr310)
      echo "SCM_URL=https://github.com/FasterXML/jackson-modules-java8.git"
      echo "SCM_REVISION=jackson-modules-java8-${version}"
      return 0
      ;;
    com.fasterxml.jackson.module:jackson-module-parameter-names)
      echo "SCM_URL=https://github.com/FasterXML/jackson-modules-java8.git"
      echo "SCM_REVISION=jackson-modules-java8-${version}"
      return 0
      ;;
    
    # Apache Camel family
    org.apache.camel:*)
      echo "SCM_URL=https://github.com/apache/camel.git"
      echo "SCM_REVISION=camel-${version}"
      return 0
      ;;
    
    # Apache Commons family
    org.apache.commons:commons-compress|org.apache.commons:commons-text|org.apache.commons:commons-math3)
      local artifact_name="${artifact_id#commons-}"
      echo "SCM_URL=https://github.com/apache/commons-${artifact_name}.git"
      echo "SCM_REVISION=rel/commons-${artifact_name}-${version}"
      return 0
      ;;
    commons-io:commons-io)
      echo "SCM_URL=https://github.com/apache/commons-io.git"
      echo "SCM_REVISION=rel/commons-io-${version}"
      return 0
      ;;
    
    # Netty family
    io.netty:*)
      echo "SCM_URL=https://github.com/netty/netty.git"
      echo "SCM_REVISION=netty-${version}"
      return 0
      ;;

    # Reactive Streams
    org.reactivestreams:reactive-streams)
      echo "SCM_URL=https://github.com/reactive-streams/reactive-streams-jvm.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # JSpecify
    org.jspecify:jspecify)
      echo "SCM_URL=https://github.com/jspecify/jspecify.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # Apache HttpComponents Core 5
    org.apache.httpcomponents.core5:*)
      echo "SCM_URL=https://github.com/apache/httpcomponents-core.git"
      echo "SCM_REVISION=rel/v${version}"
      return 0
      ;;

    # Google Error Prone
    com.google.errorprone:error_prone_annotations)
      echo "SCM_URL=https://github.com/google/error-prone.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # Apache Cassandra Java driver
    org.apache.cassandra:java-driver-core|org.apache.cassandra:java-driver-guava-shaded|org.apache.cassandra:java-driver-query-builder|org.apache.cassandra:java-driver-mapper-processor|org.apache.cassandra:java-driver-mapper-runtime)
      echo "SCM_URL=https://github.com/apache/cassandra-java-driver.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Apache Curator
    org.apache.curator:*)
      echo "SCM_URL=https://github.com/apache/curator.git"
      echo "SCM_REVISION=apache-curator-${version}"
      return 0
      ;;

    # Apache Daffodil (Scala suffix _2.12 / _2.13 stripped for version tag)
    org.apache.daffodil:*)
      local base_version="${version%%_*}"
      echo "SCM_URL=https://github.com/apache/daffodil.git"
      echo "SCM_REVISION=v${base_version}"
      return 0
      ;;

    # Apache Directory API
    org.apache.directory.api:*)
      echo "SCM_URL=https://github.com/apache/directory-ldap-api.git"
      echo "SCM_REVISION=${artifact_id}-${version}"
      return 0
      ;;

    # Apache Directory Server (ApacheDS)
    org.apache.directory.server:*)
      echo "SCM_URL=https://github.com/apache/directory-server.git"
      echo "SCM_REVISION=${artifact_id}-${version}"
      return 0
      ;;

    # Apache Drill
    org.apache.drill|org.apache.drill.exec:*)
      echo "SCM_URL=https://github.com/apache/drill.git"
      echo "SCM_REVISION=drill-${version}"
      return 0
      ;;

    # Apache Flink (shaded artifacts have composite versions like 9.5-17.0)
    org.apache.flink:flink-shaded-*)
      echo "SCM_URL=https://github.com/apache/flink-shaded.git"
      echo "SCM_REVISION=release-${version}"
      return 0
      ;;
    org.apache.flink:*)
      echo "SCM_URL=https://github.com/apache/flink.git"
      echo "SCM_REVISION=release-${version}"
      return 0
      ;;

    # Apache Fury (incubating)
    org.apache.fury:*)
      echo "SCM_URL=https://github.com/apache/fury.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # Apache Commons Collections 4
    org.apache.commons:commons-collections4)
      echo "SCM_URL=https://github.com/apache/commons-collections.git"
      echo "SCM_REVISION=rel/commons-collections-${version}"
      return 0
      ;;

    # Apache Commons CSV
    org.apache.commons:commons-csv)
      echo "SCM_URL=https://github.com/apache/commons-csv.git"
      echo "SCM_REVISION=rel/commons-csv-${version}"
      return 0
      ;;

    # Apache Commons Exec
    org.apache.commons:commons-exec)
      echo "SCM_URL=https://github.com/apache/commons-exec.git"
      echo "SCM_REVISION=rel/commons-exec-${version}"
      return 0
      ;;

    # Apache Commons FileUpload 2
    org.apache.commons:commons-fileupload2-core|org.apache.commons:commons-fileupload2-jakarta|org.apache.commons:commons-fileupload2-portlet|org.apache.commons:commons-fileupload2-javax)
      echo "SCM_URL=https://github.com/apache/commons-fileupload.git"
      echo "SCM_REVISION=rel/commons-fileupload2-${version}"
      return 0
      ;;

    # Other common libraries
    at.yawi.lz4:lz4-java|at.yawk.lz4:lz4-java)
      echo "SCM_URL=https://github.com/yawkat/lz4-java.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # SLF4J family
    org.slf4j:*)
      echo "SCM_URL=https://github.com/qos-ch/slf4j.git"
      echo "SCM_REVISION=v_${version}"
      return 0
      ;;

    # Log4j 2 family
    org.apache.logging.log4j:*)
      echo "SCM_URL=https://github.com/apache/logging-log4j2.git"
      echo "SCM_REVISION=log4j-${version}"
      return 0
      ;;

    # Apache Commons Lang
    org.apache.commons:commons-lang3)
      echo "SCM_URL=https://github.com/apache/commons-lang.git"
      echo "SCM_REVISION=rel/commons-lang-${version}"
      return 0
      ;;

    # Google Guava
    com.google.guava:guava|com.google.guava:guava-parent|com.google.guava:failureaccess)
      echo "SCM_URL=https://github.com/google/guava.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # JUnit 5 family
    org.junit.jupiter:*|org.junit.platform:*|org.junit.vintage:*)
      echo "SCM_URL=https://github.com/junit-team/junit5.git"
      # JUnit 5 tags: r5.x.y
      echo "SCM_REVISION=r${version}"
      return 0
      ;;

    # JUnit 4
    junit:junit)
      echo "SCM_URL=https://github.com/junit-team/junit4.git"
      echo "SCM_REVISION=r${version}"
      return 0
      ;;

    # Mockito
    org.mockito:*)
      echo "SCM_URL=https://github.com/mockito/mockito.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # AssertJ
    org.assertj:assertj-core)
      echo "SCM_URL=https://github.com/assertj/assertj.git"
      echo "SCM_REVISION=assertj-core-${version}"
      return 0
      ;;

    # Byte Buddy
    net.bytebuddy:byte-buddy|net.bytebuddy:byte-buddy-agent)
      echo "SCM_URL=https://github.com/raphw/byte-buddy.git"
      echo "SCM_REVISION=byte-buddy-${version}"
      return 0
      ;;

    # Bouncycastle
    org.bouncycastle:*)
      echo "SCM_URL=https://github.com/bcgit/bc-java.git"
      echo "SCM_REVISION=r${version//./_}"
      return 0
      ;;

    # OkHttp / Okio
    com.squareup.okhttp3:*)
      echo "SCM_URL=https://github.com/square/okhttp.git"
      echo "SCM_REVISION=parent-${version}"
      return 0
      ;;

    # Vert.x family
    io.vertx:*)
      echo "SCM_URL=https://github.com/eclipse-vertx/vert.x.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Micrometer
    io.micrometer:*)
      echo "SCM_URL=https://github.com/micrometer-metrics/micrometer.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # AWS SDK v2
    software.amazon.awssdk:*)
      echo "SCM_URL=https://github.com/aws/aws-sdk-java-v2.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Apache CXF
    org.apache.cxf:*)
      echo "SCM_URL=https://github.com/apache/cxf.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Apache CXF XJC plugins
    org.apache.cxf.xjcplugins:*|org.apache.cxf.xjc-utils:*)
      echo "SCM_URL=https://github.com/apache/cxf-xjc-utils.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Apache CXF STS
    org.apache.cxf.services.sts:*)
      echo "SCM_URL=https://github.com/apache/cxf.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Quarkiverse CXF
    io.quarkiverse.cxf:*)
      echo "SCM_URL=https://github.com/quarkiverse/quarkus-cxf.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Debezium
    io.debezium:*)
      echo "SCM_URL=https://github.com/debezium/debezium.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # Azure SDK for Java
    com.azure:*)
      echo "SCM_URL=https://github.com/Azure/azure-sdk-for-java.git"
      echo "SCM_REVISION=${artifact_id}_${version}"
      return 0
      ;;

    # OpenSAML / Shibboleth
    org.opensaml:*)
      echo "SCM_URL=https://git.shibboleth.net/git/java-opensaml.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # net.shibboleth
    net.shibboleth:*)
      echo "SCM_URL=https://git.shibboleth.net/git/java-parent-project.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # HAPI FHIR
    ca.uhn.hapi.fhir:*)
      echo "SCM_URL=https://github.com/hapifhir/hapi-fhir.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # HAPI HL7v2
    ca.uhn.hapi:*)
      echo "SCM_URL=https://github.com/hapifhir/hapi-hl7v2.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # LangChain4j
    dev.langchain4j:*)
      echo "SCM_URL=https://github.com/langchain4j/langchain4j.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Eclipse Jetty (12+)
    org.eclipse.jetty:*|org.eclipse.jetty.websocket:*|org.eclipse.jetty.compression:*)
      echo "SCM_URL=https://github.com/jetty/jetty.project.git"
      echo "SCM_REVISION=jetty-${version}"
      return 0
      ;;

    # Spring Framework
    org.springframework:spring-*)
      echo "SCM_URL=https://github.com/spring-projects/spring-framework.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # Spring Data
    org.springframework.data:*)
      echo "SCM_URL=https://github.com/spring-projects/spring-data-commons.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Apache Kafka
    org.apache.kafka:*)
      echo "SCM_URL=https://github.com/apache/kafka.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Apache Groovy
    org.apache.groovy:*)
      echo "SCM_URL=https://github.com/apache/groovy.git"
      echo "SCM_REVISION=GROOVY_${version//./_}"
      return 0
      ;;

    # Apache ZooKeeper
    org.apache.zookeeper:*)
      echo "SCM_URL=https://github.com/apache/zookeeper.git"
      echo "SCM_REVISION=release-${version}"
      return 0
      ;;

    # Apache WSS4J
    org.apache.wss4j:*)
      echo "SCM_URL=https://github.com/apache/ws-wss4j.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Apache RocketMQ
    org.apache.rocketmq:*)
      echo "SCM_URL=https://github.com/apache/rocketmq.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Apache Qpid
    org.apache.qpid:*)
      echo "SCM_URL=https://github.com/apache/qpid-broker-j.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Apache PDFBox
    org.apache.pdfbox:*)
      echo "SCM_URL=https://github.com/apache/pdfbox.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Apache Shiro
    org.apache.shiro:*)
      echo "SCM_URL=https://github.com/apache/shiro.git"
      echo "SCM_REVISION=shiro-root-${version}"
      return 0
      ;;

    # Apache Velocity
    org.apache.velocity:*)
      echo "SCM_URL=https://github.com/apache/velocity-engine.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Apache Santuario XML Security
    org.apache.santuario:*)
      echo "SCM_URL=https://github.com/apache/santuario-xml-security-java.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Apache Jackrabbit Oak
    org.apache.jackrabbit:*)
      echo "SCM_URL=https://github.com/apache/jackrabbit-oak.git"
      echo "SCM_REVISION=${artifact_id}-${version}"
      return 0
      ;;

    # Apache Neethi
    org.apache.neethi:*)
      echo "SCM_URL=https://github.com/apache/neethi.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Apache ws-xmlschema
    org.apache.ws.xmlschema:*)
      echo "SCM_URL=https://github.com/apache/ws-xmlschema.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Apache Yetus
    org.apache.yetus:*)
      echo "SCM_URL=https://github.com/apache/yetus.git"
      echo "SCM_REVISION=rel/yetus-${version}"
      return 0
      ;;

    # GlassFish JAXB RI
    org.glassfish.jaxb:*)
      echo "SCM_URL=https://github.com/eclipse-ee4j/jaxb-ri.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # JVNET JAXB / jvnet staxex / mimepull
    org.jvnet.jaxb:*|org.jvnet.staxex:*|org.jvnet.mimepull:*)
      echo "SCM_URL=https://github.com/javaee/jaxb-v2.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Dropwizard Metrics
    io.dropwizard.metrics:*)
      echo "SCM_URL=https://github.com/dropwizard/metrics.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # Hazelcast
    com.hazelcast:*)
      echo "SCM_URL=https://github.com/hazelcast/hazelcast.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # Okio (Square)
    com.squareup.okio:*)
      echo "SCM_URL=https://github.com/square/okio.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Retrofit2 (Square)
    com.squareup.retrofit2:*)
      echo "SCM_URL=https://github.com/square/retrofit.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Eclipse JGit
    org.eclipse.jgit:*)
      echo "SCM_URL=https://git.eclipse.org/r/jgit/jgit.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # Swagger Core v3 / Swagger Parser / Swagger Codegen
    io.swagger.core.v3:*|io.swagger.parser.v3:*|io.swagger.codegen.v3:*)
      echo "SCM_URL=https://github.com/swagger-api/swagger-core.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # Reactor Core / Reactor Netty
    io.projectreactor:*|io.projectreactor.netty:*)
      echo "SCM_URL=https://github.com/reactor/reactor-core.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # OpenTelemetry Java
    io.opentelemetry:*)
      echo "SCM_URL=https://github.com/open-telemetry/opentelemetry-java.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # Ehcache 3
    org.ehcache:*)
      echo "SCM_URL=https://github.com/ehcache/ehcache3.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # MyBatis
    org.mybatis:*)
      echo "SCM_URL=https://github.com/mybatis/mybatis-3.git"
      echo "SCM_REVISION=mybatis-${version}"
      return 0
      ;;

    # SnakeYAML Engine
    org.snakeyaml:snakeyaml-engine)
      echo "SCM_URL=https://bitbucket.org/snakeyaml/snakeyaml-engine.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # Woodstox (FasterXML)
    com.fasterxml.woodstox:woodstox-core|org.codehaus.woodstox:stax2-api)
      echo "SCM_URL=https://github.com/FasterXML/woodstox.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # ANTLR 4
    org.antlr:antlr4|org.antlr:antlr4-runtime)
      echo "SCM_URL=https://github.com/antlr/antlr4.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # MVEL
    org.mvel:mvel2)
      echo "SCM_URL=https://github.com/mvel/mvel.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # JSON (org.json)
    org.json:json)
      echo "SCM_URL=https://github.com/stleary/JSON-java.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Network JSON schema validator (networknt)
    com.networknt:json-schema-validator)
      echo "SCM_URL=https://github.com/networknt/json-schema-validator.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Javassist
    org.javassist:javassist)
      echo "SCM_URL=https://github.com/jboss-javassist/javassist.git"
      echo "SCM_REVISION=rel_${version//./_}"
      return 0
      ;;

    # Joda Time
    joda-time:joda-time)
      echo "SCM_URL=https://github.com/JodaOrg/joda-time.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # MapStruct
    org.mapstruct:mapstruct|org.mapstruct:mapstruct-processor)
      echo "SCM_URL=https://github.com/mapstruct/mapstruct.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Jolokia
    org.jolokia:*)
      echo "SCM_URL=https://github.com/jolokia/jolokia.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # Jasypt
    org.jasypt:jasypt)
      echo "SCM_URL=https://github.com/jasypt/jasypt.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # InfluxDB Java client
    org.influxdb:influxdb-java)
      echo "SCM_URL=https://github.com/influxdata/influxdb-java.git"
      echo "SCM_REVISION=influxdb-java-${version}"
      return 0
      ;;

    # Reflections
    org.reflections:reflections)
      echo "SCM_URL=https://github.com/ronmamo/reflections.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # OpenSearch Java client
    org.opensearch.client:*)
      echo "SCM_URL=https://github.com/opensearch-project/opensearch-java.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Jedis (Redis client)
    redis.clients:jedis)
      echo "SCM_URL=https://github.com/redis/jedis.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # wsdl4j
    wsdl4j:wsdl4j)
      echo "SCM_URL=https://github.com/jvm-build-service-code/wsdl4j.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # commons-beanutils (old groupId)
    commons-beanutils:commons-beanutils)
      echo "SCM_URL=https://github.com/apache/commons-beanutils.git"
      echo "SCM_REVISION=BEANUTILS_${version//./_}"
      return 0
      ;;

    # commons-cli (old groupId)
    commons-cli:commons-cli)
      echo "SCM_URL=https://github.com/apache/commons-cli.git"
      echo "SCM_REVISION=rel/commons-cli-${version}"
      return 0
      ;;

    # commons-collections (old groupId)
    commons-collections:commons-collections)
      echo "SCM_URL=https://github.com/apache/commons-collections.git"
      echo "SCM_REVISION=COLLECTIONS_${version//./_}"
      return 0
      ;;

    # commons-validator (old groupId)
    commons-validator:commons-validator)
      echo "SCM_URL=https://github.com/apache/commons-validator.git"
      echo "SCM_REVISION=rel/commons-validator-${version}"
      return 0
      ;;

    # Kryo
    com.esotericsoftware.kryo:kryo|com.esotericsoftware:kryo)
      echo "SCM_URL=https://github.com/EsotericSoftware/kryo.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Google Cloud / API / Auth Java
    com.google.cloud:*|com.google.api:*|com.google.auth:*|com.google.api-client:*|com.google.oauth-client:*)
      echo "SCM_URL=https://github.com/googleapis/google-cloud-java.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # OpenCensus
    io.opencensus:*)
      echo "SCM_URL=https://github.com/census-instrumentation/opencensus-java.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # Quarkiverse extensions (generic fallback)
    io.quarkiverse.*:*)
      local ext="${group_id#io.quarkiverse.}"
      echo "SCM_URL=https://github.com/quarkiverse/quarkus-${ext}.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Smooks
    org.smooks:*|org.smooks.cartridges:*)
      echo "SCM_URL=https://github.com/smooks/smooks.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # Mozilla Rhino
    org.mozilla:rhino)
      echo "SCM_URL=https://github.com/mozilla/rhino.git"
      echo "SCM_REVISION=Rhino${version//./_}_RELEASE"
      return 0
      ;;

    # Saxon-HE
    net.sf.saxon:Saxon-HE)
      echo "SCM_URL=https://github.com/Saxonica/Saxon-HE.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # docling
    ai.docling:*)
      echo "SCM_URL=https://github.com/DS4SD/docling-serve.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # Sangupta (misc Apache utilities)
    com.sangupta:*)
      echo "SCM_URL=https://github.com/sangupta/murmur.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # Web3j
    org.web3j:*)
      echo "SCM_URL=https://github.com/web3j/web3j.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # Jackson JSON path
    com.jayway.jsonpath:json-path)
      echo "SCM_URL=https://github.com/json-path/JsonPath.git"
      echo "SCM_REVISION=json-path-${version}"
      return 0
      ;;

    # Kiwiproject
    org.kiwiproject:*)
      echo "SCM_URL=https://github.com/kiwiproject/kiwi.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # IBM Cloud SDK Core
    com.ibm.cloud:*)
      echo "SCM_URL=https://github.com/IBM/java-sdk-core.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # IBM MQ
    com.ibm.mq:*)
      echo "SCM_URL=https://github.com/ibm-messaging/mq-jms-spring.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # GraalVM JS
    org.graalvm.js:*)
      echo "SCM_URL=https://github.com/oracle/graaljs.git"
      echo "SCM_REVISION=vm-${version}"
      return 0
      ;;

    # ANTLR 3 runtime (legacy)
    org.antlr:antlr-runtime|org.antlr:antlr)
      echo "SCM_URL=https://github.com/antlr/antlr3.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # ThreeTen Extra
    org.threeten:*)
      echo "SCM_URL=https://github.com/ThreeTen/threeten-extra.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # DataDog sketches
    com.datadoghq:*)
      echo "SCM_URL=https://github.com/DataDog/sketches-java.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # DataStax OSS Quarkus
    com.datastax.oss.quarkus:*)
      echo "SCM_URL=https://github.com/datastax/cassandra-quarkus.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # AWS CRT (native)
    software.amazon.awssdk.crt:*)
      echo "SCM_URL=https://github.com/awslabs/aws-crt-java.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # AMQP Hub Quarkus
    org.amqphub.quarkus:*)
      echo "SCM_URL=https://github.com/amqphub/quarkus-qpid-jms.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # javax.cache / JCache API
    javax.cache:*)
      echo "SCM_URL=https://github.com/jsr107/jsr107spec.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Jakarta JMS API
    jakarta.jms:*)
      echo "SCM_URL=https://github.com/jakartaee/messaging.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # Apache Kudu
    org.apache.kudu:*)
      echo "SCM_URL=https://github.com/apache/kudu.git"
      echo "SCM_REVISION=kudu-${version}"
      return 0
      ;;

    # Apache XML Graphics (Batik / FOP)
    org.apache.xmlgraphics:*)
      echo "SCM_URL=https://github.com/apache/xmlgraphics-commons.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # run.endive
    run.endive:*)
      echo "SCM_URL=https://github.com/endive/endive.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # com.lihaoyi (Scala/Java)
    com.lihaoyi:*)
      echo "SCM_URL=https://github.com/com-lihaoyi/os-lib.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # JXMPP
    org.jxmpp:*)
      echo "SCM_URL=https://github.com/igniterealtime/jxmpp.git"
      echo "SCM_REVISION=jxmpp-${version}"
      return 0
      ;;

    # stax-ex (jvnet)
    org.jvnet.staxex:*)
      echo "SCM_URL=https://github.com/eclipse-ee4j/stax-ex.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # mimepull (jvnet)
    org.jvnet.mimepull:*)
      echo "SCM_URL=https://github.com/eclipse-ee4j/metro-mimepull.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # ThreeTen bp (backport)
    org.threeten:threetenbp)
      echo "SCM_URL=https://github.com/ThreeTen/threetenbp.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # istack-commons (com.sun.istack)
    com.sun.istack:*)
      echo "SCM_URL=https://github.com/eclipse-ee4j/jaxb-istack-commons.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # JAXB external (relaxng / rngom)
    com.sun.xml.bind.external:*)
      echo "SCM_URL=https://github.com/eclipse-ee4j/jaxb-ri.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # FastInfoset
    com.sun.xml.fastinfoset:*)
      echo "SCM_URL=https://github.com/eclipse-ee4j/metro-fi.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # SAAJ
    com.sun.xml.messaging.saaj:*)
      echo "SCM_URL=https://github.com/eclipse-ee4j/metro-saaj.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # xalan
    xalan:*)
      echo "SCM_URL=https://github.com/apache/xalan-java.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # xml-resolver
    xml-resolver:*)
      echo "SCM_URL=https://github.com/xmlresolver/xmlresolver.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;

    # com.google.api-client
    com.google.api-client:*)
      echo "SCM_URL=https://github.com/googleapis/google-api-java-client.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;

    # com.google.oauth-client
    com.google.oauth-client:*)
      echo "SCM_URL=https://github.com/googleapis/google-oauth-java-client.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;
  esac

  return 1
}

# Fetch SCM from JVM Build Data repository
fetch_scm_from_jvm_build_data() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"
  local base="/Users/soghosh/.bob/tmp/150502b6733f681f816890e7f7461ab13058171ce580eae19ef3e4c3c3e4d2b8/jvm-build-data/scm-info"
  local group_path="${group_id//./\/}"
  
  local candidates=(
    "$base/$group_path/_artifact/$artifact_id/_version/$version/scm.yaml"
    "$base/$group_path/_artifact/$artifact_id/scm.yaml"
    "$base/$group_path/scm.yaml"
  )
  
  local file=""
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      file="$candidate"
      break
    fi
  done
  
  [[ -z "$file" ]] && return 1

  local uri path_value revision
  uri="$(yq -r '.uri // ""' "$file" 2>/dev/null || true)"
  path_value="$(yq -r '.path // ""' "$file" 2>/dev/null || true)"
  [[ -z "$uri" ]] && return 1

  revision="$(apply_tag_mapping_from_file "$file" "$version")"
  [[ -z "$revision" || "$revision" == "HEAD" ]] && return 1
  
  if [[ -n "$path_value" && "$path_value" != "null" ]]; then
    uri="${uri%/}/${path_value#/}"
  fi

  echo "SCM_URL=$uri"
  echo "SCM_REVISION=$revision"
}

# Fetch SCM from Camel Spring Boot Data repository
fetch_scm_from_camel_spring_boot_data() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"
  local base="/Users/soghosh/autobuilds/.bob/tmp-camel-spring-boot-depstobuild/scm-info"
  local group_path="${group_id//./\/}"
  
  local candidates=(
    "$base/$group_path/_artifact/$artifact_id/_version/$version/scm.yaml"
    "$base/$group_path/_artifact/$artifact_id/scm.yaml"
    "$base/$group_path/scm.yaml"
  )
  
  local file=""
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      file="$candidate"
      break
    fi
  done
  
  [[ -z "$file" ]] && return 1

  local uri revision
  uri="$(yq -r '.uri // ""' "$file" 2>/dev/null || true)"
  [[ -z "$uri" ]] && return 1

  revision="$(apply_tag_mapping_from_file "$file" "$version")"
  [[ -z "$revision" || "$revision" == "HEAD" ]] && return 1
  
  echo "SCM_URL=$uri"
  echo "SCM_REVISION=$revision"
}

# Fetch SCM from Maven Central POM
fetch_scm_from_maven() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"
  local max_depth="${4:-3}"

  [[ "$max_depth" -le 0 ]] && return 1

  local group_path pom_url pom_content scm_url scm_tag
  group_path="$(echo "$group_id" | tr '.' '/')"
  pom_url="https://repo1.maven.org/maven2/${group_path}/${artifact_id}/${version}/${artifact_id}-${version}.pom"

  # Add timeout to prevent hanging (10 seconds max per curl)
  pom_content="$(curl -fsSL --max-time 10 --connect-timeout 5 "$pom_url" 2>/dev/null || true)"
  [[ -z "$pom_content" ]] && return 1

  # Try to find SCM in current POM
  scm_url="$(echo "$pom_content" | grep -oE '<connection>[^<]+' | head -1 | sed 's/<connection>//' | sed 's#^scm:git:##' | sed 's#^scm:git://##' | sed 's#^scm:svn:##' | sed 's#^scm:##')"
  [[ -z "$scm_url" ]] && scm_url="$(echo "$pom_content" | grep -oE '<developerConnection>[^<]+' | head -1 | sed 's/<developerConnection>//' | sed 's#^scm:git:##' | sed 's#^scm:git://##' | sed 's#^scm:svn:##' | sed 's#^scm:##')"

  scm_tag="$(echo "$pom_content" | grep -oE '<tag>[^<]+' | head -1 | sed 's/<tag>//')"
  if [[ -z "$scm_tag" ]]; then
    scm_tag="$(echo "$pom_content" | grep -oE '<revision>[^<]+' | head -1 | sed 's/<revision>//')"
  fi

  # If SCM found in current POM, use it
  if [[ -n "$scm_url" && -n "$scm_tag" && "$scm_tag" != "HEAD" ]]; then
    echo "SCM_URL=$scm_url"
    echo "SCM_REVISION=$scm_tag"
    return 0
  fi

  # Don't recurse to parent - too slow
  return 1
}

# Apply tag mapping from scm.yaml file
apply_tag_mapping_from_file() {
  local file="$1"
  local version="$2"

  local mapping_type
  mapping_type="$(yq -r '.tagMapping | type // ""' "$file" 2>/dev/null || true)"

  if [[ -z "$mapping_type" || "$mapping_type" == "null" ]]; then
    echo "$version"
    return 0
  fi

  # String-based mapping (simple regex substitution)
  if [[ "$mapping_type" == "!!str" ]]; then
    local mapping lhs rhs
    mapping="$(yq -r '.tagMapping // ""' "$file" 2>/dev/null || true)"
    if [[ -z "$mapping" || "$mapping" != *"->"* ]]; then
      echo "$version"
      return 0
    fi
    lhs="$(echo "$mapping" | awk -F'->' '{print $1}' | xargs)"
    rhs="$(echo "$mapping" | awk -F'->' '{print $2}' | xargs)"
    python3 - "$version" "$lhs" "$rhs" <<'PY'
import re, sys
version, lhs, rhs = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    print(re.sub(lhs, rhs, version))
except re.error:
    print(version)
PY
    return 0
  fi

  echo "$version"
}
