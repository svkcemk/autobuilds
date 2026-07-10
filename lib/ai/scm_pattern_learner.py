#!/usr/bin/env python3
"""
SCM Pattern Learner - AI-powered SCM URL and revision prediction
Uses pattern matching and historical data to learn SCM resolution patterns
"""

import json
import re
import hashlib
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Tuple, Optional
from collections import defaultdict
import subprocess


class SCMPatternLearner:
    """
    Learns SCM URL patterns from historical successful resolutions
    Provides intelligent fallback when traditional methods fail
    """
    
    def __init__(self, data_dir: str = None):
        """
        Initialize the SCM Pattern Learner
        
        Args:
            data_dir: Directory for storing training data and patterns
        """
        if data_dir is None:
            data_dir = Path.home() / ".bob" / "ai" / "scm_learner"
        
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)
        
        self.training_file = self.data_dir / "training_data.jsonl"
        self.patterns_file = self.data_dir / "learned_patterns.json"
        self.success_cache_file = self.data_dir / "success_cache.json"
        
        self.learned_patterns = self._load_patterns()
        self.success_cache = self._load_success_cache()
        
    def _load_patterns(self) -> Dict:
        """Load learned patterns from disk"""
        if self.patterns_file.exists():
            with open(self.patterns_file) as f:
                return json.load(f)
        return {
            'url_patterns': {},
            'revision_patterns': {},
            'group_mappings': {},
            'artifact_mappings': {}
        }
    
    def _save_patterns(self):
        """Save learned patterns to disk"""
        with open(self.patterns_file, 'w') as f:
            json.dump(self.learned_patterns, f, indent=2)
    
    def _load_success_cache(self) -> Dict:
        """Load success cache from disk"""
        if self.success_cache_file.exists():
            with open(self.success_cache_file) as f:
                return json.load(f)
        return {}
    
    def _save_success_cache(self):
        """Save success cache to disk"""
        with open(self.success_cache_file, 'w') as f:
            json.dump(self.success_cache, f, indent=2)
    
    def generate_candidate_urls(self, group_id: str, artifact_id: str) -> List[str]:
        """
        Generate candidate SCM URLs using learned patterns and heuristics
        
        Args:
            group_id: Maven group ID (e.g., "org.apache.camel")
            artifact_id: Maven artifact ID (e.g., "camel-kafka")
            
        Returns:
            List of candidate URLs ordered by likelihood
        """
        candidates = []
        
        # Check learned patterns first
        group_key = group_id
        if group_key in self.learned_patterns['group_mappings']:
            pattern = self.learned_patterns['group_mappings'][group_key]
            url = pattern.replace('{artifact_id}', artifact_id)
            candidates.append(url)
        
        artifact_key = f"{group_id}:{artifact_id}"
        if artifact_key in self.learned_patterns['artifact_mappings']:
            candidates.append(self.learned_patterns['artifact_mappings'][artifact_key])
        
        # Extract organization name from group ID
        parts = group_id.split('.')
        org_name = parts[-1] if parts else group_id
        
        # GitHub patterns (most common)
        candidates.extend([
            f"https://github.com/{org_name}/{artifact_id}.git",
            f"https://github.com/{org_name}/{artifact_id}",
            f"https://github.com/{group_id.replace('.', '/')}/{artifact_id}.git",
        ])
        
        # Apache-specific patterns
        if 'apache' in group_id.lower():
            project = artifact_id
            # Remove common prefixes
            for prefix in [f"{org_name}-", "apache-"]:
                if project.startswith(prefix):
                    project = project[len(prefix):]
            
            candidates.extend([
                f"https://github.com/apache/{project}.git",
                f"https://github.com/apache/{artifact_id}.git",
                f"https://gitbox.apache.org/repos/asf/{project}.git",
            ])
        
        # GitLab patterns
        candidates.extend([
            f"https://gitlab.com/{org_name}/{artifact_id}.git",
            f"https://gitlab.com/{group_id.replace('.', '/')}/{artifact_id}.git",
        ])
        
        # Google-specific patterns
        if 'google' in group_id.lower():
            candidates.extend([
                f"https://github.com/googleapis/{artifact_id}.git",
                f"https://github.com/google/{artifact_id}.git",
            ])
        
        # Eclipse-specific patterns
        if 'eclipse' in group_id.lower():
            candidates.extend([
                f"https://github.com/eclipse/{artifact_id}.git",
                f"https://github.com/eclipse-ee4j/{artifact_id}.git",
            ])
        
        # Remove duplicates while preserving order
        seen = set()
        unique_candidates = []
        for url in candidates:
            if url not in seen:
                seen.add(url)
                unique_candidates.append(url)
        
        return unique_candidates
    
    def predict_scm_revision(self, version: str, scm_url: str) -> str:
        """
        Predict SCM revision/tag from version using learned patterns
        
        Args:
            version: Artifact version (e.g., "4.18.1")
            scm_url: SCM URL
            
        Returns:
            Predicted revision/tag
        """
        # Check learned patterns
        url_hash = hashlib.md5(scm_url.encode()).hexdigest()
        if url_hash in self.learned_patterns['revision_patterns']:
            pattern = self.learned_patterns['revision_patterns'][url_hash]
            return pattern.replace('{version}', version)
        
        # Heuristic-based prediction
        if 'github.com/apache' in scm_url:
            # Apache projects often use: rel/artifact-version
            artifact = scm_url.split('/')[-1].replace('.git', '')
            return f"rel/{artifact}-{version}"
        
        elif 'github.com/google' in scm_url or 'github.com/googleapis' in scm_url:
            # Google projects typically use: v{version}
            return f"v{version}"
        
        elif 'github.com/FasterXML' in scm_url:
            # Jackson uses: artifact-version
            artifact = scm_url.split('/')[-1].replace('.git', '')
            return f"{artifact}-{version}"
        
        elif 'github.com/eclipse' in scm_url:
            # Eclipse projects vary, try version first
            return version
        
        elif 'gitlab.ow2.org' in scm_url:
            # OW2 (ASM) uses: ASM_X_Y_Z
            return f"ASM_{version.replace('.', '_')}"
        
        # Default: try v{version} (most common)
        return f"v{version}"
    
    def learn_from_success(self, group_id: str, artifact_id: str, version: str, 
                          scm_url: str, scm_revision: str):
        """
        Learn from successful SCM resolution
        Updates patterns and training data
        
        Args:
            group_id: Maven group ID
            artifact_id: Maven artifact ID
            version: Artifact version
            scm_url: Successful SCM URL
            scm_revision: Successful SCM revision
        """
        # Store in training data
        training_record = {
            'group_id': group_id,
            'artifact_id': artifact_id,
            'version': version,
            'scm_url': scm_url,
            'scm_revision': scm_revision,
            'timestamp': datetime.now().isoformat()
        }
        
        # Append to training file
        with open(self.training_file, 'a') as f:
            f.write(json.dumps(training_record) + '\n')
        
        # Update success cache
        cache_key = f"{group_id}:{artifact_id}:{version}"
        self.success_cache[cache_key] = {
            'scm_url': scm_url,
            'scm_revision': scm_revision,
            'timestamp': datetime.now().isoformat()
        }
        self._save_success_cache()
        
        # Extract and learn patterns
        self._extract_patterns(group_id, artifact_id, version, scm_url, scm_revision)
        self._save_patterns()
    
    def _extract_patterns(self, group_id: str, artifact_id: str, version: str,
                         scm_url: str, scm_revision: str):
        """Extract patterns from successful resolution"""
        
        # Learn group-level URL pattern
        url_template = scm_url.replace(artifact_id, '{artifact_id}')
        if group_id not in self.learned_patterns['group_mappings']:
            self.learned_patterns['group_mappings'][group_id] = url_template
        
        # Learn artifact-specific mapping
        artifact_key = f"{group_id}:{artifact_id}"
        self.learned_patterns['artifact_mappings'][artifact_key] = scm_url
        
        # Learn revision pattern
        url_hash = hashlib.md5(scm_url.encode()).hexdigest()
        revision_template = scm_revision.replace(version, '{version}')
        if url_hash not in self.learned_patterns['revision_patterns']:
            self.learned_patterns['revision_patterns'][url_hash] = revision_template
    
    def get_from_cache(self, group_id: str, artifact_id: str, version: str) -> Optional[Dict]:
        """
        Get SCM info from success cache
        
        Returns:
            Dict with scm_url and scm_revision, or None if not cached
        """
        cache_key = f"{group_id}:{artifact_id}:{version}"
        return self.success_cache.get(cache_key)
    
    def predict_scm(self, group_id: str, artifact_id: str, version: str,
                   verify_urls: bool = True) -> Optional[Dict]:
        """
        Predict SCM URL and revision using learned patterns
        
        Args:
            group_id: Maven group ID
            artifact_id: Maven artifact ID
            version: Artifact version
            verify_urls: Whether to verify URLs are accessible
            
        Returns:
            Dict with scm_url, scm_revision, confidence, method
            or None if prediction fails
        """
        # Check cache first
        cached = self.get_from_cache(group_id, artifact_id, version)
        if cached:
            return {
                'scm_url': cached['scm_url'],
                'scm_revision': cached['scm_revision'],
                'confidence': 1.0,
                'method': 'cache'
            }
        
        # Generate candidates
        candidates = self.generate_candidate_urls(group_id, artifact_id)
        
        if not candidates:
            return None
        
        # Verify candidates if requested
        if verify_urls:
            valid_candidates = []
            for url in candidates:
                if self._verify_url_accessible(url):
                    valid_candidates.append(url)
                    if len(valid_candidates) >= 3:  # Limit verification
                        break
            
            if not valid_candidates:
                return None
            
            candidates = valid_candidates
        
        # Use first candidate (highest confidence)
        best_url = candidates[0]
        predicted_revision = self.predict_scm_revision(version, best_url)
        
        # Calculate confidence based on pattern match
        confidence = 0.7  # Base confidence for heuristic
        if group_id in self.learned_patterns['group_mappings']:
            confidence = 0.9  # Higher confidence for learned patterns
        
        return {
            'scm_url': best_url,
            'scm_revision': predicted_revision,
            'confidence': confidence,
            'method': 'ai_prediction'
        }
    
    def _verify_url_accessible(self, url: str, timeout: int = 5) -> bool:
        """
        Verify if URL is accessible via HTTP HEAD request
        
        Args:
            url: URL to verify
            timeout: Timeout in seconds
            
        Returns:
            True if accessible, False otherwise
        """
        try:
            # Use curl for HTTP HEAD request
            result = subprocess.run(
                ['curl', '-I', '-s', '-f', '-m', str(timeout), url],
                capture_output=True,
                timeout=timeout + 1
            )
            return result.returncode == 0
        except:
            return False
    
    def get_statistics(self) -> Dict:
        """
        Get learning statistics
        
        Returns:
            Dict with statistics about learned patterns
        """
        training_count = 0
        if self.training_file.exists():
            with open(self.training_file) as f:
                training_count = sum(1 for _ in f)
        
        return {
            'training_samples': training_count,
            'cached_resolutions': len(self.success_cache),
            'learned_group_patterns': len(self.learned_patterns['group_mappings']),
            'learned_artifact_patterns': len(self.learned_patterns['artifact_mappings']),
            'learned_revision_patterns': len(self.learned_patterns['revision_patterns'])
        }
    
    def export_patterns(self, output_file: str):
        """Export learned patterns to file for inspection"""
        with open(output_file, 'w') as f:
            json.dump({
                'patterns': self.learned_patterns,
                'statistics': self.get_statistics(),
                'exported_at': datetime.now().isoformat()
            }, f, indent=2)


