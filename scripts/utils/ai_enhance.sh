#!/usr/bin/env bash
# AI Enhancement Integration Script
# Main entry point for AI-powered features in autobuilder
# Usage: ./ai_enhance.sh [command] [options]

set -euo pipefail

# Script directory (autobuilds root)
AUTOBUILDS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$AUTOBUILDS_ROOT"

# Source AI-enhanced resolver
source "$AUTOBUILDS_ROOT/lib/scm_resolver_ai.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Show usage
show_usage() {
    cat <<'USAGE'
AI Enhancement Integration for Autobuilder

Usage:
  ./ai_enhance.sh <command> [options]

Commands:
  status                    Show AI module status and statistics
  predict <GAV>            Predict SCM URL and revision for artifact
  validate <config>        Validate and auto-fix build config
  validate-urls <urls...>  Validate multiple URLs in parallel
  learn <GAV> <url> <rev>  Manually teach AI from successful resolution
  stats                    Show detailed AI statistics
  clear-cache [hours]      Clear AI cache (optionally older than N hours)
  test                     Run AI module tests

Examples:
  # Check AI status
  ./ai_enhance.sh status

  # Predict SCM for artifact
  ./ai_enhance.sh predict org.apache.camel:camel-kafka:4.18.1

  # Validate and auto-fix config
  ./ai_enhance.sh validate output/build-configs/org_apache_camel_camel-kafka_4.18.1.yaml.json

  # Validate multiple URLs
  ./ai_enhance.sh validate-urls \
    https://github.com/apache/camel.git \
    https://github.com/apache/flink.git

  # Teach AI from successful resolution
  ./ai_enhance.sh learn \
    org.apache.camel:camel-kafka:4.18.1 \
    https://github.com/apache/camel.git \
    camel-kafka-4.18.1

  # Clear old cache entries
  ./ai_enhance.sh clear-cache 48

Options:
  -h, --help               Show this help message
  -v, --verbose            Verbose output
  --dry-run                Preview changes without applying (for validate)

USAGE
    exit 0
}

# Command: status
cmd_status() {
    show_ai_status
}

# Command: predict
cmd_predict() {
    local gav="$1"
    
    # Parse GAV
    local group_id artifact_id version
    group_id="$(echo "$gav" | cut -d: -f1)"
    artifact_id="$(echo "$gav" | cut -d: -f2)"
    version="$(echo "$gav" | cut -d: -f3)"
    
    log_info "Predicting SCM for $gav"
    echo
    
    # Try AI prediction
    local result
    result="$(resolve_scm_with_ai "$group_id" "$artifact_id" "$version" true 2>&1)"
    
    if [[ $? -eq 0 && -n "$result" ]]; then
        log_success "Prediction successful!"
        echo
        echo "$result"
    else
        log_error "Failed to predict SCM"
        exit 1
    fi
}

# Command: validate
cmd_validate() {
    local config_file="$1"
    local dry_run="${2:-false}"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Config file not found: $config_file"
        exit 1
    fi
    
    log_info "Validating: $config_file"
    echo
    
    if [[ "$dry_run" == "true" || "$dry_run" == "--dry-run" ]]; then
        validate_and_fix_config "$config_file" --dry-run
    else
        validate_and_fix_config "$config_file"
    fi
}

