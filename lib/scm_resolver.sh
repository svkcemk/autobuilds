#!/usr/bin/env bash
# SCM Resolution Library
# Shared library for resolving SCM URLs and revisions for Maven artifacts
# Part of the PNC Build Config Generator consolidation effort

set -euo pipefail

# Main entry point for SCM resolution
# Tries multiple sources in order: family rules, JVM build data, Camel data, Maven Central
# Args: group_id artifact_id version
# Returns: SCM_URL=... and SCM_REVISION=... on stdout, or exits with error
resolve_scm() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"
  
  local scm_data=""
  
  # PRIORITY 1: Try PNC existing build configs FIRST (copy from existing builds)
  # This is the most reliable source - if it's already built in PNC, reuse that SCM info
  scm_data="$(fetch_scm_from_pnc "$group_id" "$artifact_id" "$version" 2>/dev/null || true)"
  if [[ -n "$scm_data" ]]; then
    echo "$scm_data"
    return 0
  fi
  
  # PRIORITY 2: Family Rules (fast, hardcoded patterns for common libraries)
  scm_data="$(fetch_scm_from_family_rules "$group_id" "$artifact_id" "$version" 2>/dev/null || true)"
  if [[ -n "$scm_data" ]]; then
    echo "$scm_data"
    return 0
  fi
  
  # PRIORITY 3: JVM Build Data (cached from previous builds)
  scm_data="$(fetch_scm_from_jvm_build_data "$group_id" "$artifact_id" "$version" 2>/dev/null || true)"
  if [[ -n "$scm_data" ]]; then
    echo "$scm_data"
    return 0
  fi
  
  # PRIORITY 4: Camel Spring Boot Data (Camel-specific)
  scm_data="$(fetch_scm_from_camel_spring_boot_data "$group_id" "$artifact_id" "$version" 2>/dev/null || true)"
  if [[ -n "$scm_data" ]]; then
    echo "$scm_data"
    return 0
  fi
  
  # PRIORITY 5: Maven Central POM (slowest, downloads and parses POM)
  scm_data="$(fetch_scm_from_maven "$group_id" "$artifact_id" "$version" 2>/dev/null || true)"
  if [[ -n "$scm_data" ]]; then
    echo "$scm_data"
    return 0
  fi
  
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
  
  # Search for build config matching the artifact
  # PNC build config names follow pattern: groupId_artifactId_version (with dots replaced by underscores)
  local search_pattern="${group_id//./_}_${artifact_id}_${version}"
  local pnc_output
  
  # Try exact match first with 10 second timeout
  pnc_output="$(timeout 10 bacon pnc build-config list --query="name==${search_pattern}" -o 2>/dev/null || echo '[]')"
  
  # Check if we got results, if not try wildcard patterns
  local result_count
  result_count=$(echo "$pnc_output" | jq 'length' 2>/dev/null || echo "0")
  
  if [[ "$result_count" -eq 0 ]]; then
    # Try wildcard pattern: *artifactId*version*
    search_pattern="*${artifact_id}*${version}*"
    pnc_output="$(timeout 10 bacon pnc build-config list --query="name=like=${search_pattern}" -o 2>/dev/null || echo '[]')"
    result_count=$(echo "$pnc_output" | jq 'length' 2>/dev/null || echo "0")
    
    if [[ "$result_count" -eq 0 ]]; then
      # Last resort: just artifact name with wildcards
      search_pattern="*${artifact_id}*"
      pnc_output="$(timeout 10 bacon pnc build-config list --query="name=like=${search_pattern}" -o 2>/dev/null || echo '[]')"
      result_count=$(echo "$pnc_output" | jq 'length' 2>/dev/null || echo "0")
      
      if [[ "$result_count" -eq 0 ]]; then
        return 1
      fi
    fi
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
    
    # Google API family
    com.google.api:api-common)
      echo "SCM_URL=https://github.com/googleapis/api-common-java.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;
    com.google.api:gax|com.google.api:gax-grpc|com.google.api:gax-httpjson)
      echo "SCM_URL=https://github.com/googleapis/gax-java.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;
    com.google.api.grpc:proto-google-cloud-pubsub-v1|com.google.api.grpc:proto-google-common-protos|com.google.api.grpc:proto-google-iam-v1)
      echo "SCM_URL=https://github.com/googleapis/sdk-platform-java.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;
    com.google.auth:google-auth-library-credentials|com.google.auth:google-auth-library-oauth2-http)
      echo "SCM_URL=https://github.com/googleapis/google-auth-library-java.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;
    com.google.cloud:google-cloud-pubsub)
      echo "SCM_URL=https://github.com/googleapis/java-pubsub.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;
    com.google.code.gson:gson)
      echo "SCM_URL=https://github.com/google/gson.git"
      echo "SCM_REVISION=gson-parent-${version}"
      return 0
      ;;
    com.google.errorprone:error_prone_annotations)
      echo "SCM_URL=https://github.com/google/error-prone.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;
    
    # Google Guava family
    com.google.guava:failureaccess|com.google.guava:guava|com.google.guava:listenablefuture)
      echo "SCM_URL=https://github.com/google/guava.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;
    com.google.http-client:google-http-client|com.google.http-client:google-http-client-gson)
      echo "SCM_URL=https://github.com/googleapis/google-http-java-client.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;
    com.google.j2objc:j2objc-annotations)
      echo "SCM_URL=https://github.com/google/j2objc.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    com.google.protobuf:protobuf-java|com.google.protobuf:protobuf-java-util)
      echo "SCM_URL=https://github.com/protocolbuffers/protobuf.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;
    
    # gRPC family
    io.grpc:grpc-alts|io.grpc:grpc-api|io.grpc:grpc-auth|io.grpc:grpc-context|io.grpc:grpc-core|io.grpc:grpc-grpclb|io.grpc:grpc-inprocess|io.grpc:grpc-netty|io.grpc:grpc-protobuf|io.grpc:grpc-stub)
      echo "SCM_URL=https://github.com/grpc/grpc-java.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;
    
    # Netty family
    io.netty:*)
      echo "SCM_URL=https://github.com/netty/netty.git"
      echo "SCM_REVISION=netty-${version}"
      return 0
      ;;
    
    # OpenCensus family
    io.opencensus:opencensus-api|io.opencensus:opencensus-contrib-http-util)
      echo "SCM_URL=https://github.com/census-instrumentation/opencensus-java.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;
    
    # OpenTelemetry family
    io.opentelemetry:opentelemetry-api|io.opentelemetry:opentelemetry-context)
      echo "SCM_URL=https://github.com/open-telemetry/opentelemetry-java.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;
    
    # SmallRye family
    io.smallrye.common:*)
      echo "SCM_URL=https://github.com/smallrye/smallrye-common.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    io.smallrye.config:*)
      echo "SCM_URL=https://github.com/smallrye/smallrye-config.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    io.smallrye.reactive:mutiny|io.smallrye.reactive:mutiny-smallrye-context-propagation)
      echo "SCM_URL=https://github.com/smallrye/smallrye-mutiny.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    io.smallrye.reactive:smallrye-mutiny-vertx-core|io.smallrye.reactive:smallrye-mutiny-vertx-runtime|io.smallrye.reactive:vertx-mutiny-generator)
      echo "SCM_URL=https://github.com/smallrye/smallrye-mutiny-vertx-bindings.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    io.smallrye:smallrye-context-propagation|io.smallrye:smallrye-context-propagation-api|io.smallrye:smallrye-context-propagation-storage)
      echo "SCM_URL=https://github.com/smallrye/smallrye-context-propagation.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    io.smallrye:smallrye-fault-tolerance-vertx)
      echo "SCM_URL=https://github.com/smallrye/smallrye-fault-tolerance.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    
    # Vert.x family
    io.vertx:vertx-codegen|io.vertx:vertx-core|io.vertx:vertx-grpc-client|io.vertx:vertx-grpc-common|io.vertx:vertx-grpc-server|io.vertx:vertx-grpc)
      echo "SCM_URL=https://github.com/eclipse-vertx/vert.x.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    
    # Jakarta EE family
    jakarta.activation:jakarta.activation-api)
      echo "SCM_URL=https://github.com/jakartaee/jaf-api.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    jakarta.annotation:jakarta.annotation-api)
      echo "SCM_URL=https://github.com/jakartaee/common-annotations-api.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    jakarta.el:jakarta.el-api)
      echo "SCM_URL=https://github.com/jakartaee/expression-language.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    jakarta.enterprise:jakarta.enterprise.lang-model)
      echo "SCM_URL=https://github.com/jakartaee/cdi.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    jakarta.interceptor:jakarta.interceptor-api)
      echo "SCM_URL=https://github.com/jakartaee/interceptors.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    jakarta.json:jakarta.json-api)
      echo "SCM_URL=https://github.com/jakartaee/jsonp-api.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    jakarta.transaction:jakarta.transaction-api)
      echo "SCM_URL=https://github.com/jakartaee/transactions.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    jakarta.xml.bind:jakarta.xml.bind-api)
      echo "SCM_URL=https://github.com/jakartaee/jaxb-api.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    
    # Apache Commons family
    org.apache.httpcomponents:httpclient)
      echo "SCM_URL=https://github.com/apache/httpcomponents-client.git"
      echo "SCM_REVISION=rel/v${version}"
      return 0
      ;;
    org.apache.httpcomponents:httpcore)
      echo "SCM_URL=https://github.com/apache/httpcomponents-core.git"
      echo "SCM_REVISION=rel/v${version}"
      return 0
      ;;
    org.apache.logging.log4j:log4j-api)
      echo "SCM_URL=https://github.com/apache/logging-log4j2.git"
      echo "SCM_REVISION=rel/${version}"
      return 0
      ;;
    
    # Other common libraries
    org.conscrypt:conscrypt-openjdk-uber)
      echo "SCM_URL=https://github.com/google/conscrypt.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;
    org.eclipse.microprofile.config:microprofile-config-api)
      echo "SCM_URL=https://github.com/eclipse/microprofile-config.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    org.eclipse.microprofile.context-propagation:microprofile-context-propagation-api)
      echo "SCM_URL=https://github.com/eclipse/microprofile-context-propagation.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    org.eclipse.parsson:parsson)
      echo "SCM_URL=https://github.com/eclipse-ee4j/parsson.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    org.jboss.logmanager:log4j2-jboss-logmanager)
      echo "SCM_URL=https://github.com/jboss-logging/log4j2-jboss-logmanager.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    org.jboss.threads:jboss-threads)
      echo "SCM_URL=https://github.com/jbossas/jboss-threads.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    org.jctools:jctools-core)
      echo "SCM_URL=https://github.com/JCTools/JCTools.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;
    org.jspecify:jspecify)
      echo "SCM_URL=https://github.com/jspecify/jspecify.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
    org.ow2.asm:asm)
      echo "SCM_URL=https://gitlab.ow2.org/asm/asm.git"
      echo "SCM_REVISION=ASM_${version//./_}"
      return 0
      ;;
    org.slf4j:slf4j-api)
      echo "SCM_URL=https://github.com/qos-ch/slf4j.git"
      echo "SCM_REVISION=v_${version}"
      return 0
      ;;
    org.wildfly.common:wildfly-common)
      echo "SCM_URL=https://github.com/wildfly/wildfly-common.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
  esac

  return 1
}

