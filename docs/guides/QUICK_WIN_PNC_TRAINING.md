# Quick Win: PNC Training for Camel 4.22

## Goal

**Train AI with real Camel 4.22 build data from PNC in 2-3 days** to achieve immediate accuracy improvements.

## Focused Approach

Instead of building the full infrastructure, we'll create a **minimal viable solution** that:
1. Harvests Camel 4.22 build data from PNC
2. Converts it to AI training format
3. Trains the existing AI
4. Validates improvements

## Implementation (2-3 Days)

### Day 1: PNC Data Harvester (Minimal)

**Create**: `lib/ai/pnc_camel_harvester.py`

```python
#!/usr/bin/env python3
"""
Quick PNC harvester focused on Camel 4.22 builds
Minimal implementation for immediate results
"""

import json
import requests
from pathlib import Path
from typing import List, Dict

class CamelPNCHarvester:
    """Harvest Camel 4.22 build data from PNC"""
    
    def __init__(self, pnc_base_url: str = "https://orch.psi.redhat.com/pnc-rest/v2"):
        self.base_url = pnc_base_url
        self.session = requests.Session()
        self.session.headers.update({"Accept": "application/json"})
    
    def harvest_camel_builds(self, version_pattern: str = "4.22") -> List[Dict]:
        """
        Harvest all Camel builds matching version pattern
        
        Args:
            version_pattern: Version to match (e.g., "4.22")
            
        Returns:
            List of build records with SCM info
        """
        builds = []
        
        # Query PNC for Camel build configs
        print(f"Querying PNC for Camel {version_pattern} builds...")
        
        # Search for build configs with "camel" in name
        url = f"{self.base_url}/build-configs"
        params = {
            "q": f"name=like=camel-*",
            "pageSize": 200
        }
        
        response = self.session.get(url, params=params)
        response.raise_for_status()
        data = response.json()
        
        print(f"Found {len(data.get('content', []))} Camel build configs")
        
        # Filter and extract SCM info
        for config in data.get('content', []):
            name = config.get('name', '')
            
            # Filter by version pattern
            if version_pattern not in name:
                continue
            
            # Extract SCM info
            scm_repo = config.get('scmRepository', {})
            scm_url = scm_repo.get('internalUrl') or scm_repo.get('externalUrl')
            scm_revision = config.get('scmRevision')
            
            if not scm_url or not scm_revision:
                continue
            
            # Parse artifact info from name
            # Format: groupId_artifactId_version
            parts = name.split('_')
            if len(parts) >= 3:
                group_id = parts[0].replace('_', '.')
                artifact_id = parts[1]
                version = parts[2]
            else:
                # Fallback: try to parse from name
                artifact_id = name.split('-')[0] if '-' in name else name
                group_id = "org.apache.camel"
                version = version_pattern
            
            build_record = {
                "build_config_id": config.get('id'),
                "name": name,
                "group_id": group_id,
                "artifact_id": artifact_id,
                "version": version,
                "scm_url": scm_url,
                "scm_revision": scm_revision,
                "build_script": config.get('buildScript', ''),
                "environment_id": config.get('environment', {}).get('id'),
                "environment_name": config.get('environment', {}).get('name'),
                "source": "pnc_harvest"
            }
            
            builds.append(build_record)
            print(f"  ✓ {group_id}:{artifact_id}:{version}")
        
        return builds
    
    def save_to_jsonl(self, builds: List[Dict], output_file: str):
        """Save builds to JSONL file"""
        output_path = Path(output_file)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_path, 'w') as f:
            for build in builds:
                f.write(json.dumps(build) + '\n')
        
        print(f"\nSaved {len(builds)} builds to {output_file}")


if __name__ == '__main__':
    import sys
    
    version = sys.argv[1] if len(sys.argv) > 1 else "4.22"
    output = sys.argv[2] if len(sys.argv) > 2 else "pnc-camel-harvest.jsonl"
    
    harvester = CamelPNCHarvester()
    builds = harvester.harvest_camel_builds(version)
    harvester.save_to_jsonl(builds, output)
    
    print(f"\n✓ Harvested {len(builds)} Camel {version} builds from PNC")
```

**Usage**:
```bash
# Harvest Camel 4.22 builds
python3 lib/ai/pnc_camel_harvester.py 4.22 camel-4.22-pnc.jsonl
```

### Day 2: Training Converter & AI Integration