# Command: validate-urls
cmd_validate_urls() {
    local urls=("$@")
    
    if [[ ${#urls[@]} -eq 0 ]]; then
        log_error "No URLs provided"
        exit 1
    fi
    
    log_info "Validating ${#urls[@]} URL(s) in parallel..."
    echo
    
    local valid_urls
    valid_urls="$(validate_urls_parallel "${urls[@]}")"
    
    if [[ -n "$valid_urls" ]]; then
        log_success "Valid URLs:"
        echo "$valid_urls" | while read -r url; do
            echo "  ✅ $url"
        done
    else
        log_warn "No valid URLs found"
    fi
}

# Command: learn
cmd_learn() {
    if [[ $# -lt 3 ]]; then
        log_error "Usage: learn <GAV> <scm_url> <scm_revision>"
        exit 1
    fi
    
    local gav="$1"
    local scm_url="$2"
    local scm_revision="$3"
    
    # Parse GAV
    local group_id artifact_id version
    group_id="$(echo "$gav" | cut -d: -f1)"
    artifact_id="$(echo "$gav" | cut -d: -f2)"
    version="$(echo "$gav" | cut -d: -f3)"
    
    log_info "Teaching AI from successful resolution..."
    log_info "  Artifact: $gav"
    log_info "  SCM URL: $scm_url"
    log_info "  SCM Revision: $scm_revision"
    echo
    
    learn_from_success "$group_id" "$artifact_id" "$version" "$scm_url" "$scm_revision"
    wait  # Wait for async learning to complete
    
    log_success "Learning complete!"
}

# Command: stats
cmd_stats() {
    log_info "AI Module Statistics"
    echo
    
    local stats
    stats="$(get_ai_statistics)"
    
    echo "$stats" | python3 -m json.tool 2>/dev/null || echo "$stats"
}

# Command: clear-cache
cmd_clear_cache() {
    local hours="${1:-}"
    
    if [[ -n "$hours" ]]; then
        log_info "Clearing cache entries older than $hours hours..."
    else
        log_info "Clearing all cache entries..."
    fi
    
    # Call Python to clear cache
    (cd "$AUTOBUILDS_ROOT" && python3 - "$hours" <<'PYTHON'
import sys
import os

sys.path.insert(0, os.getcwd())

try:
    from lib.ai.scm_pattern_learner import SCMPatternLearner
    from lib.ai.url_validator import SmartURLValidator
    
    hours = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1] else None
    
    learner = SCMPatternLearner()
    validator = SmartURLValidator()
    
    # Clear caches
    if hours:
        validator.clear_cache(older_than_hours=hours)
        print(f"✅ Cleared cache entries older than {hours} hours")
    else:
        validator.clear_cache()
        print("✅ Cleared all cache entries")
    
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
PYTHON
)
    
    log_success "Cache cleared!"
}

# Command: test
cmd_test() {
    log_info "Running AI module tests..."
    echo
    
    # Test 1: SCM Pattern Learner
    log_info "Test 1: SCM Pattern Learner"
    python3 "$SCRIPT_DIR/lib/ai/scm_pattern_learner.py" \
        org.apache.camel camel-kafka 4.18.1 2>&1 | head -20
    echo
    
    # Test 2: URL Validator
    log_info "Test 2: URL Validator"
    python3 "$SCRIPT_DIR/lib/ai/url_validator.py" \
        https://github.com/apache/camel.git 2>&1 | head -10
    echo
    
    # Test 3: Auto Fixer (dry-run on sample config if exists)
    log_info "Test 3: Auto Fixer"
    local sample_config="$SCRIPT_DIR/output/build-configs"
    if [[ -d "$sample_config" ]]; then
        local first_config=$(find "$sample_config" -name "*.json" -type f | head -1)
        if [[ -n "$first_config" ]]; then
            echo "Testing with: $(basename "$first_config")"
            python3 "$SCRIPT_DIR/lib/ai/auto_fixer.py" "$first_config" --dry-run 2>&1 | head -15
        else
            echo "No config files found for testing"
        fi
    else
        echo "No output directory found, skipping auto-fixer test"
    fi
    echo
    
    log_success "Tests complete!"
}

# Main
main() {
    if [[ $# -eq 0 ]]; then
        show_usage
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        status)
            cmd_status "$@"
            ;;
        predict)
            if [[ $# -lt 1 ]]; then
                log_error "Usage: predict <GAV>"
                exit 1
            fi
            cmd_predict "$@"
            ;;
        validate)
            if [[ $# -lt 1 ]]; then
                log_error "Usage: validate <config_file> [--dry-run]"
                exit 1
            fi
            cmd_validate "$@"
            ;;
        validate-urls)
            cmd_validate_urls "$@"
            ;;
        learn)
            cmd_learn "$@"
            ;;
        stats)
            cmd_stats "$@"
            ;;
        clear-cache)
            cmd_clear_cache "$@"
            ;;
        test)
            cmd_test "$@"
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            echo
            show_usage
            ;;
    esac
}

main "$@"
