#!/bin/bash

set -euo pipefail

CAMEL_VERSION="4.22.0.redhat-00002"
UPSTREAM_VERSION="4.22.0"
OUTPUT_DIR="/Users/soghosh/autobuilds/camel-4.22.0-redhat-00002-report"
INDY_URL="https://indy.corp.redhat.com/api/content/maven/hosted/pnc-builds"
TRANSITIVE_SOURCE_DIR="/Users/soghosh/autobuilds/camel-4.22.0-transitive-builds"

echo "=========================================="
echo "Camel Transitive Productization Analyzer"
echo "Version: $CAMEL_VERSION"
echo "Output: $OUTPUT_DIR"
echo "=========================================="
echo ""

mkdir -p "$OUTPUT_DIR"

log() {
    echo "$1"
}

require_file() {
    local file_path="$1"
    if [ ! -f "$file_path" ]; then
        echo "Required file not found: $file_path" >&2
        exit 1
    fi
}

find_productized_version() {
    local group_id="$1"
    local artifact_id="$2"
    local version="$3"
    local group_path="${group_id//./\/}"
    local metadata_url="${INDY_URL}/${group_path}/${artifact_id}/maven-metadata.xml"

    if [[ "$version" == *".redhat-"* ]]; then
        echo "$version"
        return 0
    fi

    local metadata
    metadata=$(curl -f -sS "$metadata_url" 2>/dev/null || true)
    if [ -z "$metadata" ]; then
        return 1
    fi

    local matched_version
    matched_version=$(printf '%s\n' "$metadata" | grep -o "<version>${version}\.redhat-[^<]*</version>" | sed -E 's#</?version>##g' | tail -1)

    if [ -n "$matched_version" ]; then
        echo "$matched_version"
        return 0
    fi

    return 1
}

prepare_inputs() {
    log "[1/5] Preparing transitive dependency inputs..."

    require_file "${TRANSITIVE_SOURCE_DIR}/root-artifacts.txt"
    require_file "${TRANSITIVE_SOURCE_DIR}/all-dependencies.txt"
    require_file "${TRANSITIVE_SOURCE_DIR}/third-party-dependencies.txt"
    require_file "${TRANSITIVE_SOURCE_DIR}/unresolved-artifacts.txt"

    cp "${TRANSITIVE_SOURCE_DIR}/root-artifacts.txt" "${OUTPUT_DIR}/root-artifacts.txt"
    cp "${TRANSITIVE_SOURCE_DIR}/all-dependencies.txt" "${OUTPUT_DIR}/all-dependencies.txt"
    cp "${TRANSITIVE_SOURCE_DIR}/third-party-dependencies.txt" "${OUTPUT_DIR}/third-party-dependencies.txt"
    cp "${TRANSITIVE_SOURCE_DIR}/unresolved-artifacts.txt" "${OUTPUT_DIR}/unresolved-artifacts.txt"

    ROOT_COUNT=$(wc -l < "${OUTPUT_DIR}/root-artifacts.txt" | tr -d ' ')
    TOTAL_TRANSITIVE_COUNT=$(grep -E '^[^[]' "${OUTPUT_DIR}/all-dependencies.txt" | grep ':jar:' | sed -E 's/^\[INFO\] //' | sort -u | wc -l | tr -d ' ')
    THIRD_PARTY_COUNT=$(wc -l < "${OUTPUT_DIR}/third-party-dependencies.txt" | tr -d ' ')
    UNRESOLVED_COUNT=$(wc -l < "${OUTPUT_DIR}/unresolved-artifacts.txt" | tr -d ' ')

    log "✓ Root artifacts: $ROOT_COUNT"
    log "✓ Unique transitive dependencies captured: $TOTAL_TRANSITIVE_COUNT"
    log "✓ Third-party root/transitive artifacts: $THIRD_PARTY_COUNT"
    log "✓ Unresolved artifacts: $UNRESOLVED_COUNT"
}

