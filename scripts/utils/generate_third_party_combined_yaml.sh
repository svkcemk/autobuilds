#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="build-config.yaml"
OUTPUT_DIR="./third-party-output"
INPUT_ARTIFACT=""
INPUT_BOM=""
ROOT_ARTIFACTS_FILE=""
EXCLUDE_GROUPS="org.apache.camel,org.apache.camel.quarkus"
EFFECTIVE_EXCLUDE_GROUPS=""
WORK_DIR=""
TEMP_POM=""
UNRESOLVED_FILE=""
ENV_DB_FILE="${ENV_DB_FILE:-./env-database.json}"
VERBOSE="${VERBOSE:-false}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

show_usage() {
  cat <<'USAGE'
Generate third-party build configs and one combined YAML.

Usage:
  ./generate_third_party_combined_yaml.sh [OPTIONS]

Options:
  -a, --artifact GAV         Root artifact GAV (groupId:artifactId:version)
  -b, --bom GAV              BOM GAV used for dependencyManagement/import
  -r, --root-artifacts FILE  File with root artifact GAVs, one per line
  -e, --exclude-groups CSV   Comma-separated groups to exclude
                             default: org.apache.camel,org.apache.camel.quarkus
  -c, --config FILE          Config file (default: build-config.yaml)
  -o, --output DIR           Output directory (default: ./third-party-output)
  -h, --help                 Show help
USAGE
  exit 0
}

cleanup() {
  [[ -n "${TEMP_POM:-}" && -f "${TEMP_POM:-}" ]] && rm -f "$TEMP_POM"
  [[ -n "${WORK_DIR:-}" && -d "${WORK_DIR:-}" ]] && rm -rf "$WORK_DIR"
}
trap cleanup EXIT

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a|--artifact) INPUT_ARTIFACT="$2"; shift 2 ;;
      -b|--bom) INPUT_BOM="$2"; shift 2 ;;
      -r|--root-artifacts) ROOT_ARTIFACTS_FILE="$2"; shift 2 ;;
      -e|--exclude-groups) EXCLUDE_GROUPS="$2"; shift 2 ;;
      -c|--config) CONFIG_FILE="$2"; shift 2 ;;
      -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
      -h|--help) show_usage ;;
      *) log_error "Unknown option: $1"; show_usage ;;
    esac
  done
}

validate_gav() {
  [[ "$1" =~ ^[^:]+:[^:]+:[^:]+$ ]]
}

install_yq_if_possible() {
  if command -v yq >/dev/null 2>&1; then
    return 0
  fi

  log_warn "yq not found. Attempting installation..."
  if command -v brew >/dev/null 2>&1; then
    brew install yq && return 0
  fi
  if command -v pip3 >/dev/null 2>&1; then
    pip3 install yq && return 0
  fi

  log_error "Could not install yq automatically. Install it manually and retry."
  exit 1
}

check_prerequisites() {
  command -v bash >/dev/null 2>&1 || { log_error "bash is required"; exit 1; }
  command -v curl >/dev/null 2>&1 || { log_error "curl is required"; exit 1; }
  command -v python3 >/dev/null 2>&1 || { log_error "python3 is required"; exit 1; }
  command -v mvn >/dev/null 2>&1 || { log_error "mvn is required"; exit 1; }
  command -v awk >/dev/null 2>&1 || { log_error "awk is required"; exit 1; }
  command -v sort >/dev/null 2>&1 || { log_error "sort is required"; exit 1; }
  install_yq_if_possible

  if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
  fi
  
  # Initialize environment database if auto-selection enabled
  local auto_select
  auto_select="$(yq -r '.buildConfigGeneratorConfig.environmentSelection.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")"
  
  if [ "$auto_select" = "true" ]; then
    command -v jq >/dev/null 2>&1 || { log_error "jq is required for environment auto-selection"; exit 1; }
    
    if [ ! -f "$ENV_DB_FILE" ]; then
      log_info "Generating environment database from env.txt..."
      if [ -f "env.txt" ]; then
        if command -v ./env_parser.sh >/dev/null 2>&1; then
          ./env_parser.sh -i env.txt -o "$ENV_DB_FILE" >/dev/null 2>&1 || {
            log_warn "Failed to generate environment database. Auto-selection disabled."
          }
        else
          log_warn "env_parser.sh not found. Auto-selection disabled."
        fi
      else
        log_warn "env.txt not found. Auto-selection disabled."
      fi
    fi
  fi

# Environment selection configuration
ENV_DB_FILE="${ENV_DB_FILE:-./env-database.json}"
VERBOSE="${VERBOSE:-false}"

log_verbose() {
  if [[ "$VERBOSE" == "true" ]]; then
    # Output without color codes to avoid breaking variable capture
    echo "[INFO] $1" >&2
  fi
}

