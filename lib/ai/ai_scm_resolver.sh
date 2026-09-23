#!/usr/bin/env bash
# AI-Enhanced SCM Resolution
# Uses AI to intelligently resolve SCM URLs when traditional methods fail
# Part of the AI-Assisted Productization Tool

set -euo pipefail

# Source the base SCM resolver
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/lib/scm_resolver.sh"

# AI-powered SCM resolution using pattern matching and heuristics
# This function is called when all traditional methods fail
# Args: group_id artifact_id version
# Returns: SCM_URL=... and SCM_REVISION=... on stdout, or exits with error
ai_resolve_scm() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"
  
  echo "[AI] Attempting intelligent SCM resolution for $group_id:$artifact_id:$version" >&2
  
  # Strategy 1: GitHub organization inference from groupId
  local scm_url scm_revision
  if scm_url=$(infer_github_from_groupid "$group_id" "$artifact_id" "$version"); then
    scm_revision=$(infer_tag_from_version "$version" "$artifact_id")
    if verify_scm_exists "$scm_url" "$scm_revision"; then
      echo "SCM_URL=$scm_url"
      echo "SCM_REVISION=$scm_revision"
      echo "[AI] ✓ Resolved via GitHub organization inference" >&2
      return 0
    fi
  fi
  
  # Strategy 2: Common naming patterns
  if scm_url=$(try_common_naming_patterns "$group_id" "$artifact_id"); then
    scm_revision=$(infer_tag_from_version "$version" "$artifact_id")
    if verify_scm_exists "$scm_url" "$scm_revision"; then
      echo "SCM_URL=$scm_url"
      echo "SCM_REVISION=$scm_revision"
      echo "[AI] ✓ Resolved via common naming patterns" >&2
      return 0
    fi
  fi
  
  # Strategy 3: Search GitHub API
  if scm_url=$(search_github_api "$group_id" "$artifact_id"); then
    scm_revision=$(infer_tag_from_version "$version" "$artifact_id")
    if verify_scm_exists "$scm_url" "$scm_revision"; then
      echo "SCM_URL=$scm_url"
      echo "SCM_REVISION=$scm_revision"
      echo "[AI] ✓ Resolved via GitHub API search" >&2
      return 0
    fi
  fi
  
  # Strategy 4: Analyze artifact metadata from Maven Central
  if scm_url=$(analyze_maven_metadata "$group_id" "$artifact_id" "$version"); then
    scm_revision=$(infer_tag_from_version "$version" "$artifact_id")
    echo "SCM_URL=$scm_url"
    echo "SCM_REVISION=$scm_revision"
    echo "[AI] ✓ Resolved via Maven metadata analysis" >&2
    return 0
  fi
  
  echo "[AI] ✗ Unable to resolve SCM using AI methods" >&2
  return 1
}