# CLI interface for testing
if __name__ == '__main__':
    import sys
    
    if len(sys.argv) < 4:
        print("Usage: scm_pattern_learner.py <group_id> <artifact_id> <version>")
        print("Example: scm_pattern_learner.py org.apache.camel camel-kafka 4.18.1")
        sys.exit(1)
    
    group_id = sys.argv[1]
    artifact_id = sys.argv[2]
    version = sys.argv[3]
    
    learner = SCMPatternLearner()
    
    print(f"Predicting SCM for {group_id}:{artifact_id}:{version}")
    print()
    
    # Show statistics
    stats = learner.get_statistics()
    print("Learning Statistics:")
    print(f"  Training samples: {stats['training_samples']}")
    print(f"  Cached resolutions: {stats['cached_resolutions']}")
    print(f"  Learned patterns: {stats['learned_group_patterns']} groups, "
          f"{stats['learned_artifact_patterns']} artifacts")
    print()
    
    # Generate candidates
    print("Candidate URLs:")
    candidates = learner.generate_candidate_urls(group_id, artifact_id)
    for i, url in enumerate(candidates[:5], 1):
        print(f"  {i}. {url}")
    print()
    
    # Predict
    result = learner.predict_scm(group_id, artifact_id, version, verify_urls=False)
    if result:
        print("Prediction:")
        print(f"  SCM URL: {result['scm_url']}")
        print(f"  SCM Revision: {result['scm_revision']}")
        print(f"  Confidence: {result['confidence']:.0%}")
        print(f"  Method: {result['method']}")
    else:
        print("Failed to predict SCM")
