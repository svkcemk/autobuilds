# PNC API-Powered AI Training Plan

## Problem Statement

The current AI/ML features learn only from successful resolutions during runtime. This is slow and limited. **PNC (Project Newcastle) has thousands of successful builds with verified SCM information** that we're not leveraging for training.

## Opportunity

PNC API provides access to:
- **Build Configs**: SCM URLs, revisions, build scripts, environments
- **Build Records**: Successful/failed builds with metadata
- **Artifacts**: Maven coordinates linked to builds
- **Projects**: Grouping of related build configs

This is a **goldmine of training data** that can dramatically improve AI prediction accuracy.

## Current State

### Existing AI Components

1. **SCM Pattern Learner** (`lib/ai/scm_pattern_learner.py`)
   - Learns from successful resolutions
   - Stores patterns in `~/.bob/ai/scm_learner/`
   - Currently has minimal training data

2. **PNC Integration** (`generate_with_pnc_integration.sh`)
   - Queries PNC for individual artifacts
   - One-at-a-time approach
   - Not used for bulk training

### Gap Analysis

❌ **No bulk data harvesting from PNC**
❌ **No automated training pipeline**
❌ **No incremental learning from PNC updates**
❌ **No validation of AI improvements**
❌ **Limited training data (only runtime successes)**

## Proposed Solution

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     PNC API (Data Source)                    │
│  - Build Configs (SCM URLs, revisions, scripts)             │
│  - Build Records (success/failure, timestamps)              │
│  - Artifacts (Maven coordinates)                            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              PNC Data Harvester (New Component)              │
│  - Bulk query PNC API                                       │
│  - Filter successful builds                                 │
│  - Extract SCM metadata                                     │
│  - Rate limiting & caching                                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│           Training Data Converter (New Component)            │
│  - Convert PNC format → AI training format                  │
│  - Validate data quality                                    │
│  - Deduplicate entries                                      │
│  - Enrich with metadata                                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│         Enhanced SCM Pattern Learner (Updated)               │
│  - Bulk import training data                                │
│  - Incremental learning                                     │
│  - Pattern extraction & optimization                        │
│  - Confidence scoring                                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Validation Framework (New Component)            │
│  - Measure prediction accuracy                              │
│  - Compare before/after training                            │
│  - Generate improvement reports                             │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Plan

### Phase 1: PNC Data Harvester (Week 1)

**Goal**: Create tool to bulk harvest build data from PNC API

**Components**:

1. **PNC API Client** (`lib/ai/pnc_client.py`)
   ```python
   class PNCClient:
       - query_build_configs(filters, limit)
       - query_build_records(build_config_id)
       - query_artifacts(gav)
       - get_scm_repository(repo_id)
       - batch_query(queries)  # Parallel requests
   ```

2. **Data Harvester** (`lib/ai/pnc_harvester.py`)
   ```python
   class PNCHarvester:
       - harvest_successful_builds(date_range, filters)
       - extract_scm_metadata(build_config)
       - filter_quality_data(builds)
       - save_raw_data(output_dir)
   ```

**Key Features**:
- **Parallel API requests** (10-20 concurrent)
- **Rate limiting** (respect PNC API limits)
- **Caching** (avoid re-fetching same data)
- **Filtering**: Only successful builds, valid SCM URLs
- **Progress tracking**: Show harvest progress

**API Endpoints to Use**:
```
GET /pnc-rest/v2/build-configs
GET /pnc-rest/v2/builds
GET /pnc-rest/v2/artifacts
GET /pnc-rest/v2/scm-repositories
```

**Output Format** (JSONL):
```json
{
  "build_config_id": "12345",
  "name": "camel-kafka-4.18.1",
  "group_id": "org.apache.camel",
  "artifact_id": "camel-kafka",
  "version": "4.18.1",
  "scm_url": "https://github.com/apache/camel.git",
  "scm_revision": "camel-kafka-4.18.1",
  "scm_tag": "camel-kafka-4.18.1",
  "build_script": "mvn clean deploy -DskipTests",
  "environment_id": "1200",
  "environment_name": "OpenJDK 11.0; Mvn 3.5.4",
  "build_status": "SUCCESS",
  "build_time": "2024-03-15T10:30:00Z",
  "artifacts": ["org.apache.camel:camel-kafka:4.18.1"]
}
```

### Phase 2: Training Data Converter (Week 1-2)

**Goal**: Convert PNC data to AI training format

**Components**:

1. **Data Converter** (`lib/ai/training_converter.py`)
   ```python
   class TrainingConverter:
       - convert_pnc_to_training(pnc_data)
       - validate_scm_url(url)
       - normalize_revision(revision, url)
       - extract_patterns(group_id, artifact_id, scm_url)
       - deduplicate_entries(training_data)
   ```

