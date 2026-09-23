#!/usr/bin/env bash
# Cache Manager Library
# Provides persistent caching for Maven dependency trees, SCM data, and productization status
# Part of Phase 1: Performance Optimization

set -euo pipefail

# Cache configuration
CACHE_BASE_DIR="${CACHE_DIR:-$HOME/.bob/cache}"
CACHE_VERSION="1.0"

# Cache subdirectories
MAVEN_TREE_CACHE="$CACHE_BASE_DIR/maven-trees"
PRODUCTIZATION_CACHE="$CACHE_BASE_DIR/productization"
SCM_CACHE="$CACHE_BASE_DIR/scm"
BOM_EXPANSION_CACHE="$CACHE_BASE_DIR/bom-expansion"

# Default TTLs (in seconds)
MAVEN_TREE_TTL="${MAVEN_TREE_TTL:-86400}"      # 24 hours
PRODUCTIZATION_TTL="${PRODUCTIZATION_TTL:-21600}" # 6 hours
SCM_TTL="${SCM_TTL:-604800}"                    # 7 days
BOM_EXPANSION_TTL="${BOM_EXPANSION_TTL:-86400}" # 24 hours

# Initialize cache directories
init_cache() {
  mkdir -p "$MAVEN_TREE_CACHE"
  mkdir -p "$PRODUCTIZATION_CACHE"
  mkdir -p "$SCM_CACHE"
  mkdir -p "$BOM_EXPANSION_CACHE"
  
  # Create cache metadata
  local metadata_file="$CACHE_BASE_DIR/metadata.json"
  if [[ ! -f "$metadata_file" ]]; then
    cat > "$metadata_file" <<EOF
{
  "version": "$CACHE_VERSION",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "last_cleanup": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
  fi
}

# Generate cache key from input
# Args: input_string
# Returns: SHA256 hash
generate_cache_key() {
  local input="$1"
  echo -n "$input" | shasum -a 256 | awk '{print $1}'
}

# Check if cache entry is valid (not expired)
# Args: cache_file ttl
# Returns: 0 if valid, 1 if expired or missing
is_cache_valid() {
  local cache_file="$1"
  local ttl="$2"
  
  [[ ! -f "$cache_file" ]] && return 1
  
  local file_time
  file_time=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo "0")
  local current_time
  current_time=$(date +%s)
  local age=$((current_time - file_time))
  
  [[ $age -lt $ttl ]]
}

# Get cached Maven dependency tree
# Args: input_type input_value output_file
# Returns: 0 if cache hit, 1 if cache miss
get_cached_maven_tree() {
  local input_type="$1"
  local input_value="$2"
  local output_file="$3"
  
  init_cache
  
  local cache_key
  cache_key=$(generate_cache_key "${input_type}:${input_value}")
  local cache_file="$MAVEN_TREE_CACHE/${cache_key}.txt"
  
  if is_cache_valid "$cache_file" "$MAVEN_TREE_TTL"; then
    cp "$cache_file" "$output_file"
    return 0
  fi
  
  return 1
}

# Cache Maven dependency tree
# Args: input_type input_value tree_file
cache_maven_tree() {
  local input_type="$1"
  local input_value="$2"
  local tree_file="$3"
  
  init_cache
  
  local cache_key
  cache_key=$(generate_cache_key "${input_type}:${input_value}")
  local cache_file="$MAVEN_TREE_CACHE/${cache_key}.txt"
  
  cp "$tree_file" "$cache_file"
  
  # Store metadata
  cat > "${cache_file}.meta" <<EOF
{
  "input_type": "$input_type",
  "input_value": "$input_value",
  "cached_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "ttl": $MAVEN_TREE_TTL
}
EOF
}

# Get cached productization status
# Args: gav redhat_suffix
# Returns: 0 if cache hit (prints status), 1 if cache miss
get_cached_productization_status() {
  local gav="$1"
  local redhat_suffix="$2"
  
  init_cache
  
  local cache_key
  cache_key=$(generate_cache_key "${gav}:${redhat_suffix}")
  local cache_file="$PRODUCTIZATION_CACHE/${cache_key}.json"
  
  if is_cache_valid "$cache_file" "$PRODUCTIZATION_TTL"; then
    cat "$cache_file"
    return 0
  fi
  
  return 1
}