# Fetch SCM from JVM Build Data repository
# Searches in hierarchical structure: version-specific, artifact-specific, group-specific
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
# Parses <scm> section from POM file
fetch_scm_from_maven() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"

  local group_path pom_url pom_content scm_url scm_tag
  group_path="$(echo "$group_id" | tr '.' '/')"
  pom_url="https://repo1.maven.org/maven2/${group_path}/${artifact_id}/${version}/${artifact_id}-${version}.pom"

  pom_content="$(curl -fsSL "$pom_url" 2>/dev/null || true)"
  [[ -z "$pom_content" ]] && return 1

  scm_url="$(echo "$pom_content" | grep -oE '<connection>[^<]+' | head -1 | sed 's/<connection>//' | sed 's#^scm:git:##' | sed 's#^scm:git://##' | sed 's#^scm:svn:##' | sed 's#^scm:##')"
  [[ -z "$scm_url" ]] && scm_url="$(echo "$pom_content" | grep -oE '<developerConnection>[^<]+' | head -1 | sed 's/<developerConnection>//' | sed 's#^scm:git:##' | sed 's#^scm:git://##' | sed 's#^scm:svn:##' | sed 's#^scm:##')"

  scm_tag="$(echo "$pom_content" | grep -oE '<tag>[^<]+' | head -1 | sed 's/<tag>//')"
  if [[ -z "$scm_tag" ]]; then
    scm_tag="$(echo "$pom_content" | grep -oE '<revision>[^<]+' | head -1 | sed 's/<revision>//')"
  fi

  [[ -z "$scm_url" ]] && return 1
  [[ -z "$scm_tag" || "$scm_tag" == "HEAD" ]] && return 1

  echo "SCM_URL=$scm_url"
  echo "SCM_REVISION=$scm_tag"
}

# Apply tag mapping from scm.yaml file
# Supports both string and array-based mappings
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

  # Array-based mapping (multiple pattern/tag pairs)
  if [[ "$mapping_type" == "!!seq" ]]; then
    local count i pattern tag
    count="$(yq -r '.tagMapping | length' "$file" 2>/dev/null || echo 0)"
    i=0
    while [[ "$i" -lt "$count" ]]; do
      pattern="$(yq -r ".tagMapping[$i].pattern // \"\"" "$file" 2>/dev/null || true)"
      tag="$(yq -r ".tagMapping[$i].tag // \"\"" "$file" 2>/dev/null || true)"
      if [[ -n "$pattern" && -n "$tag" ]]; then
        local mapped
        mapped="$(python3 - "$version" "$pattern" "$tag" <<'PY'
import re, sys
version, pattern, tag = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    if re.search(pattern, version):
        print(re.sub(pattern, tag, version))
    else:
        print("")
except re.error:
    print("")
PY
)"
        if [[ -n "$mapped" ]]; then
          echo "$mapped"
          return 0
        fi
      fi
      i=$((i + 1))
    done
  fi

  echo "$version"
}