**Conversion Logic**:
```
PNC Build Config → AI Training Record

Input:
{
  "name": "camel-kafka-4.18.1",
  "scm_url": "https://github.com/apache/camel.git",
  "scm_revision": "camel-kafka-4.18.1",
  ...
}

Output:
{
  "group_id": "org.apache.camel",
  "artifact_id": "camel-kafka",
  "version": "4.18.1",
  "scm_url": "https://github.com/apache/camel.git",
  "scm_revision": "camel-kafka-4.18.1",
  "timestamp": "2024-03-15T10:30:00Z",
  "source": "pnc_harvest",
  "confidence": 1.0
}
```

**Data Quality Checks**:
- ✓ Valid SCM URL (accessible, correct format)
- ✓ Valid Maven coordinates (group:artifact:version)
- ✓ SCM revision exists in repository
- ✓ No duplicate entries
- ✓ Successful build status

### Phase 3: Enhanced SCM Pattern Learner (Week 2)

**Goal**: Update AI to support bulk training from PNC data

**Updates to `scm_pattern_learner.py`**:

```python
class SCMPatternLearner:
    # New methods
    def bulk_import_training_data(self, training_file: str):
        """Import bulk training data from JSONL file"""
        
    def learn_from_batch(self, training_records: List[Dict]):
        """Learn from batch of training records"""
        
    def optimize_patterns(self):
        """Optimize learned patterns (merge similar, remove outliers)"""
        
    def get_pattern_coverage(self) -> Dict:
        """Calculate coverage of learned patterns"""
        
    def export_training_report(self, output_file: str):
        """Export detailed training report"""
```

**Pattern Optimization**:
- Merge similar patterns (e.g., `github.com/apache/*`)
- Weight patterns by success count
- Remove outliers (patterns with <3 examples)
- Calculate confidence scores based on evidence

### Phase 4: Validation Framework (Week 2-3)

**Goal**: Measure AI improvement from PNC training

**Components**:

1. **Validation Suite** (`lib/ai/validator.py`)
   ```python
   class AIValidator:
       - create_test_set(size, source)
       - measure_accuracy(test_set)
       - compare_before_after(baseline, trained)
       - generate_report(results)
   ```

**Metrics to Track**:
- **Prediction Accuracy**: % of correct predictions
- **Coverage**: % of artifacts with learned patterns
- **Confidence Distribution**: How confident is the AI?
- **Speed**: Prediction time (should be <1s)
- **Cache Hit Rate**: % of cache hits

**Test Methodology**:
1. Create test set (500 artifacts from Camel 4.22)
2. Measure baseline accuracy (before PNC training)
3. Harvest PNC data and train AI
4. Measure new accuracy (after PNC training)
5. Generate comparison report

**Expected Improvements**:
- Accuracy: 70% → **90%+**
- Coverage: 30% → **80%+**
- Cache hits: 20% → **60%+**

### Phase 5: Automation & Integration (Week 3)

**Goal**: Automate PNC training pipeline

**Components**:

1. **Training Pipeline** (`ai_train_from_pnc.sh`)
   ```bash
   #!/bin/bash
   # Automated PNC training pipeline
   
   # Step 1: Harvest PNC data
   python3 lib/ai/pnc_harvester.py \
     --date-range "2024-01-01:2024-12-31" \
     --filters "status=SUCCESS" \
     --output pnc-harvest.jsonl
   
   # Step 2: Convert to training format
   python3 lib/ai/training_converter.py \
     --input pnc-harvest.jsonl \
     --output training-data.jsonl \
     --validate
   
   # Step 3: Import to AI
   python3 lib/ai/scm_pattern_learner.py \
     --bulk-import training-data.jsonl \
     --optimize
   
   # Step 4: Validate improvements
   python3 lib/ai/validator.py \
     --test-set camel-4.22-test.txt \
     --report validation-report.json
   ```

2. **Incremental Updates** (Cron job)
   ```bash
   # Daily: Harvest new builds from last 24 hours
   0 2 * * * /path/to/ai_train_from_pnc.sh --incremental
   ```

3. **Integration with Existing Tools**
   - Update `ai_enhance.sh` to support PNC training
   - Add `--train-from-pnc` flag to autobuilder
   - Show training statistics in status output

## Data Sources & Scope

### PNC API Endpoints

**Primary Data Source**:
```
Base URL: https://orch.psi.redhat.com/pnc-rest/v2
```

**Key Endpoints**:
1. `/build-configs` - Get all build configurations
2. `/builds` - Get build records (filter by status=SUCCESS)
3. `/artifacts` - Get artifact metadata
4. `/scm-repositories` - Get SCM repository details

**Query Strategy**:
```bash
# Get successful builds for Camel components
GET /builds?q=buildConfigName=like=camel-*;status==SUCCESS

# Get build config details
GET /build-configs/{id}

# Get SCM repository
GET /scm-repositories/{id}
```

### Target Datasets

**Initial Training Set** (Phase 1):
- **Camel 4.18.x builds**: ~200 components
- **Camel 4.22.x builds**: ~220 components
- **Quarkus 3.x builds**: ~500 components
- **Total**: ~1000 successful builds