# Cache productization status
# Args: gav redhat_suffix productized productized_version repository
cache_productization_status() {
  local gav="$1"
  local redhat_suffix="$2"
  local productized="$3"
  local productized_version="${4:-}"
  local repository="${5:-}"
  
  init_cache
  
  local cache_key
  cache_key=$(generate_cache_key "${gav}:${redhat_suffix}")
  local cache_file="$PRODUCTIZATION_CACHE/${cache_key}.json"
  
  cat > "$cache_file" <<EOF
{
  "gav": "$gav",
  "redhat_suffix": "$redhat_suffix",
  "productized": $productized,
  "productized_version": "$productized_version",
  "repository": "$repository",
  "checked_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "ttl": $PRODUCTIZATION_TTL
}
EOF
}

# Get cached SCM data
# Args: gav
# Returns: 0 if cache hit (prints SCM data), 1 if cache miss
get_cached_scm() {
  local gav="$1"
  
  init_cache
  
  local cache_key
  cache_key=$(generate_cache_key "$gav")
  local cache_file="$SCM_CACHE/${cache_key}.txt"
  
  if is_cache_valid "$cache_file" "$SCM_TTL"; then
    cat "$cache_file"
    return 0
  fi
  
  return 1
}

# Cache SCM data
# Args: gav scm_url scm_revision scm_source
cache_scm() {
  local gav="$1"
  local scm_url="$2"
  local scm_revision="$3"
  local scm_source="${4:-unknown}"
  
  init_cache
  
  local cache_key
  cache_key=$(generate_cache_key "$gav")
  local cache_file="$SCM_CACHE/${cache_key}.txt"
  
  cat > "$cache_file" <<EOF
SCM_URL=$scm_url
SCM_REVISION=$scm_revision
SCM_SOURCE=$scm_source
EOF
  
  # Store metadata
  cat > "${cache_file}.meta" <<EOF
{
  "gav": "$gav",
  "cached_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "ttl": $SCM_TTL
}
EOF
}

# Get cached BOM expansion
# Args: bom_gav
# Returns: 0 if cache hit (prints file path), 1 if cache miss
get_cached_bom_expansion() {
  local bom_gav="$1"
  
  init_cache
  
  local cache_key
  cache_key=$(generate_cache_key "$bom_gav")
  local cache_file="$BOM_EXPANSION_CACHE/${cache_key}.txt"
  
  if is_cache_valid "$cache_file" "$BOM_EXPANSION_TTL"; then
    echo "$cache_file"
    return 0
  fi
  
  return 1
}

# Cache BOM expansion
# Args: bom_gav expansion_file
cache_bom_expansion() {
  local bom_gav="$1"
  local expansion_file="$2"
  
  init_cache
  
  local cache_key
  cache_key=$(generate_cache_key "$bom_gav")
  local cache_file="$BOM_EXPANSION_CACHE/${cache_key}.txt"
  
  cp "$expansion_file" "$cache_file"
  
  # Store metadata
  cat > "${cache_file}.meta" <<EOF
{
  "bom_gav": "$bom_gav",
  "cached_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "ttl": $BOM_EXPANSION_TTL
}
EOF
}