**Create**: `lib/ai/quick_train.py`

```python
#!/usr/bin/env python3
"""
Quick training script - converts PNC data and trains AI
"""

import json
import sys
from pathlib import Path
from scm_pattern_learner import SCMPatternLearner

def convert_and_train(pnc_harvest_file: str):
    """
    Convert PNC harvest to training format and train AI
    
    Args:
        pnc_harvest_file: Path to PNC harvest JSONL file
    """
    learner = SCMPatternLearner()
    
    print("Loading PNC harvest data...")
    training_count = 0
    
    with open(pnc_harvest_file) as f:
        for line in f:
            record = json.loads(line)
            
            # Extract fields
            group_id = record['group_id']
            artifact_id = record['artifact_id']
            version = record['version']
            scm_url = record['scm_url']
            scm_revision = record['scm_revision']
            
            # Train AI
            learner.learn_from_success(
                group_id, artifact_id, version,
                scm_url, scm_revision
            )
            
            training_count += 1
            if training_count % 10 == 0:
                print(f"  Trained on {training_count} builds...")
    
    print(f"\n✓ Trained AI on {training_count} builds")
    
    # Show statistics
    stats = learner.get_statistics()
    print("\nAI Statistics:")
    print(f"  Training samples: {stats['training_samples']}")
    print(f"  Cached resolutions: {stats['cached_resolutions']}")
    print(f"  Learned group patterns: {stats['learned_group_patterns']}")
    print(f"  Learned artifact patterns: {stats['learned_artifact_patterns']}")
    print(f"  Learned revision patterns: {stats['learned_revision_patterns']}")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: quick_train.py <pnc-harvest.jsonl>")
        sys.exit(1)
    
    convert_and_train(sys.argv[1])
```

**Usage**:
```bash
# Train AI from PNC harvest
python3 lib/ai/quick_train.py camel-4.22-pnc.jsonl
```

### Day 3: Validation & Integration

**Create**: `lib/ai/quick_validate.py`

```python
#!/usr/bin/env python3
"""
Quick validation - test AI predictions on Camel 4.22 artifacts
"""

import sys
from scm_pattern_learner import SCMPatternLearner

def validate_predictions(test_file: str):
    """
    Validate AI predictions against test set
    
    Args:
        test_file: File with test artifacts (one per line: group:artifact:version)
    """
    learner = SCMPatternLearner()
    
    print("Validating AI predictions...")
    
    total = 0
    correct = 0
    cached = 0
    predicted = 0
    failed = 0
    
    with open(test_file) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            
            parts = line.split(':')
            if len(parts) != 3:
                continue
            
            group_id, artifact_id, version = parts
            total += 1
            
            # Try prediction
            result = learner.predict_scm(group_id, artifact_id, version, verify_urls=False)
            
            if result:
                if result['method'] == 'cache':
                    cached += 1
                    correct += 1
                    status = "✓ CACHED"
                elif result['method'] == 'ai_prediction':
                    predicted += 1
                    correct += 1
                    status = f"✓ PREDICTED ({result['confidence']:.0%})"
                else:
                    status = "? UNKNOWN"
            else:
                failed += 1
                status = "✗ FAILED"
            
            print(f"{status:20} {group_id}:{artifact_id}:{version}")
    
    # Summary
    print("\n" + "="*60)
    print("VALIDATION SUMMARY")
    print("="*60)
    print(f"Total artifacts:     {total}")
    print(f"Successful:          {correct} ({correct/total*100:.1f}%)")
    print(f"  - From cache:      {cached}")
    print(f"  - AI predicted:    {predicted}")
    print(f"Failed:              {failed} ({failed/total*100:.1f}%)")
    print("="*60)
    
    if correct / total >= 0.8:
        print("\n✓ SUCCESS: AI accuracy >= 80%")
    else:
        print(f"\n⚠ WARNING: AI accuracy < 80% ({correct/total*100:.1f}%)")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: quick_validate.py <test-artifacts.txt>")
        sys.exit(1)
    
    validate_predictions(sys.argv[1])
```

**Usage**:
```bash
# Create test set from unproductized deps
head -50 camel-4.22.0-redhat-00002-report/unproductized-deps.txt > test-artifacts.txt

# Validate AI
python3 lib/ai/quick_validate.py test-artifacts.txt
```

## Quick Start Script