# Select build environment ID based on POM analysis
select_build_environment_id() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"
  
  # Check if auto-selection is enabled
  local auto_select
  auto_select="$(yq -r '.buildConfigGeneratorConfig.environmentSelection.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")"
  
  if [ "$auto_select" = "true" ] && [ -f "$ENV_DB_FILE" ]; then
    # Construct POM URL
    local group_path
    group_path="$(echo "$group_id" | tr '.' '/')"
    local pom_url="https://repo1.maven.org/maven2/${group_path}/${artifact_id}/${version}/${artifact_id}-${version}.pom"
    
    # Analyze POM requirements
    local pom_content
    pom_content="$(curl -fsSL "$pom_url" 2>/dev/null || true)"
    
    if [ -n "$pom_content" ]; then
      # Extract Java version
      local java_version
      java_version="$(echo "$pom_content" | \
        grep -oE '<maven\.compiler\.source>[^<]+' | \
        sed 's/<maven\.compiler\.source>//' | head -1)"
      
      if [ -z "$java_version" ]; then
        java_version="$(echo "$pom_content" | \
          grep -oE '<maven\.compiler\.target>[^<]+' | \
          sed 's/<maven\.compiler\.target>//' | head -1)"
      fi
      
      if [ -z "$java_version" ]; then
        java_version="$(echo "$pom_content" | \
          grep -oE '<java\.version>[^<]+' | \
          sed 's/<java\.version>//' | head -1)"
      fi
      
      # Normalize Java version (remove 1. prefix)
      if [[ "$java_version" =~ ^1\.([0-9]+) ]]; then
        java_version="${BASH_REMATCH[1]}"
      fi
      
      # Extract Maven version
      local maven_version
      maven_version="$(echo "$pom_content" | \
        grep -oE '<maven\.version>[^<]+' | \
        sed 's/<maven\.version>//' | head -1)"
      
      # Select environment based on requirements
      if [ -n "$java_version" ]; then
        local selected_env_id
        selected_env_id="$(jq -r --arg jv "$java_version" --arg mv "$maven_version" '
          map(
            . + {
              score: (
                (if .attributes.JDK == $jv then 100 else 0 end) +
                (if (.attributes.JDK // "") | startswith(($jv | split(".")[0])) then 50 else 0 end) +
                (if .attributes.MAVEN == $mv then 30 else 0 end) +
                (if .attributes.MAVEN != null and .attributes.MAVEN != "" then 10 else 0 end) +
                (if .deprecated then -50 else 0 end) +
                (if .hidden then -100 else 0 end)
              )
            }
          ) | sort_by(-.score) | .[0].id
        ' "$ENV_DB_FILE" 2>/dev/null || echo "")"
        
        if [ -n "$selected_env_id" ] && [ "$selected_env_id" != "null" ]; then
          log_verbose "Selected environment ID $selected_env_id for $group_id:$artifact_id:$version (Java $java_version)"
          echo "$selected_env_id"
          return 0
        fi
      fi
    fi
  fi
  
  # Fallback to default
  local default_env_id
  default_env_id="$(get_default_value '.buildConfigGeneratorConfig.defaultValues.environmentId' '316')"
  echo "$default_env_id"
}



  if [[ -n "$INPUT_ARTIFACT" ]] && ! validate_gav "$INPUT_ARTIFACT"; then
    log_error "Invalid --artifact GAV: $INPUT_ARTIFACT"
    exit 1
  fi

  if [[ -n "$INPUT_BOM" ]] && ! validate_gav "$INPUT_BOM"; then
    log_error "Invalid --bom GAV: $INPUT_BOM"
    exit 1
  fi

  if [[ -z "$INPUT_ARTIFACT" && -z "$ROOT_ARTIFACTS_FILE" ]]; then
    log_error "Provide --artifact or --root-artifacts"
    exit 1
  fi

  if [[ -n "$ROOT_ARTIFACTS_FILE" && ! -f "$ROOT_ARTIFACTS_FILE" ]]; then
    log_error "Root artifacts file not found: $ROOT_ARTIFACTS_FILE"
    exit 1
  fi
}

get_default_value() {
  local query="$1"
  local fallback="$2"
  local value
  value="$(yq -r "$query // \"\"" "$CONFIG_FILE" 2>/dev/null || true)"
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "$fallback"
  else
    echo "$value"
  fi
}

prepare_workspace() {
  mkdir -p "$OUTPUT_DIR/build-configs"
  : > "$OUTPUT_DIR/root-artifacts.txt"
  : > "$OUTPUT_DIR/all-dependencies.txt"
  : > "$OUTPUT_DIR/third-party-dependencies.txt"
  : > "$OUTPUT_DIR/dependency-edges.txt"
  : > "$OUTPUT_DIR/unresolved-artifacts.txt"
  UNRESOLVED_FILE="$OUTPUT_DIR/unresolved-artifacts.txt"
  WORK_DIR="$(mktemp -d)"
}

