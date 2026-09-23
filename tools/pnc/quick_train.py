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
    harvest_path = Path(pnc_harvest_file)
    
    if not harvest_path.exists():
        print(f"Error: Harvest file not found: {pnc_harvest_file}")
        sys.exit(1)
    
    print("="*60)
    print("Quick AI Training from PNC Data")
    print("="*60)
    print()
    
    learner = SCMPatternLearner()
    
    # Show initial statistics
    initial_stats = learner.get_statistics()
    print("Initial AI Statistics:")
    print(f"  Training samples: {initial_stats['training_samples']}")
    print(f"  Cached resolutions: {initial_stats['cached_resolutions']}")
    print(f"  Learned group patterns: {initial_stats['learned_group_patterns']}")
    print(f"  Learned artifact patterns: {initial_stats['learned_artifact_patterns']}")
    print()
    
    print(f"Loading PNC harvest data from {pnc_harvest_file}...")
    training_count = 0
    skipped = 0
    errors = 0
    
    with open(pnc_harvest_file) as f:
        for line_num, line in enumerate(f, 1):
            try:
                record = json.loads(line)
                
                # Extract fields
                group_id = record.get('group_id')
                artifact_id = record.get('artifact_id')
                version = record.get('version')
                scm_url = record.get('scm_url')
                scm_revision = record.get('scm_revision')
                
                # Validate required fields
                if not all([group_id, artifact_id, version, scm_url, scm_revision]):
                    skipped += 1
                    continue
                
                # Train AI
                learner.learn_from_success(
                    group_id, artifact_id, version,
                    scm_url, scm_revision
                )
                
                training_count += 1
                if training_count % 10 == 0:
                    print(f"  Trained on {training_count} builds...")
                
            except json.JSONDecodeError as e:
                print(f"  Warning: Invalid JSON on line {line_num}: {e}")
                errors += 1
            except Exception as e:
                print(f"  Warning: Error processing line {line_num}: {e}")
                errors += 1
    
    print()
    print("="*60)
    print(f"✓ Training Complete")
    print("="*60)
    print(f"  Successfully trained: {training_count} builds")
    if skipped > 0:
        print(f"  Skipped (incomplete): {skipped} builds")
    if errors > 0:
        print(f"  Errors: {errors} builds")
    print()
    
    # Show updated statistics
    final_stats = learner.get_statistics()
    print("Updated AI Statistics:")
    print(f"  Training samples: {final_stats['training_samples']} (+{final_stats['training_samples'] - initial_stats['training_samples']})")
    print(f"  Cached resolutions: {final_stats['cached_resolutions']} (+{final_stats['cached_resolutions'] - initial_stats['cached_resolutions']})")
    print(f"  Learned group patterns: {final_stats['learned_group_patterns']} (+{final_stats['learned_group_patterns'] - initial_stats['learned_group_patterns']})")
    print(f"  Learned artifact patterns: {final_stats['learned_artifact_patterns']} (+{final_stats['learned_artifact_patterns'] - initial_stats['learned_artifact_patterns']})")
    print(f"  Learned revision patterns: {final_stats['learned_revision_patterns']} (+{final_stats['learned_revision_patterns'] - initial_stats['learned_revision_patterns']})")
    print()
    
    # Calculate improvement
    if initial_stats['cached_resolutions'] > 0:
        improvement = ((final_stats['cached_resolutions'] - initial_stats['cached_resolutions']) / 
                      initial_stats['cached_resolutions'] * 100)
        print(f"Cache improvement: +{improvement:.1f}%")
    else:
        print(f"Cache improvement: {final_stats['cached_resolutions']} new entries")
    
    print()
    print("="*60)
    print("Next steps:")
    print("  1. Validate predictions: python3 lib/ai/quick_validate.py <test-file>")
    print("  2. Test AI: ./ai_enhance.sh predict <artifact>")
    print("  3. Check status: ./ai_enhance.sh status")
    print("="*60)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: quick_train.py <pnc-harvest.jsonl>")
        print()
        print("Example:")
        print("  python3 lib/ai/quick_train.py pnc-camel-harvest.jsonl")
        sys.exit(1)
    
    convert_and_train(sys.argv[1])