# Clear all caches
clear_all_caches() {
  echo "[INFO] Clearing all caches..." >&2
  rm -rf "$MAVEN_TREE_CACHE"/*
  rm -rf "$PRODUCTIZATION_CACHE"/*
  rm -rf "$SCM_CACHE"/*
  rm -rf "$BOM_EXPANSION_CACHE"/*
  echo "[INFO] All caches cleared" >&2
}

# Clear specific cache type
# Args: cache_type (maven|productization|scm|bom)
clear_cache_type() {
  local cache_type="$1"
  
  case "$cache_type" in
    maven)
      echo "[INFO] Clearing Maven tree cache..." >&2
      rm -rf "$MAVEN_TREE_CACHE"/*
      ;;
    productization)
      echo "[INFO] Clearing productization cache..." >&2
      rm -rf "$PRODUCTIZATION_CACHE"/*
      ;;
    scm)
      echo "[INFO] Clearing SCM cache..." >&2
      rm -rf "$SCM_CACHE"/*
      ;;
    bom)
      echo "[INFO] Clearing BOM expansion cache..." >&2
      rm -rf "$BOM_EXPANSION_CACHE"/*
      ;;
    *)
      echo "[ERROR] Unknown cache type: $cache_type" >&2
      return 1
      ;;
  esac
  
  echo "[INFO] Cache cleared: $cache_type" >&2
}

# Clean expired cache entries
cleanup_expired_caches() {
  echo "[INFO] Cleaning up expired cache entries..." >&2
  
  local total_removed=0
  
  # Cleanup Maven tree cache
  for cache_file in "$MAVEN_TREE_CACHE"/*.txt; do
    [[ ! -f "$cache_file" ]] && continue
    if ! is_cache_valid "$cache_file" "$MAVEN_TREE_TTL"; then
      rm -f "$cache_file" "${cache_file}.meta"
      total_removed=$((total_removed + 1))
    fi
  done
  
  # Cleanup productization cache
  for cache_file in "$PRODUCTIZATION_CACHE"/*.json; do
    [[ ! -f "$cache_file" ]] && continue
    if ! is_cache_valid "$cache_file" "$PRODUCTIZATION_TTL"; then
      rm -f "$cache_file"
      total_removed=$((total_removed + 1))
    fi
  done
  
  # Cleanup SCM cache
  for cache_file in "$SCM_CACHE"/*.txt; do
    [[ ! -f "$cache_file" ]] && continue
    if ! is_cache_valid "$cache_file" "$SCM_TTL"; then
      rm -f "$cache_file" "${cache_file}.meta"
      total_removed=$((total_removed + 1))
    fi
  done
  
  # Cleanup BOM expansion cache
  for cache_file in "$BOM_EXPANSION_CACHE"/*.txt; do
    [[ ! -f "$cache_file" ]] && continue
    if ! is_cache_valid "$cache_file" "$BOM_EXPANSION_TTL"; then
      rm -f "$cache_file" "${cache_file}.meta"
      total_removed=$((total_removed + 1))
    fi
  done
  
  echo "[INFO] Removed $total_removed expired cache entries" >&2
  
  # Update metadata
  local metadata_file="$CACHE_BASE_DIR/metadata.json"
  if [[ -f "$metadata_file" ]]; then
    local version created_at
    version=$(jq -r '.version' "$metadata_file" 2>/dev/null || echo "$CACHE_VERSION")
    created_at=$(jq -r '.created_at' "$metadata_file" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    cat > "$metadata_file" <<EOF
{
  "version": "$version",
  "created_at": "$created_at",
  "last_cleanup": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
  fi
}

# Get cache statistics
get_cache_stats() {
  init_cache
  
  local maven_count productization_count scm_count bom_count
  maven_count=$(find "$MAVEN_TREE_CACHE" -name "*.txt" 2>/dev/null | wc -l | tr -d ' ')
  productization_count=$(find "$PRODUCTIZATION_CACHE" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
  scm_count=$(find "$SCM_CACHE" -name "*.txt" 2>/dev/null | wc -l | tr -d ' ')
  bom_count=$(find "$BOM_EXPANSION_CACHE" -name "*.txt" 2>/dev/null | wc -l | tr -d ' ')
  
  local maven_size productization_size scm_size bom_size total_size
  maven_size=$(du -sh "$MAVEN_TREE_CACHE" 2>/dev/null | awk '{print $1}' || echo "0")
  productization_size=$(du -sh "$PRODUCTIZATION_CACHE" 2>/dev/null | awk '{print $1}' || echo "0")
  scm_size=$(du -sh "$SCM_CACHE" 2>/dev/null | awk '{print $1}' || echo "0")
  bom_size=$(du -sh "$BOM_EXPANSION_CACHE" 2>/dev/null | awk '{print $1}' || echo "0")
  total_size=$(du -sh "$CACHE_BASE_DIR" 2>/dev/null | awk '{print $1}' || echo "0")
  
  cat <<EOF
Cache Statistics
================
Location: $CACHE_BASE_DIR

Maven Tree Cache:
  Entries: $maven_count
  Size: $maven_size
  TTL: ${MAVEN_TREE_TTL}s ($(($MAVEN_TREE_TTL / 3600))h)

Productization Cache:
  Entries: $productization_count
  Size: $productization_size
  TTL: ${PRODUCTIZATION_TTL}s ($(($PRODUCTIZATION_TTL / 3600))h)

SCM Cache:
  Entries: $scm_count
  Size: $scm_size
  TTL: ${SCM_TTL}s ($(($SCM_TTL / 86400))d)

BOM Expansion Cache:
  Entries: $bom_count
  Size: $bom_size
  TTL: ${BOM_EXPANSION_TTL}s ($(($BOM_EXPANSION_TTL / 3600))h)

Total Cache Size: $total_size
EOF
}

# Export functions for use in other scripts
export -f init_cache
export -f generate_cache_key
export -f is_cache_valid
export -f get_cached_maven_tree
export -f cache_maven_tree
export -f get_cached_productization_status
export -f cache_productization_status
export -f get_cached_scm
export -f cache_scm
export -f get_cached_bom_expansion
export -f cache_bom_expansion
export -f clear_all_caches
export -f clear_cache_type
export -f cleanup_expired_caches
export -f get_cache_stats