load_effective_exclude_groups() {
  local config_groups cli_groups merged
  config_groups="$(yq -r '.dependencyResolutionConfig.excludeGroups // [] | join(",")' "$CONFIG_FILE" 2>/dev/null || true)"
  cli_groups="$EXCLUDE_GROUPS"
  merged="$(printf '%s\n%s\n' "$cli_groups" "$config_groups" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d' | sort -u | paste -sd, -)"
  EFFECTIVE_EXCLUDE_GROUPS="$merged"
}

load_root_artifacts() {
  if [[ -n "$INPUT_ARTIFACT" ]]; then
    echo "$INPUT_ARTIFACT" >> "$OUTPUT_DIR/root-artifacts.txt"
  fi

  if [[ -n "$ROOT_ARTIFACTS_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="$(echo "$line" | sed 's/#.*$//' | xargs)"
      [[ -z "$line" ]] && continue
      validate_gav "$line" || { log_error "Invalid root artifact GAV: $line"; exit 1; }
      echo "$line" >> "$OUTPUT_DIR/root-artifacts.txt"
    done < "$ROOT_ARTIFACTS_FILE"
  fi

  sort -u "$OUTPUT_DIR/root-artifacts.txt" -o "$OUTPUT_DIR/root-artifacts.txt"
}

generate_temp_pom() {
  TEMP_POM="$WORK_DIR/pom.xml"

  {
    echo '<project xmlns="http://maven.apache.org/POM/4.0.0"'
    echo '         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
    echo '         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">'
    echo '  <modelVersion>4.0.0</modelVersion>'
    echo '  <groupId>local.temp</groupId>'
    echo '  <artifactId>third-party-generator</artifactId>'
    echo '  <version>1.0.0</version>'

    if [[ -n "$INPUT_BOM" ]]; then
      local bom_group bom_artifact bom_version
      bom_group="$(echo "$INPUT_BOM" | cut -d: -f1)"
      bom_artifact="$(echo "$INPUT_BOM" | cut -d: -f2)"
      bom_version="$(echo "$INPUT_BOM" | cut -d: -f3)"
      echo '  <dependencyManagement>'
      echo '    <dependencies>'
      echo '      <dependency>'
      echo "        <groupId>${bom_group}</groupId>"
      echo "        <artifactId>${bom_artifact}</artifactId>"
      echo "        <version>${bom_version}</version>"
      echo '        <type>pom</type>'
      echo '        <scope>import</scope>'
      echo '      </dependency>'
      echo '    </dependencies>'
      echo '  </dependencyManagement>'
    fi

    echo '  <dependencies>'
    while IFS= read -r gav || [[ -n "$gav" ]]; do
      [[ -z "$gav" ]] && continue
      local g a v
      g="$(echo "$gav" | cut -d: -f1)"
      a="$(echo "$gav" | cut -d: -f2)"
      v="$(echo "$gav" | cut -d: -f3)"
      echo '    <dependency>'
      echo "      <groupId>${g}</groupId>"
      echo "      <artifactId>${a}</artifactId>"
      echo "      <version>${v}</version>"
      echo '    </dependency>'
    done < "$OUTPUT_DIR/root-artifacts.txt"
    echo '  </dependencies>'
    echo '</project>'
  } > "$TEMP_POM"
}

resolve_dependency_tree() {
  log_info "Resolving dependency tree with Maven..."
  mvn -f "$TEMP_POM" dependency:tree -DoutputType=text -Dverbose -Dscope=compile > "$WORK_DIR/dependency-tree.txt"
  cp "$WORK_DIR/dependency-tree.txt" "$OUTPUT_DIR/all-dependencies.txt"
}

filter_third_party_dependencies() {
  log_info "Filtering third-party dependencies..."
  python3 - "$WORK_DIR/dependency-tree.txt" "$OUTPUT_DIR/root-artifacts.txt" "$OUTPUT_DIR/third-party-dependencies.txt" "$OUTPUT_DIR/dependency-edges.txt" "$EFFECTIVE_EXCLUDE_GROUPS" <<'PY'
import re
import sys
from pathlib import Path

tree_file = Path(sys.argv[1])
roots_file = Path(sys.argv[2])
deps_out = Path(sys.argv[3])
edges_out = Path(sys.argv[4])
exclude_groups = {x.strip() for x in sys.argv[5].split(",") if x.strip()}

roots = {line.strip() for line in roots_file.read_text().splitlines() if line.strip()}
artifact_re = re.compile(r'([A-Za-z0-9_.\-]+):([A-Za-z0-9_.\-]+):([A-Za-z0-9_.\-]+)(?::([A-Za-z0-9_.\-]+))?:([A-Za-z0-9_.\-]+):([A-Za-z0-9_.\-]+)')
stack = []
deps = set()
edges = set()

for raw in tree_file.read_text().splitlines():
    line = raw[7:] if raw.startswith('[INFO] ') else raw
    if not line.strip():
        continue
    if line.startswith('--- ') or line.startswith('BUILD ') or line.startswith('Scanning for projects'):
        continue
    if 'omitted for duplicate' in line or 'omitted for conflict' in line or 'omitted for cycle' in line:
        continue

    match = artifact_re.search(line)
    if not match:
        continue

    group, artifact, packaging, classifier, version, scope = match.groups()
    gav = f"{group}:{artifact}:{version}"

    prefix = line[:match.start()]
    depth = prefix.count('|  ')
    if '+-' in prefix or '\\-' in prefix:
        depth += 1
    elif prefix.strip():
        depth = 1
    else:
        depth = 0

    while len(stack) > depth:
        stack.pop()

    parent = stack[-1] if stack else None
    if len(stack) < depth:
        stack.extend([None] * (depth - len(stack)))
    if len(stack) == depth:
        stack.append(gav)
    else:
        stack[depth] = gav

    if gav in roots:
        continue
    if group in exclude_groups:
        continue

    deps.add(gav)
    if parent and parent not in roots:
        parent_group = parent.split(':', 1)[0]
        if parent_group not in exclude_groups:
            edges.add((parent, gav))

deps_out.write_text("".join(f"{x}\n" for x in sorted(deps)))
edges_out.write_text("".join(f"{a} {b}\n" for a, b in sorted(edges)))
PY
}

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

apply_tag_mapping_from_file() {
  local file="$1"
  local version="$2"

  local mapping_type
  mapping_type="$(yq -r '.tagMapping | type // ""' "$file" 2>/dev/null || true)"

  if [[ -z "$mapping_type" || "$mapping_type" == "null" ]]; then
    echo "$version"
    return 0
  fi

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

fetch_scm_from_family_rules() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"

  case "$group_id:$artifact_id" in
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
    io.grpc:grpc-alts|io.grpc:grpc-api|io.grpc:grpc-auth|io.grpc:grpc-context|io.grpc:grpc-core|io.grpc:grpc-grpclb|io.grpc:grpc-inprocess|io.grpc:grpc-netty|io.grpc:grpc-protobuf|io.grpc:grpc-stub)
      echo "SCM_URL=https://github.com/grpc/grpc-java.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;
    io.netty:*)
      echo "SCM_URL=https://github.com/netty/netty.git"
      echo "SCM_REVISION=netty-${version}"
      return 0
      ;;
    io.opencensus:opencensus-api|io.opencensus:opencensus-contrib-http-util)
      echo "SCM_URL=https://github.com/census-instrumentation/opencensus-java.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;
    io.opentelemetry:opentelemetry-api|io.opentelemetry:opentelemetry-context)
      echo "SCM_URL=https://github.com/open-telemetry/opentelemetry-java.git"
      echo "SCM_REVISION=v${version}"
      return 0
      ;;
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
    io.vertx:vertx-codegen|io.vertx:vertx-core|io.vertx:vertx-grpc-client|io.vertx:vertx-grpc-common|io.vertx:vertx-grpc-server|io.vertx:vertx-grpc)
      echo "SCM_URL=https://github.com/eclipse-vertx/vert.x.git"
      echo "SCM_REVISION=${version}"
      return 0
      ;;
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