classify_dependencies() {
    log ""
    log "[2/5] Checking productization status for transitive artifacts..."

    PRODUCTIZED_FILE="${OUTPUT_DIR}/productized-deps.txt"
    UNPRODUCTIZED_FILE="${OUTPUT_DIR}/unproductized-deps.txt"
    PRODUCTIZED_DETAILS_FILE="${OUTPUT_DIR}/productized-deps-detailed.txt"
    UNPRODUCTIZED_DETAILS_FILE="${OUTPUT_DIR}/unproductized-deps-detailed.txt"

    : > "$PRODUCTIZED_FILE"
    : > "$UNPRODUCTIZED_FILE"
    : > "$PRODUCTIZED_DETAILS_FILE"
    : > "$UNPRODUCTIZED_DETAILS_FILE"

    local current=0
    while IFS= read -r dep; do
        [ -z "$dep" ] && continue
        current=$((current + 1))

        local group_id artifact_id version matched_version
        group_id=$(echo "$dep" | cut -d: -f1)
        artifact_id=$(echo "$dep" | cut -d: -f2)
        version=$(echo "$dep" | cut -d: -f3)

        matched_version=$(find_productized_version "$group_id" "$artifact_id" "$version" || true)

        if [ -n "$matched_version" ]; then
            echo "${group_id}:${artifact_id}:${matched_version}" >> "$PRODUCTIZED_FILE"
            echo "${dep} -> ${matched_version}" >> "$PRODUCTIZED_DETAILS_FILE"
        else
            echo "$dep" >> "$UNPRODUCTIZED_FILE"
            echo "${dep} -> no matching .redhat-* version found in Indy metadata" >> "$UNPRODUCTIZED_DETAILS_FILE"
        fi

        if [ $((current % 25)) -eq 0 ]; then
            log "  Checked $current/$THIRD_PARTY_COUNT dependencies..."
        fi
    done < "${OUTPUT_DIR}/third-party-dependencies.txt"

    PRODUCTIZED_COUNT=$(wc -l < "$PRODUCTIZED_FILE" | tr -d ' ')
    UNPRODUCTIZED_COUNT=$(wc -l < "$UNPRODUCTIZED_FILE" | tr -d ' ')

    log "✓ Already productized: $PRODUCTIZED_COUNT"
    log "✓ Need productization: $UNPRODUCTIZED_COUNT"
}

generate_breakdowns() {
    log ""
    log "[3/5] Generating dependency breakdowns..."

    cut -d: -f1 "${OUTPUT_DIR}/third-party-dependencies.txt" | sort | uniq -c | sort -rn > "${OUTPUT_DIR}/by-group.txt"

    {
        echo "Top dependency groups:"
        head -20 "${OUTPUT_DIR}/by-group.txt"
        echo
        echo "Unresolved artifacts:"
        cat "${OUTPUT_DIR}/unresolved-artifacts.txt"
    } > "${OUTPUT_DIR}/analysis-summary.txt"

    log "✓ Group breakdown generated"
}