# Infer GitHub URL from groupId patterns
# Examples:
#   com.github.user -> https://github.com/user
#   io.github.user -> https://github.com/user
#   org.projectname -> https://github.com/projectname (try)
infer_github_from_groupid() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"
  
  # Pattern 1: com.github.username or io.github.username
  if [[ "$group_id" =~ ^(com|io)\.github\.([a-zA-Z0-9_-]+)$ ]]; then
    local username="${BASH_REMATCH[2]}"
    echo "https://github.com/$username/$artifact_id.git"
    return 0
  fi
  
  # Pattern 2: Jakarta EE (jakarta.*) -> Try jakartaee first, then eclipse-ee4j
  if [[ "$group_id" =~ ^jakarta\.([a-zA-Z0-9_-]+) ]]; then
    local subproject="${BASH_REMATCH[1]}"
    # Special mappings for known Jakarta projects
    case "$subproject" in
      activation)
        echo "https://github.com/jakartaee/jaf-api.git"
        return 0
        ;;
      xml.bind)
        echo "https://github.com/jakartaee/jaxb-api.git"
        return 0
        ;;
      *)
        # Try jakartaee organization with artifact name
        echo "https://github.com/jakartaee/$artifact_id.git"
        return 0
        ;;
    esac
  fi
  
  # Pattern 3: Eclipse projects (org.eclipse.*)
  if [[ "$group_id" =~ ^org\.eclipse\. ]]; then
    echo "https://github.com/eclipse/$artifact_id.git"
    return 0
  fi
  
  # Pattern 4: Apache projects (org.apache.*)
  if [[ "$group_id" =~ ^org\.apache\.([a-zA-Z0-9_-]+) ]]; then
    local project="${BASH_REMATCH[1]}"
    # Try project-specific repo first
    echo "https://github.com/apache/$project-$artifact_id.git"
    return 0
  fi
  
  # Pattern 5: Elastic/Elasticsearch (co.elastic.*)
  if [[ "$group_id" =~ ^co\.elastic\. ]]; then
    echo "https://github.com/elastic/$artifact_id.git"
    return 0
  fi
  
  # Pattern 6: AWS SDK (com.amazonaws.* or software.amazon.*)
  if [[ "$group_id" =~ ^(com\.amazonaws|software\.amazon)\. ]]; then
    echo "https://github.com/aws/$artifact_id.git"
    return 0
  fi
  
  # Pattern 7: com.company (single level) -> try github.com/company/artifactId
  # Examples: com.box -> github.com/box/box-java-sdk
  if [[ "$group_id" =~ ^com\.([a-zA-Z0-9_-]+)$ ]]; then
    local company="${BASH_REMATCH[1]}"
    echo "https://github.com/$company/$artifact_id.git"
    return 0
  fi
  
  # Pattern 8: org.projectname -> try github.com/projectname/artifactId
  if [[ "$group_id" =~ ^org\.([a-zA-Z0-9_-]+)$ ]]; then
    local org="${BASH_REMATCH[1]}"
    echo "https://github.com/$org/$artifact_id.git"
    return 0
  fi
  
  # Pattern 9: com.company.project -> try github.com/company/project
  if [[ "$group_id" =~ ^com\.([a-zA-Z0-9_-]+)\.([a-zA-Z0-9_-]+)$ ]]; then
    local company="${BASH_REMATCH[1]}"
    local project="${BASH_REMATCH[2]}"
    echo "https://github.com/$company/$project.git"
    return 0
  fi
  
  return 1
}

# Try common naming patterns for popular repositories
try_common_naming_patterns() {
  local group_id="$1"
  local artifact_id="$2"
  
  # Pattern 1: artifact-id matches repo name exactly
  echo "https://github.com/${group_id##*.}/$artifact_id.git"
  return 0
}

# Infer Git tag from version
# Common patterns: v1.0.0, 1.0.0, artifactId-1.0.0, rel/1.0.0
infer_tag_from_version() {
  local version="$1"
  local artifact_id="$2"
  
  # Try multiple tag patterns (most common first)
  local patterns=(
    "v$version"
    "$version"
    "$artifact_id-$version"
    "release-$version"
    "rel/$version"
  )
  
  # Return the first pattern (most common)
  echo "${patterns[0]}"
}

# Verify if SCM URL and revision exist (lightweight check)
verify_scm_exists() {
  local scm_url="$1"
  local scm_revision="$2"
  
  # Convert git URL to HTTPS for checking
  local https_url="$scm_url"
  https_url="${https_url%.git}"
  https_url="${https_url/git@github.com:/https://github.com/}"
  https_url="${https_url/git:\/\/github.com\//https://github.com/}"
  
  # Quick check: try to access the repository (just check if repo exists)
  # Accept any successful HTTP response (2xx or 3xx)
  local http_code
  http_code=$(curl -fsSL -I --max-time 5 -w "%{http_code}" -o /dev/null "$https_url" 2>/dev/null || echo "000")
  
  if [[ "$http_code" =~ ^[23] ]]; then
    # Repository exists, now try to verify tag/revision
    # Try multiple tag patterns
    local tag_patterns=("$scm_revision" "v$scm_revision" "${scm_revision#v}")
    for tag in "${tag_patterns[@]}"; do
      local tag_url="$https_url/releases/tag/$tag"
      local tag_code
      tag_code=$(curl -fsSL -I --max-time 3 -w "%{http_code}" -o /dev/null "$tag_url" 2>/dev/null || echo "000")
      if [[ "$tag_code" =~ ^[23] ]]; then
        return 0
      fi
    done
    # If no tag found but repo exists, still return success (repo is valid)
    return 0
  fi
  
  return 1
}