# Query PNC for existing build configs via bacon CLI
query_pnc_build_config() {
  local group_id="$1"
  local artifact_id="$2"
  local current_version="$3"
  
  # Check if bacon CLI is available
  if ! command -v bacon >/dev/null 2>&1; then
    log_verbose "bacon CLI not found, skipping PNC query"
    return 1
  fi
  
  # Convert groupId dots to hyphens for PNC naming convention
  local pnc_group
  pnc_group="$(echo "$group_id" | tr '.' '-')"
  
  # Search pattern: groupId-artifactId-*
  local search_pattern="${pnc_group}-${artifact_id}*"
  
  log_verbose "Querying PNC for build configs matching: $search_pattern"
  
  # Query PNC via bacon CLI
  local pnc_configs
  if ! pnc_configs="$(bacon pnc build-config list --query="name=like=${search_pattern}" -o 2>/dev/null)"; then
    log_verbose "Failed to query PNC"
    return 1
  fi
  
  # Check if we got any results
  if [[ -z "$pnc_configs" || "$pnc_configs" == "[]" ]]; then
    log_verbose "No PNC build configs found for $search_pattern"
    return 1
  fi
  
  # Parse JSON and find most recent non-current version
  local best_config
  best_config="$(echo "$pnc_configs" | jq -r --arg current_ver "$current_version" '
    map(select(.name | test("'"$pnc_group"'-'"$artifact_id"'-")))
    | map(select(.name | test("-'"$current_version"'($|-AUTOBUILD)") | not))
    | sort_by(.modificationTime) | reverse | .[0] // empty
  ' 2>/dev/null || echo "")"
  
  if [[ -n "$best_config" && "$best_config" != "null" ]]; then
    echo "$best_config"
    return 0
  fi
  
  return 1
}

