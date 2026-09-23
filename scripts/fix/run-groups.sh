#!/usr/bin/env bash
# run-groups.sh — run generate_build_configs.sh for each groupId in batch-cq339-remaining.txt
# Output: output-groups/<sanitized-groupId>/build-config.yaml  (one per group)
# Usage: ./run-groups.sh [--dry-run] [--filter <groupId>] [--skip-existing] [--force]
#        BATCH_FILE=other.txt OUT_ROOT=other-dir ./run-groups.sh
set -euo pipefail

BATCH_FILE="${BATCH_FILE:-batch-cq339-remaining.txt}"
OUT_ROOT="${OUT_ROOT:-output-groups}"
DRY_RUN=false
FILTER=""
SKIP_EXISTING=false
FORCE_FLAG="--force-full"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)       DRY_RUN=true ;;
    --filter)        FILTER="$2"; shift ;;
    --skip-existing) SKIP_EXISTING=true ;;
    --force)         FORCE_FLAG="--force-full" ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
  shift
done

mkdir -p "$OUT_ROOT"

# Build ordered group list (largest first)
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "${line%%:*}"
done < "$BATCH_FILE" | sort | uniq -c | sort -rn | awk '{print $2}' > /tmp/run-groups-order.txt

total=$(wc -l < /tmp/run-groups-order.txt | tr -d ' ')
idx=0
pass=0
fail=0
skip=0

while IFS= read -r group; do
  idx=$((idx + 1))

  # Apply --filter if set
  if [[ -n "$FILTER" && "$group" != *"$FILTER"* ]]; then
    continue
  fi

  # Sanitize group for directory name (dots → dashes)
  safe="${group//./-}"
  out_dir="$OUT_ROOT/$safe"

  # Skip if already done (build-config.yaml exists)
  if [[ "$SKIP_EXISTING" == "true" && -f "$out_dir/build-config.yaml" ]]; then
    echo "[$idx/$total] SKIP (exists) $group"
    skip=$((skip + 1))
    continue
  fi

  # Write per-group artifact file
  tmp_file="/tmp/run-groups-batch-$$.txt"
  grep "^${group}:" "$BATCH_FILE" > "$tmp_file"
  art_count=$(wc -l < "$tmp_file" | tr -d ' ')

  echo "[$idx/$total] $group ($art_count arts) → $out_dir/build-config.yaml"

  if [[ "$DRY_RUN" == "true" ]]; then
    sed 's/^/    /' "$tmp_file"
    rm -f "$tmp_file"
    continue
  fi

  set +e
  SKIP_PNC_QUERIES=false ENABLE_AI_ASSISTANT=true \
    ./generate_build_configs.sh \
      -c test-config.yaml \
      -r "$tmp_file" \
      --direct-artifacts \
      $FORCE_FLAG \
      -o "$out_dir" \
      2>&1 | grep -E "SUCCESS|ERROR|Unresolved|Generated:" | tail -5
  rc=$?
  set -e

  rm -f "$tmp_file"

  if [[ $rc -eq 0 && -f "$out_dir/combined-build-configs.yaml" ]]; then
    # Rename to build-config.yaml (canonical BACON name)
    mv "$out_dir/combined-build-configs.yaml" "$out_dir/build-config.yaml"
    pass=$((pass + 1))
  else
    echo "  FAILED for $group (rc=$rc)"
    fail=$((fail + 1))
  fi

done < /tmp/run-groups-order.txt

echo ""
echo "=== Done: $pass passed, $fail failed, $skip skipped (total groups: $total) ==="
