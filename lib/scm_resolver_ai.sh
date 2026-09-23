#!/usr/bin/env bash
# AI-Enhanced SCM Resolution
# Integrates AI/ML capabilities with traditional SCM resolution methods
# Part of the PNC Build Config Generator AI enhancement

set -euo pipefail

# Get lib directory and autobuilds root
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOBUILDS_ROOT="$(cd "$LIB_DIR/.." && pwd)"

# Source the original resolver
source "$LIB_DIR/scm_resolver.sh"

# AI module paths (relative to lib directory)
AI_MODULE_DIR="$LIB_DIR/ai"
SCM_LEARNER="$AI_MODULE_DIR/scm_pattern_learner.py"
AUTO_FIXER="$AI_MODULE_DIR/auto_fixer.py"
URL_VALIDATOR="$AI_MODULE_DIR/url_validator.py"

# Check if AI modules are available
AI_AVAILABLE=false
if [[ -f "$SCM_LEARNER" ]] && command -v python3 >/dev/null 2>&1; then
    AI_AVAILABLE=true
fi

# Enhanced SCM resolution with AI fallback
# Args: group_id artifact_id version
# Returns: SCM_URL=... and SCM_REVISION=... on stdout, or exits with error
resolve_scm_with_ai() {
    local group_id="$1"
    local artifact_id="$2"
    local version="$3"
    local use_ai="${4:-true}"
    
    # Try traditional methods first (fast and reliable)
    local scm_data=""
    scm_data="$(resolve_scm "$group_id" "$artifact_id" "$version" 2>/dev/null || true)"
    
    if [[ -n "$scm_data" ]]; then
        # Success with traditional methods
        local scm_url scm_revision
        scm_url="$(echo "$scm_data" | awk -F= '/^SCM_URL=/{print substr($0,9)}')"
        scm_revision="$(echo "$scm_data" | awk -F= '/^SCM_REVISION=/{print substr($0,14)}')"
        
        # Learn from success if AI is available
        if [[ "$AI_AVAILABLE" == "true" && "$use_ai" == "true" ]]; then
            learn_from_success "$group_id" "$artifact_id" "$version" "$scm_url" "$scm_revision" &
        fi
        
        echo "$scm_data"
        return 0
    fi
    
    # Traditional methods failed, try AI fallback
    if [[ "$AI_AVAILABLE" == "true" && "$use_ai" == "true" ]]; then
        # log_verbose "Traditional SCM resolution failed, trying AI prediction..."
        
        local ai_result
        ai_result="$(predict_scm_with_ai "$group_id" "$artifact_id" "$version")"
        
        if [[ -n "$ai_result" ]]; then
            echo "$ai_result"
            return 0
        fi
    fi
    
    # Both traditional and AI methods failed
    return 1
}

# Predict SCM using AI
# Args: group_id artifact_id version
# Returns: SCM_URL=... and SCM_REVISION=... on stdout, or empty if failed
predict_scm_with_ai() {
    local group_id="$1"
    local artifact_id="$2"
    local version="$3"
    
    if [[ ! -f "$SCM_LEARNER" ]]; then
        return 1
    fi
    
    # Call Python AI module
    local prediction
    prediction="$(python3 "$SCM_LEARNER" "$group_id" "$artifact_id" "$version" 2>/dev/null | grep -E '^(SCM_URL|SCM_REVISION|Confidence)=' || true)"
    
    if [[ -z "$prediction" ]]; then
        return 1
    fi
    
    # Extract confidence and SCM URL
    local confidence scm_url
    confidence="$(echo "$prediction" | grep '^Confidence=' | cut -d= -f2 || echo "0")"
    scm_url="$(echo "$prediction" | grep '^SCM_URL=' | cut -d= -f2- || echo "")"
    
    # Transform downstream URLs to upstream
    if [[ -n "$scm_url" ]] && [[ "$scm_url" == *"github.ibm.com"* || "$scm_url" == *"gitlab.cee.redhat.com"* ]]; then
        local transformed_url
        transformed_url="$(python3 "$AI_MODULE_DIR/url_transformer.py" "$scm_url" 2>/dev/null | grep '^Transformed:' | cut -d: -f2- | xargs || echo "$scm_url")"
        if [[ -n "$transformed_url" ]]; then
            prediction="$(echo "$prediction" | sed "s|SCM_URL=.*|SCM_URL=$transformed_url|")"
        fi
    fi
    
    # Only use prediction if confidence is high enough (>70%)
    if (( $(echo "$confidence >= 0.7" | bc -l 2>/dev/null || echo 0) )); then
        echo "$prediction" | grep -E '^(SCM_URL|SCM_REVISION)='
        return 0
    fi
    
    return 1
}