# Search for existing build config from previous versions (local files)
find_previous_build_config_local() {
  local group_id="$1"
  local artifact_id="$2"
  local current_version="$3"
  local search_dirs="${4:-}"
  
  # Get search directories from config if not provided
  if [[ -z "$search_dirs" ]]; then
    search_dirs="$(yq -r '.buildConfigGeneratorConfig.buildScriptReuse.searchDirectories // [] | join(",")' "$CONFIG_FILE" 2>/dev/null || echo "")"
  fi
  
  # If no search directories configured, return
  if [[ -z "$search_dirs" ]]; then
    return 1
  fi
  
  # Search pattern: groupId_artifactId_*.yaml.json
  local search_pattern="${group_id}_${artifact_id}_*.yaml.json"
  local found_config=""
  
  # Search in each directory
  IFS=',' read -ra DIRS <<< "$search_dirs"
  for dir in "${DIRS[@]}"; do
    dir="$(echo "$dir" | xargs)"  # trim whitespace
    [[ -z "$dir" || ! -d "$dir" ]] && continue
    
    # Find matching configs, sort by version (newest first)
    while IFS= read -r config_file; do
      [[ -z "$config_file" ]] && continue
      
      # Extract version from filename
      local file_version
      file_version="$(basename "$config_file" | sed "s/${group_id}_${artifact_id}_//;s/.yaml.json$//")"
      
      # Skip if it's the same version
      [[ "$file_version" == "$current_version" ]] && continue
      
      # Found a previous version
      log_verbose "Found previous build config: $config_file (version: $file_version)"
      found_config="$config_file"
      break 2
    done < <(find "$dir" -name "$search_pattern" -type f 2>/dev/null | sort -V -r)
  done
  
  if [[ -n "$found_config" ]]; then
    echo "$found_config"
    return 0
  fi
  
  return 1
}

resolve_metadata() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"

  # Select environment (with auto-selection if enabled)
  local environment_id
  environment_id="$(select_build_environment_id "$group_id" "$artifact_id" "$version")"
  
  local default_script default_build_type
  default_script="$(get_default_value '.buildConfigGeneratorConfig.defaultValues.buildScript' 'mvn -Dmaven.test.skip=true -Dartifactory.staging.skip=true -DskipNexusStagingDeployMojo=true clean source:jar deploy')"
  default_build_type="$(get_default_value '.buildConfigGeneratorConfig.defaultValues.buildType' 'MVN')"

  # Try to find and reuse build script from previous version
  local previous_config=""
  local pnc_config=""
  
  # Check if build script reuse is enabled
  local reuse_enabled
  reuse_enabled="$(yq -r '.buildConfigGeneratorConfig.buildScriptReuse.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")"
  
  if [[ "$reuse_enabled" == "true" ]]; then
    # First try PNC if enabled
    if [[ "$(yq -r '.buildConfigGeneratorConfig.buildScriptReuse.pnc.enabled // false' "$CONFIG_FILE")" == "true" ]]; then
      log_verbose "Checking PNC for previous build config: $group_id:$artifact_id"
      pnc_config="$(query_pnc_build_config "$group_id" "$artifact_id" "$version")"
      if [[ -n "$pnc_config" ]]; then
        log_info "Found PNC build config for $group_id:$artifact_id"
        previous_config="pnc"
      fi
    fi
    
    # Fall back to local search if PNC didn't find anything
    if [[ -z "$previous_config" ]]; then
      previous_config="$(find_previous_build_config_local "$group_id" "$artifact_id" "$version")"
    fi
  fi
  
  if [[ -n "$previous_config" ]]; then
    log_verbose "Reusing build configuration from: $previous_config"
    
    # Extract build script and build type from previous config
    local prev_script prev_type prev_env_id
    
    if [[ "$previous_config" == "pnc" ]]; then
      # Extract from PNC JSON
      prev_script="$(echo "$pnc_config" | jq -r '.buildScript // ""' 2>/dev/null || echo "")"
      prev_type="$(echo "$pnc_config" | jq -r '.buildType // ""' 2>/dev/null || echo "")"
      prev_env_id="$(echo "$pnc_config" | jq -r '.environment.id // ""' 2>/dev/null || echo "")"
    else
      # Extract from local file
      prev_script="$(jq -r '.buildScript // ""' "$previous_config" 2>/dev/null || echo "")"
      prev_type="$(jq -r '.buildType // ""' "$previous_config" 2>/dev/null || echo "")"
      prev_env_id="$(jq -r '.environmentId // ""' "$previous_config" 2>/dev/null || echo "")"
    fi
    
    # Use previous values if they exist, otherwise use defaults
    [[ -n "$prev_script" ]] && default_script="$prev_script"
    [[ -n "$prev_type" ]] && default_build_type="$prev_type"
    
    # Optionally reuse environment ID from previous version
    local reuse_env_id
    reuse_env_id="$(yq -r '.buildConfigGeneratorConfig.buildScriptReuse.reuseEnvironmentId // false' "$CONFIG_FILE" 2>/dev/null || echo "false")"
    if [[ "$reuse_env_id" == "true" && -n "$prev_env_id" && "$prev_env_id" != "null" ]]; then
      environment_id="$prev_env_id"
      log_verbose "Reusing environment ID $environment_id from previous version"
    fi
  fi

  local scm_data=""
  scm_data="$(fetch_scm_from_family_rules "$group_id" "$artifact_id" "$version" || true)"
  [[ -z "$scm_data" ]] && scm_data="$(fetch_scm_from_jvm_build_data "$group_id" "$artifact_id" "$version" || true)"
  [[ -z "$scm_data" ]] && scm_data="$(fetch_scm_from_camel_spring_boot_data "$group_id" "$artifact_id" "$version" || true)"
  [[ -z "$scm_data" ]] && scm_data="$(fetch_scm_from_maven "$group_id" "$artifact_id" "$version" || true)"

  if [[ -z "$scm_data" ]]; then
    echo "${group_id}:${artifact_id}:${version}" >> "$UNRESOLVED_FILE"
    return 1
  fi

  local scm_url scm_revision
  scm_url="$(echo "$scm_data" | awk -F= '/^SCM_URL=/{print substr($0,9)}')"
  scm_revision="$(echo "$scm_data" | awk -F= '/^SCM_REVISION=/{print substr($0,14)}')"

  if [[ -z "$scm_url" || -z "$scm_revision" || "$scm_revision" == "HEAD" || "$scm_url" == *placeholder* ]]; then
    echo "${group_id}:${artifact_id}:${version}" >> "$UNRESOLVED_FILE"
    return 1
  fi

  echo "SCM_URL=$scm_url"
  echo "SCM_REVISION=$scm_revision"
  echo "BUILD_SCRIPT=$default_script"
  echo "BUILD_TYPE=$default_build_type"
  echo "ENVIRONMENT_ID=$environment_id"
}