# Search GitHub API for repository
search_github_api() {
  local group_id="$1"
  local artifact_id="$2"
  
  # Use GitHub API to search for repository
  # Format: https://api.github.com/search/repositories?q=artifact_id+in:name
  local search_query="${artifact_id// /+}"
  local api_url="https://api.github.com/search/repositories?q=$search_query+in:name&sort=stars&order=desc"
  
  # Make API request with timeout
  local response
  if response=$(timeout 5 curl -fsSL -H "Accept: application/vnd.github.v3+json" "$api_url" 2>/dev/null); then
    # Parse JSON response to get first result
    local repo_url
    repo_url=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('items') and len(data['items']) > 0:
        print(data['items'][0]['clone_url'])
except:
    pass
" 2>/dev/null)
    
    if [[ -n "$repo_url" ]]; then
      echo "$repo_url"
      return 0
    fi
  fi
  
  return 1
}

# Analyze Maven metadata for SCM hints
analyze_maven_metadata() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"
  
  # Try to fetch maven-metadata.xml
  local group_path="${group_id//./\/}"
  local metadata_url="https://repo1.maven.org/maven2/$group_path/$artifact_id/maven-metadata.xml"
  
  local metadata
  if metadata=$(timeout 5 curl -fsSL "$metadata_url" 2>/dev/null); then
    # Look for SCM URL in metadata (some artifacts include it)
    local scm_url
    scm_url=$(echo "$metadata" | grep -oP '<scm>.*?<url>\K[^<]+' | head -1)
    
    if [[ -n "$scm_url" ]]; then
      # Clean up SCM URL
      scm_url="${scm_url#scm:git:}"
      scm_url="${scm_url#scm:}"
      echo "$scm_url"
      return 0
    fi
  fi
  
  return 1
}

# Generate AI-powered suggestions for manual resolution
generate_scm_suggestions() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"
  
  cat <<EOF
[AI] SCM Resolution Suggestions for $group_id:$artifact_id:$version

Based on analysis, here are potential SCM locations to investigate:

1. GitHub Organization Patterns:
   - https://github.com/${group_id##*.}/$artifact_id
   - https://github.com/${group_id#*.}/$artifact_id
   
2. Common Repository Patterns:
   - https://github.com/$artifact_id/$artifact_id
   - https://gitlab.com/${group_id##*.}/$artifact_id
   
3. Maven Central Links:
   - Check: https://repo1.maven.org/maven2/${group_id//./\/}/$artifact_id/$version/$artifact_id-$version.pom
   - Look for <scm> section in POM
   
4. Search Engines:
   - Google: "$artifact_id maven github"
   - GitHub: Search for "$artifact_id" in repositories
   
5. Alternative Sources:
   - Check if artifact is a fork or mirror
   - Look for parent project SCM
   - Check organization website: ${group_id%%.*}

Recommended Actions:
- Verify the artifact is actually open source
- Check if it's a proprietary/commercial library
- Look for alternative artifacts with similar functionality
- Contact the artifact maintainers for SCM information
EOF
}

# Main AI-enhanced resolve function (wrapper)
ai_enhanced_resolve_scm() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"
  
  # First try traditional methods (use original if available, otherwise current)
  local resolve_func="resolve_scm"
  if declare -f resolve_scm_original >/dev/null 2>&1; then
    resolve_func="resolve_scm_original"
  fi
  
  if $resolve_func "$group_id" "$artifact_id" "$version" 2>/dev/null; then
    return 0
  fi
  
  # If traditional methods fail, use AI
  echo "[AI] Traditional SCM resolution failed, trying AI methods..." >&2
  if ai_resolve_scm "$group_id" "$artifact_id" "$version"; then
    return 0
  fi
  
  # If AI also fails, generate suggestions
  echo "" >&2
  generate_scm_suggestions "$group_id" "$artifact_id" "$version" >&2
  return 1
}

# Export functions for use in other scripts
export -f ai_resolve_scm
export -f ai_enhanced_resolve_scm
export -f generate_scm_suggestions