# Learn from successful SCM resolution
# Args: group_id artifact_id version scm_url scm_revision
learn_from_success() {
    local group_id="$1"
    local artifact_id="$2"
    local version="$3"
    local scm_url="$4"
    local scm_revision="$5"
    
    if [[ ! -f "$SCM_LEARNER" ]]; then
        return 0
    fi
    
    # Call Python AI module to learn (async, don't wait)
    (cd "$AUTOBUILDS_ROOT" && python3 - "$group_id" "$artifact_id" "$version" "$scm_url" "$scm_revision" <<'PYTHON' >/dev/null 2>&1
import sys
import os
from pathlib import Path

# Add autobuilds root to path
sys.path.insert(0, os.getcwd())

try:
    from lib.ai.scm_pattern_learner import SCMPatternLearner
    
    learner = SCMPatternLearner()
    learner.learn_from_success(
        sys.argv[1],  # group_id
        sys.argv[2],  # artifact_id
        sys.argv[3],  # version
        sys.argv[4],  # scm_url
        sys.argv[5]   # scm_revision
    )
except Exception:
    pass  # Fail silently
PYTHON
) &
}

# Validate and auto-fix build config
# Args: config_file [--dry-run]
# Returns: 0 if no issues or all fixed, 1 if issues remain
validate_and_fix_config() {
    local config_file="$1"
    local dry_run="${2:-false}"
    
    if [[ ! -f "$AUTO_FIXER" ]]; then
        log_verbose "Auto-fixer not available, skipping validation"
        return 0
    fi
    
    local args=("$config_file")
    if [[ "$dry_run" == "true" || "$dry_run" == "--dry-run" ]]; then
        args+=("--dry-run")
    fi
    
    # Run auto-fixer
    python3 "$AUTO_FIXER" "${args[@]}"
    return $?
}

# Validate URLs in parallel
# Args: url1 url2 url3 ...
# Returns: List of valid URLs (one per line)
validate_urls_parallel() {
    if [[ ! -f "$URL_VALIDATOR" ]]; then
        # Fallback to sequential validation
        for url in "$@"; do
            if curl -I -s -f -m 5 "$url" >/dev/null 2>&1; then
                echo "$url"
            fi
        done
        return 0
    fi
    
    # Use AI validator for parallel processing
    (cd "$AUTOBUILDS_ROOT" && python3 - "$@" <<'PYTHON'
import sys
import os

sys.path.insert(0, os.getcwd())

try:
    from lib.ai.url_validator import SmartURLValidator
    
    validator = SmartURLValidator()
    urls = sys.argv[1:]
    
    valid_urls = validator.get_valid_urls(urls, max_workers=10, timeout=5)
    for url in valid_urls:
        print(url)
except Exception as e:
    # Fallback: print all URLs (let caller validate)
    for url in sys.argv[1:]:
        print(url)
PYTHON
)
}

# Get AI statistics
# Returns: JSON with AI module statistics
get_ai_statistics() {
    if [[ ! -f "$SCM_LEARNER" ]]; then
        echo '{"ai_available": false}'
        return 0
    fi
    
    (cd "$AUTOBUILDS_ROOT" && python3 - <<'PYTHON'
import sys
import json
import os

sys.path.insert(0, os.getcwd())

try:
    from lib.ai.scm_pattern_learner import SCMPatternLearner
    from lib.ai.auto_fixer import AutoFixer
    from lib.ai.url_validator import SmartURLValidator
    
    learner = SCMPatternLearner()
    fixer = AutoFixer()
    validator = SmartURLValidator()
    
    stats = {
        'ai_available': True,
        'scm_learner': learner.get_statistics(),
        'auto_fixer': fixer.get_statistics(),
        'url_validator': validator.get_statistics()
    }
    
    print(json.dumps(stats, indent=2))
except Exception as e:
    print(json.dumps({'ai_available': False, 'error': str(e)}))
PYTHON
)
}

# Show AI status and statistics
show_ai_status() {
    echo "AI/ML Intelligence Status"
    echo "========================="
    echo
    
    if [[ "$AI_AVAILABLE" == "true" ]]; then
        echo "✅ AI modules available"
        echo
        
        local stats
        stats="$(get_ai_statistics)"
        
        echo "Statistics:"
        echo "$stats" | python3 -m json.tool 2>/dev/null || echo "$stats"
    else
        echo "❌ AI modules not available"
        echo
        echo "To enable AI features:"
        echo "  1. Ensure Python 3.8+ is installed"
        echo "  2. AI modules are in: $AI_MODULE_DIR"
        echo "  3. Run: python3 -m pip install --user requests"
    fi
}

# Export functions for use in other scripts
export -f resolve_scm_with_ai
export -f predict_scm_with_ai
export -f learn_from_success
export -f validate_and_fix_config
export -f validate_urls_parallel
export -f get_ai_statistics
export -f show_ai_status