generate_individual_configs() {
  log_info "Generating individual third-party build configs..."
  : > "$UNRESOLVED_FILE"

  while IFS= read -r gav || [[ -n "$gav" ]]; do
    [[ -z "$gav" ]] && continue

    local group_id artifact_id version metadata scm_url scm_revision build_script build_type environment_id config_name config_file
    group_id="$(echo "$gav" | cut -d: -f1)"
    artifact_id="$(echo "$gav" | cut -d: -f2)"
    version="$(echo "$gav" | cut -d: -f3)"

    if ! metadata="$(resolve_metadata "$group_id" "$artifact_id" "$version")"; then
      continue
    fi

    scm_url="$(echo "$metadata" | awk -F= '/^SCM_URL=/{print substr($0,9)}')"
    scm_revision="$(echo "$metadata" | awk -F= '/^SCM_REVISION=/{print substr($0,14)}')"
    build_script="$(echo "$metadata" | awk -F= '/^BUILD_SCRIPT=/{print substr($0,14)}')"
    build_type="$(echo "$metadata" | awk -F= '/^BUILD_TYPE=/{print substr($0,12)}')"
    environment_id="$(echo "$metadata" | awk -F= '/^ENVIRONMENT_ID=/{print substr($0,16)}')"

    config_name="${group_id}_${artifact_id}_${version}"
    config_file="$OUTPUT_DIR/build-configs/${config_name}.yaml"

    python3 - "$config_file.json" "$config_name" "$artifact_id" "$gav" "$scm_url" "$scm_revision" "$build_type" "$environment_id" "$build_script" <<'PY'
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
data = {
    "name": sys.argv[2],
    "project": sys.argv[3],
    "description": f"Auto-generated third-party build config for {sys.argv[4]}",
    "scmUrl": sys.argv[5],
    "scmRevision": sys.argv[6],
    "buildType": sys.argv[7],
    "environmentId": int(sys.argv[8]),
    "buildScript": sys.argv[9],
}
out.write_text(json.dumps(data, indent=2) + "\n")
PY
  done < "$OUTPUT_DIR/third-party-dependencies.txt"

  sort -u "$UNRESOLVED_FILE" -o "$UNRESOLVED_FILE"
  if [[ -s "$UNRESOLVED_FILE" ]]; then
    log_error "Exact SCM resolution failed for one or more artifacts. See: $UNRESOLVED_FILE"
    exit 1
  fi
}