**Extended Training Set** (Phase 2):
- **All Apache projects**: ~2000 builds
- **All successful builds (2024)**: ~5000 builds
- **Historical builds (2023-2024)**: ~10000 builds

## Success Criteria

### Quantitative Metrics

| Metric | Baseline | Target | Measurement |
|--------|----------|--------|-------------|
| Prediction Accuracy | 70% | 90%+ | Test set validation |
| Pattern Coverage | 30% | 80%+ | % artifacts with patterns |
| Cache Hit Rate | 20% | 60%+ | Runtime statistics |
| Training Data Size | <100 | 1000+ | # of training records |
| Prediction Time | <1s | <1s | Performance benchmark |

### Qualitative Goals

✓ **Automated Training**: No manual intervention required
✓ **Incremental Learning**: Daily updates from new PNC builds
✓ **Validated Improvements**: Measurable accuracy gains
✓ **Production Ready**: Integrated with existing tools
✓ **Well Documented**: Clear usage guide and examples

## Implementation Timeline

### Week 1: Foundation
- [ ] Day 1-2: PNC API client (`pnc_client.py`)
- [ ] Day 3-4: Data harvester (`pnc_harvester.py`)
- [ ] Day 5: Training converter (`training_converter.py`)

### Week 2: AI Enhancement
- [ ] Day 1-2: Update SCM Pattern Learner (bulk import)
- [ ] Day 3-4: Validation framework (`validator.py`)
- [ ] Day 5: Initial training run & validation

### Week 3: Automation
- [ ] Day 1-2: Training pipeline script
- [ ] Day 3: Integration with existing tools
- [ ] Day 4: Documentation & examples
- [ ] Day 5: Testing & refinement

## Example Usage

### One-Time Training

```bash
# Harvest PNC data for Camel 4.22
./ai_train_from_pnc.sh \
  --project "camel" \
  --version "4.22.*" \
  --output camel-4.22-training.jsonl

# Train AI
./ai_enhance.sh train --input camel-4.22-training.jsonl

# Validate improvements
./ai_enhance.sh validate --test-set camel-4.22-test.txt
```

### Incremental Updates

```bash
# Daily cron job: harvest last 24 hours
0 2 * * * /path/to/ai_train_from_pnc.sh --incremental --days 1
```

### Manual Training

```bash
# Harvest specific build configs
./ai_train_from_pnc.sh \
  --build-config-ids "12345,12346,12347" \
  --output manual-training.jsonl

# Import to AI
./ai_enhance.sh train --input manual-training.jsonl
```

## Risk Mitigation

### API Rate Limiting
- **Risk**: PNC API may rate limit bulk requests
- **Mitigation**: 
  - Implement exponential backoff
  - Respect rate limits (max 10 req/sec)
  - Cache responses aggressively

### Data Quality
- **Risk**: PNC data may have errors or inconsistencies
- **Mitigation**:
  - Validate all SCM URLs before training
  - Filter out failed builds
  - Manual review of outliers

### Performance Impact
- **Risk**: Bulk training may be slow
- **Mitigation**:
  - Parallel processing (10-20 workers)
  - Incremental updates (not full retraining)
  - Optimize pattern storage

### Maintenance
- **Risk**: PNC API changes may break harvester
- **Mitigation**:
  - Version API client
  - Add API compatibility checks
  - Fallback to manual training

## Expected Outcomes

### Immediate Benefits (Week 1-2)
- ✓ 1000+ training records from PNC
- ✓ 80%+ pattern coverage for Camel components
- ✓ 90%+ prediction accuracy on test set

### Long-Term Benefits (Month 1-3)
- ✓ 10,000+ training records (all projects)
- ✓ 95%+ prediction accuracy
- ✓ Automated daily training updates
- ✓ Reduced manual SCM resolution by 80%

### Strategic Impact
- **Faster Productization**: Less manual intervention
- **Higher Quality**: Validated SCM info from PNC
- **Scalability**: Can handle 1000s of artifacts
- **Knowledge Sharing**: Patterns learned from all projects

## Next Steps

1. **Review & Approve Plan**: Get stakeholder buy-in
2. **Set Up Development Environment**: PNC API access, test data
3. **Start Implementation**: Begin with PNC API client
4. **Iterative Development**: Build, test, validate each component
5. **Production Deployment**: Integrate with existing autobuilder

## References

- **PNC API Documentation**: https://orch.psi.redhat.com/pnc-rest/v2/swagger-ui.html
- **Existing AI Features**: `AI_FEATURES.md`
- **SCM Pattern Learner**: `lib/ai/scm_pattern_learner.py`
- **PNC Integration**: `generate_with_pnc_integration.sh`

---

**Document Version**: 1.0
**Last Updated**: 2026-08-19
**Status**: Proposed - Awaiting Approval
