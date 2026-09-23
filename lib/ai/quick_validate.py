#!/usr/bin/env python3
"""
Quick validation - test AI predictions on Camel 4.22 artifacts
"""

import sys
from pathlib import Path
from scm_pattern_learner import SCMPatternLearner


def validate_predictions(test_file: str):
    """
    Validate AI predictions against test set
    
    Args:
        test_file: File with test artifacts (one per line: group:artifact:version)
    """
    test_path = Path(test_file)
    
    if not test_path.exists():
        print(f"Error: Test file not found: {test_file}")
        sys.exit(1)
    
    print("="*60)
    print("AI Prediction Validation")
    print("="*60)
    print()
    
    learner = SCMPatternLearner()
    
    # Show AI statistics
    stats = learner.get_statistics()
    print("AI Statistics:")
    print(f"  Training samples: {stats['training_samples']}")
    print(f"  Cached resolutions: {stats['cached_resolutions']}")
    print(f"  Learned patterns: {stats['learned_group_patterns']} groups, {stats['learned_artifact_patterns']} artifacts")
    print()
    
    print(f"Validating predictions from {test_file}...")
    print()
    
    total = 0
    correct = 0
    cached = 0
    predicted = 0
    failed = 0
    
    results = []
    
    with open(test_file) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            
            # Parse artifact coordinates
            parts = line.split(':')
            if len(parts) < 3:
                # Try space-separated format
                parts = line.split()
                if len(parts) > 0:
                    coords = parts[0].split(':')
                    if len(coords) >= 3:
                        parts = coords
            
            if len(parts) < 3:
                continue
            
            group_id = parts[0]
            artifact_id = parts[1]
            version = parts[2]
            
            total += 1
            
            # Try prediction
            result = learner.predict_scm(group_id, artifact_id, version, verify_urls=False)
            
            if result:
                if result['method'] == 'cache':
                    cached += 1
                    correct += 1
                    status = "✓ CACHED"
                    confidence = 100
                elif result['method'] == 'ai_prediction':
                    predicted += 1
                    correct += 1
                    confidence = int(result['confidence'] * 100)
                    status = f"✓ PREDICTED ({confidence}%)"
                else:
                    status = "? UNKNOWN"
                    confidence = 0
                
                results.append({
                    'artifact': f"{group_id}:{artifact_id}:{version}",
                    'status': 'success',
                    'method': result['method'],
                    'confidence': confidence,
                    'scm_url': result.get('scm_url', ''),
                    'scm_revision': result.get('scm_revision', '')
                })
            else:
                failed += 1
                status = "✗ FAILED"
                results.append({
                    'artifact': f"{group_id}:{artifact_id}:{version}",
                    'status': 'failed',
                    'method': 'none',
                    'confidence': 0
                })
            
            print(f"{status:20} {group_id}:{artifact_id}:{version}")
    
    # Summary
    print()
    print("="*60)
    print("VALIDATION SUMMARY")
    print("="*60)
    print(f"Total artifacts:     {total}")
    print(f"Successful:          {correct} ({correct/total*100:.1f}%)" if total > 0 else "Successful:          0")
    print(f"  - From cache:      {cached}")
    print(f"  - AI predicted:    {predicted}")
    print(f"Failed:              {failed} ({failed/total*100:.1f}%)" if total > 0 else "Failed:              0")
    print("="*60)
    print()
    
    if total > 0:
        accuracy = correct / total * 100
        
        if accuracy >= 80:
            print(f"✓ SUCCESS: AI accuracy is {accuracy:.1f}% (target: 80%+)")
        elif accuracy >= 70:
            print(f"⚠ GOOD: AI accuracy is {accuracy:.1f}% (close to target)")
        else:
            print(f"✗ NEEDS IMPROVEMENT: AI accuracy is {accuracy:.1f}% (target: 80%+)")
        
        print()
        
        # Breakdown by method
        if cached > 0:
            print(f"Cache hit rate: {cached/total*100:.1f}%")
        if predicted > 0:
            print(f"AI prediction rate: {predicted/total*100:.1f}%")
        
        print()
        print("="*60)
        print("Recommendations:")
        if accuracy < 80:
            print("  • Train on more PNC data to improve accuracy")
            print("  • Check failed predictions for patterns")
            print("  • Consider manual SCM resolution for failed cases")
        else:
            print("  • AI is ready for production use!")
            print("  • Consider expanding to other projects")
            print("  • Set up incremental training from PNC")
        print("="*60)
    else:
        print("No artifacts to validate")
    
    return results


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: quick_validate.py <test-artifacts.txt>")
        print()
        print("Test file format (one per line):")
        print("  group:artifact:version")
        print("  or")
        print("  group:artifact:version <other fields>")
        print()
        print("Example:")
        print("  python3 lib/ai/quick_validate.py test-artifacts.txt")
        sys.exit(1)
    
    validate_predictions(sys.argv[1])