generate_combined_yaml() {
  log_info "Generating combined topologically sorted YAML..."

  local product_name product_abbreviation product_stage version milestone group release_file release_dir default_build_type default_environment_id default_build_script
  product_name="$(get_default_value '.buildConfigGeneratorConfig.pigTemplate.product.name' 'Camel Extensions for Quarkus Third Party Components')"
  product_abbreviation="$(get_default_value '.buildConfigGeneratorConfig.pigTemplate.product.abbreviation' 'ceq-third-party')"
  product_stage="$(get_default_value '.buildConfigGeneratorConfig.pigTemplate.product.stage' 'GA')"
  version="$(get_default_value '.buildConfigGeneratorConfig.pigTemplate.version' '0.0.0')"
  milestone="$(get_default_value '.buildConfigGeneratorConfig.pigTemplate.milestone' 'DR1')"
  group="$(get_default_value '.buildConfigGeneratorConfig.pigTemplate.group' 'generated-third-party-group')"
  release_file="$(get_default_value '.buildConfigGeneratorConfig.pigTemplate.outputPrefixes.releaseFile' 'third-party')"
  release_dir="$(get_default_value '.buildConfigGeneratorConfig.pigTemplate.outputPrefixes.releaseDir' 'third-party')"
  default_build_type="$(get_default_value '.buildConfigGeneratorConfig.defaultValues.buildType' 'MVN')"
  default_environment_id="$(get_default_value '.buildConfigGeneratorConfig.defaultValues.environmentId' '316')"
  default_build_script="$(get_default_value '.buildConfigGeneratorConfig.defaultValues.buildScript' 'mvn -Dmaven.test.skip=true -Dartifactory.staging.skip=true -DskipNexusStagingDeployMojo=true clean source:jar deploy')"

  python3 - "$OUTPUT_DIR/third-party-dependencies.txt" "$OUTPUT_DIR/dependency-edges.txt" "$OUTPUT_DIR/build-configs" "$OUTPUT_DIR/combined-build-configs.yaml" "$product_name" "$product_abbreviation" "$product_stage" "$version" "$milestone" "$group" "$release_file" "$release_dir" "$default_build_type" "$default_environment_id" "$default_build_script" <<'PY'
import sys
from pathlib import Path
from collections import defaultdict, deque
import json

deps_file = Path(sys.argv[1])
edges_file = Path(sys.argv[2])
configs_dir = Path(sys.argv[3])
out_file = Path(sys.argv[4])
product_name = sys.argv[5]
product_abbreviation = sys.argv[6]
product_stage = sys.argv[7]
version = sys.argv[8]
milestone = sys.argv[9]
group = sys.argv[10]
release_file = sys.argv[11]
release_dir = sys.argv[12]
default_build_type = sys.argv[13]
default_environment_id = int(sys.argv[14])
default_build_script = sys.argv[15]

nodes = [line.strip() for line in deps_file.read_text().splitlines() if line.strip()]
node_set = set(nodes)

adj = defaultdict(set)
indegree = {n: 0 for n in nodes}
reverse = defaultdict(set)

for line in edges_file.read_text().splitlines():
    line = line.strip()
    if not line:
        continue
    a, b = line.split(" ", 1)
    if a in node_set and b in node_set and b not in adj[a]:
        adj[a].add(b)
        reverse[b].add(a)
        indegree[b] += 1

queue = deque(sorted([n for n in nodes if indegree[n] == 0]))
ordered = []
while queue:
    n = queue.popleft()
    ordered.append(n)
    for m in sorted(adj[n]):
        indegree[m] -= 1
        if indegree[m] == 0:
            queue.append(m)

if len(ordered) != len(nodes):
    ordered.extend(sorted(set(nodes) - set(ordered)))

def load_json(path):
    return json.loads(path.read_text())

result = {
    "product": {
        "name": product_name,
        "abbreviation": product_abbreviation,
        "stage": product_stage,
    },
    "version": version,
    "milestone": milestone,
    "group": group,
    "defaultBuildParameters": {
        "buildType": default_build_type,
        "environmentId": default_environment_id,
        "buildScript": default_build_script,
    },
    "builds": [],
    "outputPrefixes": {
        "releaseFile": release_file,
        "releaseDir": release_dir,
    },
    "flow": {
        "repositoryGeneration": {"strategy": "IGNORE"},
        "licensesGeneration": {"strategy": "IGNORE"},
        "javadocGeneration": {"strategy": "IGNORE"},
        "sourcesGeneration": {"strategy": "IGNORE"},
    },
}

for gav in ordered:
    group_id, artifact_id, artifact_version = gav.split(":")
    name = f"{group_id}_{artifact_id}_{artifact_version}"
    cfg_file = configs_dir / f"{name}.yaml.json"
    data = load_json(cfg_file)
    deps = sorted(f"{p.split(':')[0]}_{p.split(':')[1]}_{p.split(':')[2]}" for p in reverse.get(gav, set()))
    if deps:
        data["dependencies"] = deps
    result["builds"].append(data)

def emit_scalar(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    text = str(value)
    if text == "" or any(ch in text for ch in [":", "#", "{", "}", "[", "]", ",", "&", "*", "?", "|", ">", "%", "@", "`", '"', "'"]) or text.strip() != text:
        return json.dumps(text)
    return text

def dump_yaml(obj, indent=0):
    lines = []
    prefix = " " * indent
    if isinstance(obj, dict):
        for key, value in obj.items():
            if isinstance(value, (dict, list)):
                lines.append(f"{prefix}{key}:")
                lines.extend(dump_yaml(value, indent + 2))
            elif isinstance(value, str) and "\n" in value:
                lines.append(f"{prefix}{key}: |")
                for line in value.splitlines():
                    lines.append(" " * (indent + 2) + line)
            else:
                lines.append(f"{prefix}{key}: {emit_scalar(value)}")
    elif isinstance(obj, list):
        for item in obj:
            if isinstance(item, dict):
                first = True
                for key, value in item.items():
                    item_prefix = f"{prefix}- " if first else " " * (indent + 2)
                    if isinstance(value, (dict, list)):
                        lines.append(f"{item_prefix}{key}:")
                        lines.extend(dump_yaml(value, indent + 4))
                    elif isinstance(value, str) and "\n" in value:
                        lines.append(f"{item_prefix}{key}: |")
                        for line in value.splitlines():
                            lines.append(" " * (indent + 4) + line)
                    else:
                        lines.append(f"{item_prefix}{key}: {emit_scalar(value)}")
                    first = False
            elif isinstance(item, list):
                lines.append(f"{prefix}-")
                lines.extend(dump_yaml(item, indent + 2))
            elif isinstance(item, str) and "\n" in item:
                lines.append(f"{prefix}- |")
                for line in item.splitlines():
                    lines.append(" " * (indent + 2) + line)
            else:
                lines.append(f"{prefix}- {emit_scalar(item)}")
    return lines

out_file.write_text("\n".join(dump_yaml(result)) + "\n")
PY
}

generate_pig_config() {
  local pig_file="$OUTPUT_DIR/pig-config.yaml"
  if yq -e '.buildConfigGeneratorConfig.pigTemplate' "$CONFIG_FILE" >/dev/null 2>&1; then
    yq -r '.buildConfigGeneratorConfig.pigTemplate' "$CONFIG_FILE" > "$pig_file"
  else
    cat > "$pig_file" <<'YAML'
product:
  name: Generated Product
  abbreviation: generated-product
  stage: GA
version: 1.0.0
milestone: DR1
group: generated-third-party-group
outputPrefixes:
  releaseFile: generated-third-party
  releaseDir: generated-third-party
flow:
  repositoryGeneration:
    strategy: IGNORE
  licensesGeneration:
    strategy: IGNORE
  javadocGeneration:
    strategy: IGNORE
  sourcesGeneration:
    strategy: IGNORE
YAML
  fi
}

generate_report() {
  local report_file="$OUTPUT_DIR/build-report.txt"
  local roots third_party configs unresolved
  roots="$(wc -l < "$OUTPUT_DIR/root-artifacts.txt" | tr -d ' ')"
  third_party="$(wc -l < "$OUTPUT_DIR/third-party-dependencies.txt" | tr -d ' ')"
  configs="$(find "$OUTPUT_DIR/build-configs" -name '*.yaml' | wc -l | tr -d ' ')"
  unresolved="$(wc -l < "$OUTPUT_DIR/unresolved-artifacts.txt" | tr -d ' ')"

  cat > "$report_file" <<REPORT
================================================================================
Third-Party Combined Build Config Report
================================================================================
Generated: $(date)
Config File: $CONFIG_FILE
Input Artifact: ${INPUT_ARTIFACT:-N/A}
Input BOM: ${INPUT_BOM:-N/A}
Excluded Groups: $EFFECTIVE_EXCLUDE_GROUPS

Summary:
--------
Root Artifacts: $roots
Third-Party Dependencies: $third_party
Individual Build Configs Generated: $configs
Unresolved SCM Artifacts: $unresolved
Combined YAML: $OUTPUT_DIR/combined-build-configs.yaml

Files Generated:
----------------
- root-artifacts.txt
- all-dependencies.txt
- third-party-dependencies.txt
- dependency-edges.txt
- unresolved-artifacts.txt
- build-configs/*.yaml
- combined-build-configs.yaml
- pig-config.yaml
- build-report.txt
================================================================================
REPORT
}

main() {
  parse_args "$@"
  check_prerequisites
  prepare_workspace
  load_effective_exclude_groups
  load_root_artifacts
  generate_temp_pom
  resolve_dependency_tree
  filter_third_party_dependencies
  generate_individual_configs
  generate_combined_yaml
  generate_pig_config
  generate_report
  log_success "Done. Output written to $OUTPUT_DIR"
}

main "$@"