generate_report() {
    log ""
    log "[4/5] Writing updated detailed report..."

    if [ "${THIRD_PARTY_COUNT}" -gt 0 ]; then
        PROD_PERCENT=$(awk "BEGIN {printf \"%.1f\", (${PRODUCTIZED_COUNT}/${THIRD_PARTY_COUNT})*100}")
        UNPROD_PERCENT=$(awk "BEGIN {printf \"%.1f\", (${UNPRODUCTIZED_COUNT}/${THIRD_PARTY_COUNT})*100}")
    else
        PROD_PERCENT="0.0"
        UNPROD_PERCENT="0.0"
    fi

    cat > "${OUTPUT_DIR}/PRODUCTIZATION_REPORT.md" <<EOF
# Camel ${CAMEL_VERSION} - Transitive Dependency Productization Analysis

**Generated**: $(date +"%Y-%m-%d %H:%M:%S")
**Analysis Scope**: Transitive dependencies of Camel component set for ${UPSTREAM_VERSION}
**Productized Camel Version Target**: ${CAMEL_VERSION}
**Indy Source**: ${INDY_URL}
**Transitive Source Directory**: ${TRANSITIVE_SOURCE_DIR}

---

## Executive Summary

| Metric | Count |
|--------|-------|
| Root Artifacts Analysed | ${ROOT_COUNT} |
| Unique Transitive Dependencies Captured | ${TOTAL_TRANSITIVE_COUNT} |
| Third-Party Dependencies Checked | ${THIRD_PARTY_COUNT} |
| Already Productized | ${PRODUCTIZED_COUNT} (${PROD_PERCENT}%) |
| Need Productization | ${UNPRODUCTIZED_COUNT} (${UNPROD_PERCENT}%) |
| Unresolved Artifacts | ${UNRESOLVED_COUNT} |

---

## Scope and Method

This report is based on **transitive dependency analysis**, not only BOM-managed entries.

1. Reused the existing Camel 4.22.0 transitive analysis outputs under \`${TRANSITIVE_SOURCE_DIR}\`.
2. Took the discovered third-party dependency set from Camel component transitive resolution.
3. Checked each dependency in Indy using \`maven-metadata.xml\`.
4. Marked a dependency as productized if any matching \`.redhat-*\` version exists for the same upstream version.
5. Marked remaining dependencies as needing productization.

---

## Top 20 Third-Party Dependency Groups

\`\`\`
$(head -20 "${OUTPUT_DIR}/by-group.txt")
\`\`\`

---

## Already Productized Dependencies

\`\`\`
$(cat "${OUTPUT_DIR}/productized-deps-detailed.txt")
\`\`\`

---

## Dependencies Needing Productization

\`\`\`
$(cat "${OUTPUT_DIR}/unproductized-deps-detailed.txt")
\`\`\`

---

## Unresolved Artifacts from Transitive Analysis

\`\`\`
$(cat "${OUTPUT_DIR}/unresolved-artifacts.txt")
\`\`\`

---

## Priority Build Waves

### Wave 1: Core Libraries
\`\`\`
$(grep -E "(slf4j|log4j|commons-|guava|jakarta|javax)" "${OUTPUT_DIR}/unproductized-deps.txt" || echo "All core libraries productized")
\`\`\`

### Wave 2: Messaging
\`\`\`
$(grep -E "(kafka|qpid|activemq|amqp|jms|pulsar|rabbitmq)" "${OUTPUT_DIR}/unproductized-deps.txt" || echo "All messaging libraries productized")
\`\`\`

### Wave 3: Data Formats
\`\`\`
$(grep -E "(jackson|jaxb|xml|json|yaml|protobuf|avro)" "${OUTPUT_DIR}/unproductized-deps.txt" || echo "All data format libraries productized")
\`\`\`

### Wave 4: Networking
\`\`\`
$(grep -E "(netty|http|okhttp|jetty|undertow)" "${OUTPUT_DIR}/unproductized-deps.txt" || echo "All networking libraries productized")
\`\`\`

### Wave 5: Framework and Integration
\`\`\`
$(grep -E "(spring|cxf|micrometer|aws|quartz)" "${OUTPUT_DIR}/unproductized-deps.txt" || echo "All framework and integration libraries productized")
\`\`\`

---

## Evidence Files

- \`root-artifacts.txt\`
- \`all-dependencies.txt\`
- \`third-party-dependencies.txt\`
- \`unresolved-artifacts.txt\`
- \`productized-deps.txt\`
- \`productized-deps-detailed.txt\`
- \`unproductized-deps.txt\`
- \`unproductized-deps-detailed.txt\`
- \`by-group.txt\`
- \`analysis-summary.txt\`

---

## Key Findings

- This corrected analysis uses the **transitive dependency set of Camel components**.
- The current reusable transitive source contains **${THIRD_PARTY_COUNT}** third-party dependencies.
- **${PRODUCTIZED_COUNT}** are already productized in Indy.
- **${UNPRODUCTIZED_COUNT}** still need productization.
- **${UNRESOLVED_COUNT}** artifacts were unresolved during the transitive collection phase and may need separate verification.

EOF

    log "✓ Updated report written: ${OUTPUT_DIR}/PRODUCTIZATION_REPORT.md"
}

print_summary() {
    log ""
    log "[5/5] Summary"
    log "=========================================="
    log "Root artifacts analysed: ${ROOT_COUNT}"
    log "Third-party dependencies checked: ${THIRD_PARTY_COUNT}"
    log "Already productized: ${PRODUCTIZED_COUNT} (${PROD_PERCENT}%)"
    log "Need productization: ${UNPRODUCTIZED_COUNT} (${UNPROD_PERCENT}%)"
    log "Unresolved artifacts: ${UNRESOLVED_COUNT}"
    log "Report: ${OUTPUT_DIR}/PRODUCTIZATION_REPORT.md"
    log "=========================================="
}

prepare_inputs
classify_dependencies
generate_breakdowns
generate_report
print_summary
