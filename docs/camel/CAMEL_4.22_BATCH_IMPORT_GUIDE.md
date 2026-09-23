# Camel 4.22 Batch Build Configs - PNC Import Guide

## Overview

All 472 unproductized Camel 4.22 dependencies have been organized into **32 batch files** for efficient PNC import.

- **Total Artifacts:** 472
- **Batch Size:** 15 artifacts per batch (last batch has 7)
- **Total Batches:** 32
- **PNC Product:** [Camel Extensions for Quarkus (ID: 163)](https://orch.pnc.engineering.redhat.com/pnc-web/products/163)
- **Product Version:** 4.22.0.redhat-00002

## Confidence Distribution

- ✅ **7 artifacts** with exact matches (≥90%) - Ready for immediate use
- ✅ **465 artifacts** with high confidence (≥60%) - Recommended for use
- ⚠️ **0 artifacts** with low confidence (<60%)
- ❌ **0 failures**

## Directory Structure

```
output-camel-4.22-batches/
├── camel-4.22-batch-001.yaml  (15 artifacts)
├── camel-4.22-batch-002.yaml  (15 artifacts)
├── camel-4.22-batch-003.yaml  (15 artifacts)
...
├── camel-4.22-batch-031.yaml  (15 artifacts)
└── camel-4.22-batch-032.yaml  (7 artifacts)
```

## Batch File Format

Each batch file contains:

1. **Header** - Batch metadata and PNC product info
2. **Batch Configuration** - Product ID, version, batch number
3. **Build Configurations** - Individual build configs (YAML format)
4. **Summary** - List of artifacts with confidence scores

### Example Structure

```yaml
# Camel 4.22 Build Configs - Batch 1 of 32
# PNC Product: https://orch.pnc.engineering.redhat.com/pnc-web/products/163
# Generated: 2026-08-20 05:40:36 UTC
# Artifacts in this batch: 15

---
# Batch Configuration
productId: 163
productVersion: "4.22.0.redhat-00002"
batchNumber: 1
totalBatches: 32

---
# Build Configurations

---
# Build config for org.apache.activemq:activemq-client:6.3.0
# Overall confidence: 68%

name: activemq-client-6.3.0
project: org.apache.activemq

scmRepository:
  url: https://github.com/activemq/activemq-client.git
scmRevision: v6.3.0
# SCM confidence: 85%, method: ai_prediction

environment:
  id: 660
  name: OpenJDK 1.8; Mvn 3.6.3

buildScript: |
  mvn deploy -DrpmDeploymentRepository="indy-mvn::default::${AProxDeployUrl}"
# Build config confidence: 50%

---
# (Next artifact...)
```

## Import Process

### Option 1: PNC Web UI Bulk Import

1. Navigate to [PNC Product 163](https://orch.pnc.engineering.redhat.com/pnc-web/products/163)
2. Go to **Build Configs** tab
3. Click **Bulk Import** or **Import from YAML**
4. Upload batch file (e.g., `camel-4.22-batch-001.yaml`)
5. Review and confirm import
6. Repeat for remaining batches

### Option 2: PNC REST API (Automated)

```bash
#!/bin/bash
# Automated batch import script

PNC_API="https://orch.pnc.engineering.redhat.com/pnc-rest/v2"
PRODUCT_ID="163"
BATCH_DIR="output-camel-4.22-batches"

for batch_file in "$BATCH_DIR"/camel-4.22-batch-*.yaml; do
    echo "Importing: $(basename "$batch_file")"
    
    curl -X POST "$PNC_API/build-configs/import" \
        -H "Content-Type: application/yaml" \
        -H "Authorization: Bearer $PNC_TOKEN" \
        --data-binary "@$batch_file"
    
    echo "Waiting 5 seconds before next batch..."
    sleep 5
done
```

### Option 3: Manual Review & Import

For high-value or critical artifacts, review individual configs before import:

```bash
# Extract individual configs from batch
cd output-camel-4.22-batches
grep -A 20 "^# Build config for" camel-4.22-batch-001.yaml
```

## Recommended Import Strategy

### Phase 1: High Confidence Batches (Batches 1-10)
- Import first 10 batches (150 artifacts)
- Monitor build success rate
- Adjust patterns if needed

### Phase 2: Remaining Batches (Batches 11-32)
- Import remaining 322 artifacts
- Track failures and patterns
- Create manual configs for any failures

### Phase 3: Validation
- Verify all 472 builds complete successfully
- Update AI training data with results
- Document any manual fixes needed

## Key Features

### ✅ Upstream URLs
All SCM URLs point to **upstream public repositories**, not downstream mirrors:
- ✅ `https://github.com/aws/aws-sdk-java-v2.git`
- ❌ ~~`git@github.ibm.com:pnc-prod/aws-aws-sdk-java-v2.git`~~

### ✅ AI-Predicted Configurations
- **SCM URLs:** Pattern-based prediction from 5,785 PNC builds
- **SCM Revisions:** Version-based tag prediction
- **Build Scripts:** Maven deployment with PNC integration
- **Environments:** OpenJDK 1.8 + Maven 3.6.3 (most common)

### ✅ Confidence Scoring
Each config includes confidence metrics:
- **Overall Confidence:** Combined SCM + build config score
- **SCM Confidence:** 85% (pattern-based) or 95% (learned)
- **Build Config Confidence:** 50% (fallback) or 70% (group match)

## Troubleshooting

### Issue: Import Fails with "Invalid YAML"
**Solution:** Validate YAML syntax
```bash
python3 -c "import yaml; yaml.safe_load(open('camel-4.22-batch-001.yaml'))"
```

### Issue: SCM URL Not Accessible
**Solution:** Verify upstream repository exists
```bash
curl -I https://github.com/aws/aws-sdk-java-v2.git
```

### Issue: Build Fails with Wrong Tag
**Solution:** Check actual tags in repository
```bash
git ls-remote --tags https://github.com/aws/aws-sdk-java-v2.git | grep 2.50.2
```

## Post-Import Actions

1. **Monitor Builds:** Track success rate in PNC dashboard
2. **Update AI Training:** Feed successful builds back to AI
3. **Document Failures:** Create manual configs for any failures
4. **Validate Artifacts:** Ensure all 472 artifacts are productized

## Files Reference

- **Individual Configs:** `output-camel-4.22-final/*.yaml` (472 files)
- **Batch Configs:** `output-camel-4.22-batches/*.yaml` (32 files)
- **Generation Log:** `build-config-generation-parallel.log`
- **AI Modules:** `lib/ai/*.py`

## Support

For issues or questions:
1. Review AI prediction: `./ai_enhance.sh predict <GAV>`
2. Check confidence: `grep "confidence:" output-camel-4.22-final/<artifact>.yaml`
3. Validate URL: `curl -I <scm_url>`
4. Manual override: Edit batch file before import

---

**Generated:** 2026-08-20 05:40:36 UTC  
**AI System:** Trained on 5,785 PNC builds with 5,912 cached resolutions  
**Success Rate:** 100% (472/472 configs generated)
