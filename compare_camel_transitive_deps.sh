#!/usr/bin/env bash
# Compare third-party transitive dependencies between two Camel versions
# This script analyzes actual transitive dependencies, not just BOM contents

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Default values
VERSION1=""
VERSION2=""
SUFFIX1=""
SUFFIX2=""
ARTIFACTS_TO_ANALYZE="org.apache.camel:camel-core"
OUTPUT_DIR="./camel-comparison-output"
CHECK_PRODUCTIZATION=false

show_usage() {
  cat <<'USAGE'
Compare Third-Party Transitive Dependencies Between Camel Versions

Usage:
  ./compare_camel_transitive_deps.sh [OPTIONS]

Required:
  --version1 VERSION          First Camel version (e.g., 4.18.1)
  --version2 VERSION          Second Camel version (e.g., 4.18.3)

Optional:
  --suffix1 SUFFIX            RedHat suffix for version 1 (e.g., redhat-00042)
  --suffix2 SUFFIX            RedHat suffix for version 2 (e.g., redhat-00001)
  --artifacts LIST            Comma-separated list of artifacts to analyze
                              (default: org.apache.camel:camel-core)
  --check-productization      Check if dependencies are productized
  -o, --output DIR            Output directory (default: ./camel-comparison-output)
  -h, --help                  Show this help

Examples:
  # Compare camel-core between versions
  ./compare_camel_transitive_deps.sh --version1 4.18.1 --version2 4.18.3

  # Compare with RedHat suffixes and productization check
  ./compare_camel_transitive_deps.sh \
    --version1 4.18.1 --suffix1 redhat-00042 \
    --version2 4.18.3 --suffix2 redhat-00001 \
    --check-productization

  # Compare multiple artifacts
  ./compare_camel_transitive_deps.sh \
    --version1 4.18.1 --version2 4.18.3 \
    --artifacts "org.apache.camel:camel-core,org.apache.camel:camel-http"

USAGE
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version1) VERSION1="$2"; shift 2 ;;
    --version2) VERSION2="$2"; shift 2 ;;
    --suffix1) SUFFIX1="$2"; shift 2 ;;
    --suffix2) SUFFIX2="$2"; shift 2 ;;
    --artifacts) ARTIFACTS_TO_ANALYZE="$2"; shift 2 ;;
    --check-productization) CHECK_PRODUCTIZATION=true; shift ;;
    -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help) show_usage; exit 0 ;;
    *) log_error "Unknown option: $1"; show_usage; exit 1 ;;
  esac
done

# Validate required arguments
if [[ -z "$VERSION1" || -z "$VERSION2" ]]; then
  log_error "Both --version1 and --version2 are required"
  show_usage
  exit 1
fi

# Build full versions with suffixes
FULL_VERSION1="$VERSION1"
[[ -n "$SUFFIX1" ]] && FULL_VERSION1="${VERSION1}.${SUFFIX1}"

FULL_VERSION2="$VERSION2"
[[ -n "$SUFFIX2" ]] && FULL_VERSION2="${VERSION2}.${SUFFIX2}"

log_info "Comparing Camel versions:"
log_info "  Version 1: $FULL_VERSION1"
log_info "  Version 2: $FULL_VERSION2"
log_info "  Artifacts: $ARTIFACTS_TO_ANALYZE"

# Create output directories
mkdir -p "$OUTPUT_DIR/v1" "$OUTPUT_DIR/v2"

# Analyze each version
for version_dir in "v1" "v2"; do
  if [[ "$version_dir" == "v1" ]]; then
    VERSION="$FULL_VERSION1"
    SUFFIX="$SUFFIX1"
  else
    VERSION="$FULL_VERSION2"
    SUFFIX="$SUFFIX2"
  fi
  
  log_info "Analyzing version $VERSION..."
  
  # Build artifact list for generate_build_configs.sh
  # Use community version for analysis (without .redhat suffix)
  COMMUNITY_VERSION=""
  if [[ "$version_dir" == "v1" ]]; then
    COMMUNITY_VERSION="$VERSION1"
  else
    COMMUNITY_VERSION="$VERSION2"
  fi
  
  ARTIFACT_ARGS=""
  IFS=',' read -ra ARTIFACTS <<< "$ARTIFACTS_TO_ANALYZE"
  for artifact in "${ARTIFACTS[@]}"; do
    ARTIFACT_ARGS="$artifact:$COMMUNITY_VERSION"
    break  # Use first artifact as primary, others would need multiple runs
  done
  
  # Run analysis using community version for dependency resolution
  # But check productization against the full productized version
  CMD="./generate_build_configs.sh \
    -a \"$ARTIFACT_ARGS\" \
    -b \"org.apache.camel:camel-bom:$COMMUNITY_VERSION\" \
    -e org.apache.camel,org.apache.camel.maven \
    -o \"$OUTPUT_DIR/$version_dir\""
  
  # Enable PNC integration to check Indy for productized versions
  if [[ "$CHECK_PRODUCTIZATION" == "true" && -n "$SUFFIX" ]]; then
    CMD="$CMD --check-productization --redhat-suffix \"$SUFFIX\""
  else
    CMD="$CMD --no-pnc-integration"
  fi
  
  log_info "Running: $CMD"
  eval "$CMD" > "$OUTPUT_DIR/${version_dir}-analysis.log" 2>&1 || {
    log_error "Failed to analyze version $VERSION"
    log_error "Check log: $OUTPUT_DIR/${version_dir}-analysis.log"
    exit 1
  }