**Create**: `quick_train_pnc.sh`

```bash
#!/bin/bash
# Quick PNC training for Camel 4.22
# Complete workflow in one script

set -e

VERSION="${1:-4.22}"
OUTPUT_DIR="pnc-training-output"

echo "=== Quick PNC Training for Camel $VERSION ==="
echo ""

# Step 1: Harvest PNC data
echo "Step 1: Harvesting PNC data..."
python3 lib/ai/pnc_camel_harvester.py "$VERSION" "$OUTPUT_DIR/harvest.jsonl"
echo ""

# Step 2: Train AI
echo "Step 2: Training AI..."
python3 lib/ai/quick_train.py "$OUTPUT_DIR/harvest.jsonl"
echo ""

# Step 3: Create test set
echo "Step 3: Creating test set..."
if [[ -f "camel-4.22.0-redhat-00002-report/unproductized-deps.txt" ]]; then
    head -50 camel-4.22.0-redhat-00002-report/unproductized-deps.txt | \
        grep -v "^#" | \
        awk '{print $1}' > "$OUTPUT_DIR/test-artifacts.txt"
    echo "  Created test set with 50 artifacts"
else
    echo "  ⚠ Warning: No test set available"
fi
echo ""

# Step 4: Validate
if [[ -f "$OUTPUT_DIR/test-artifacts.txt" ]]; then
    echo "Step 4: Validating AI predictions..."
    python3 lib/ai/quick_validate.py "$OUTPUT_DIR/test-artifacts.txt"
else
    echo "Step 4: Skipped (no test set)"
fi

echo ""
echo "=== Training Complete ==="
echo "Output directory: $OUTPUT_DIR"
echo ""
echo "Next steps:"
echo "  1. Review validation results"
echo "  2. Test AI predictions: ./ai_enhance.sh predict <artifact>"
echo "  3. Use in autobuilder: source lib/scm_resolver_ai.sh"
```

**Usage**:
```bash
# Run complete workflow
chmod +x quick_train_pnc.sh
./quick_train_pnc.sh 4.22
```

## Expected Results

### After Day 1
- ✓ Harvested 200+ Camel 4.22 builds from PNC
- ✓ SCM URLs and revisions extracted
- ✓ Data saved in JSONL format

### After Day 2
- ✓ AI trained on 200+ builds
- ✓ Learned patterns for Camel components
- ✓ 80%+ coverage for Camel artifacts

### After Day 3
- ✓ Validation shows 80-90% accuracy
- ✓ AI can predict SCM for most Camel components
- ✓ Integrated with existing tools

## Success Metrics

| Metric | Before | After | Target |
|--------|--------|-------|--------|
| Training Data | <100 | 200+ | 200+ |
| Camel Coverage | 30% | 80%+ | 80%+ |
| Prediction Accuracy | 70% | 85%+ | 80%+ |
| Cache Hit Rate | 20% | 60%+ | 50%+ |

## Integration with Existing Tools

Once trained, the AI automatically works with:

```bash
# Use in autobuilder
./ai_enhance.sh predict org.apache.camel:camel-kafka:4.22.0

# Use in SCM resolution
source lib/scm_resolver_ai.sh
resolve_scm_with_ai "org.apache.camel" "camel-kafka" "4.22.0"

# Check AI status
./ai_enhance.sh status
```

## Next Steps After Quick Win

Once this quick win proves value:

1. **Expand to other projects** (Quarkus, Spring Boot)
2. **Automate daily updates** (cron job)
3. **Build full infrastructure** (per original plan)
4. **Add more validation** (URL verification, etc.)

## Advantages of Quick Win Approach

✓ **Fast Results**: 2-3 days vs 3 weeks
✓ **Immediate Value**: Train on real Camel 4.22 data
✓ **Low Risk**: Minimal code, easy to test
✓ **Proof of Concept**: Validates approach before full build
✓ **Iterative**: Can expand after proving value

## Files to Create

```
lib/ai/
├── pnc_camel_harvester.py    # Day 1
├── quick_train.py             # Day 2
└── quick_validate.py          # Day 3

quick_train_pnc.sh             # Complete workflow
```

## Dependencies

- Python 3.8+
- `requests` library: `pip3 install requests`
- Existing `scm_pattern_learner.py`
- PNC API access (no auth required for read)

---

**Ready to implement?** Start with Day 1 and we'll have results in 2-3 days!