done

# Generate comparison report
log_info "Generating comparison report..."

python3 - "$OUTPUT_DIR" "$FULL_VERSION1" "$FULL_VERSION2" "$CHECK_PRODUCTIZATION" <<'PY'
import sys
from pathlib import Path
from collections import defaultdict

output_dir = Path(sys.argv[1])
version1 = sys.argv[2]
version2 = sys.argv[3]
check_prod = sys.argv[4] == "True"

# Read third-party dependencies
v1_deps = {}
v2_deps = {}

v1_file = output_dir / "v1" / "third-party-dependencies.txt"
v2_file = output_dir / "v2" / "third-party-dependencies.txt"

if not v1_file.exists() or not v2_file.exists():
    print(f"[ERROR] Dependency files not found", file=sys.stderr)
    sys.exit(1)

for line in v1_file.read_text().splitlines():
    if not line.strip():
        continue
    parts = line.strip().split(':')
    if len(parts) >= 3:
        key = f"{parts[0]}:{parts[1]}"
        v1_deps[key] = parts[2]

for line in v2_file.read_text().splitlines():
    if not line.strip():
        continue
    parts = line.strip().split(':')
    if len(parts) >= 3:
        key = f"{parts[0]}:{parts[1]}"
        v2_deps[key] = parts[2]

# Read productization status if available
v1_prod = set()
v2_prod = set()

if check_prod:
    v1_prod_file = output_dir / "v1" / "build-from-source.txt"
    v2_prod_file = output_dir / "v2" / "build-from-source.txt"
    
    if v1_prod_file.exists():
        for line in v1_prod_file.read_text().splitlines():
            if line.strip():
                parts = line.strip().split(':')
                if len(parts) >= 2:
                    v1_prod.add(f"{parts[0]}:{parts[1]}")
    
    if v2_prod_file.exists():
        for line in v2_prod_file.read_text().splitlines():
            if line.strip():
                parts = line.strip().split(':')
                if len(parts) >= 2:
                    v2_prod.add(f"{parts[0]}:{parts[1]}")

# Generate report
report = []
report.append("=" * 80)
report.append(f"Camel Third-Party Dependency Comparison")
report.append(f"Version 1: {version1}")
report.append(f"Version 2: {version2}")
report.append("=" * 80)
report.append("")

# Summary
all_deps = set(v1_deps.keys()) | set(v2_deps.keys())
only_v1 = set(v1_deps.keys()) - set(v2_deps.keys())
only_v2 = set(v2_deps.keys()) - set(v1_deps.keys())
common = set(v1_deps.keys()) & set(v2_deps.keys())
version_changed = {k for k in common if v1_deps[k] != v2_deps[k]}

report.append(f"Summary:")
report.append(f"  Total unique dependencies: {len(all_deps)}")
report.append(f"  In version 1 only: {len(only_v1)}")
report.append(f"  In version 2 only: {len(only_v2)}")
report.append(f"  Common dependencies: {len(common)}")
report.append(f"  Version changed: {len(version_changed)}")
report.append("")

if check_prod:
    newly_prod = {k for k in common if k not in v1_prod and k in v2_prod}
    report.append(f"  Newly productized in v2: {len(newly_prod)}")
    report.append("")

# Removed dependencies
if only_v1:
    report.append(f"Removed in {version2} ({len(only_v1)}):")
    report.append("-" * 80)
    for dep in sorted(only_v1):
        report.append(f"  - {dep}:{v1_deps[dep]}")
    report.append("")

# Added dependencies
if only_v2:
    report.append(f"Added in {version2} ({len(only_v2)}):")
    report.append("-" * 80)
    for dep in sorted(only_v2):
        prod_status = " [PRODUCTIZED]" if check_prod and dep in v2_prod else ""
        report.append(f"  + {dep}:{v2_deps[dep]}{prod_status}")
    report.append("")

# Version changes
if version_changed:
    report.append(f"Version Changes ({len(version_changed)}):")
    report.append("-" * 80)
    for dep in sorted(version_changed):
        prod_status = ""
        if check_prod:
            if dep in v2_prod and dep not in v1_prod:
                prod_status = " [NEWLY PRODUCTIZED]"
            elif dep in v2_prod:
                prod_status = " [PRODUCTIZED]"
        report.append(f"  {dep}")
        report.append(f"    {version1}: {v1_deps[dep]}")
        report.append(f"    {version2}: {v2_deps[dep]}{prod_status}")
        report.append("")

# Unchanged dependencies
unchanged = common - version_changed
if unchanged:
    report.append(f"Unchanged Dependencies ({len(unchanged)}):")
    report.append("-" * 80)
    for dep in sorted(unchanged):
        prod_status = " [PRODUCTIZED]" if check_prod and dep in v2_prod else ""
        report.append(f"  = {dep}:{v1_deps[dep]}{prod_status}")

# Write report
report_text = '\n'.join(report)
report_file = output_dir / "comparison-report.txt"
report_file.write_text(report_text)

print(report_text)
print(f"\n[SUCCESS] Report written to: {report_file}")
PY

log_success "Comparison complete! Results in: $OUTPUT_DIR/comparison-report.txt"
