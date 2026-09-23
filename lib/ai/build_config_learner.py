#!/usr/bin/env python3
"""
Build Config Learner - AI-powered build configuration prediction
Learns build scripts, environment settings, and alignment parameters from PNC data
"""

import json
import re
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Tuple, Optional
from collections import defaultdict, Counter


class BuildConfigLearner:
    """
    Learns complete build configurations from historical PNC builds
    Includes SCM, build scripts, environments, and parameters
    """
    
    def __init__(self, data_dir: str = None):
        if data_dir is None:
            data_dir = Path.home() / ".bob" / "ai" / "build_config_learner"
        
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)
        
        self.training_file = self.data_dir / "training_data.jsonl"
        self.patterns_file = self.data_dir / "learned_patterns.json"
        
        self.learned_patterns = self._load_patterns()
    
    def _load_patterns(self) -> Dict:
        """Load learned patterns from disk"""
        if self.patterns_file.exists():
            with open(self.patterns_file) as f:
                return json.load(f)
        return {
            'build_scripts': {},  # artifact -> build script patterns
            'environments': {},   # artifact -> environment preferences
            'script_templates': {},  # common script patterns
            'env_by_jdk': {},  # JDK version -> environment IDs
            'env_by_tool': {},  # Tool (maven/gradle) -> environment IDs
        }
    
    def _save_patterns(self):
        """Save learned patterns to disk"""
        with open(self.patterns_file, 'w') as f:
            json.dump(self.learned_patterns, f, indent=2)
    
    def train_from_pnc_data(self, pnc_jsonl_file: str):
        """Train from PNC harvest data"""
        print(f"Training from {pnc_jsonl_file}...")
        
        count = 0
        with open(pnc_jsonl_file) as f:
            for line in f:
                if not line.strip():
                    continue
                
                build = json.loads(line)
                self._learn_from_build(build)
                count += 1
                
                if count % 100 == 0:
                    print(f"  Processed {count} builds...")
        
        self._save_patterns()
        print(f"✓ Trained on {count} builds")
        
        return count
    
    def _learn_from_build(self, build: Dict):
        """Learn patterns from a single build"""
        group_id = build.get('group_id')
        artifact_id = build.get('artifact_id')
        build_script = build.get('build_script', '')
        env_name = build.get('environment_name', '')
        env_id = build.get('environment_id')
        
        if not all([group_id, artifact_id]):
            return
        
        artifact_key = f"{group_id}:{artifact_id}"
        
        # Learn build script patterns
        if build_script:
            if artifact_key not in self.learned_patterns['build_scripts']:
                self.learned_patterns['build_scripts'][artifact_key] = []
            
            self.learned_patterns['build_scripts'][artifact_key].append({
                'script': build_script,
                'env_name': env_name,
                'env_id': env_id
            })
        
        # Learn environment preferences
        if env_name and env_id:
            if artifact_key not in self.learned_patterns['environments']:
                self.learned_patterns['environments'][artifact_key] = []
            
            self.learned_patterns['environments'][artifact_key].append({
                'name': env_name,
                'id': env_id
            })
        
        # Learn script templates (common patterns)
        if build_script:
            # Extract common patterns
            if 'mvn' in build_script.lower():
                template_key = 'maven_deploy'
            elif 'gradle' in build_script.lower():
                template_key = 'gradle_build'
            else:
                template_key = 'generic'
            
            if template_key not in self.learned_patterns['script_templates']:
                self.learned_patterns['script_templates'][template_key] = []
            
            self.learned_patterns['script_templates'][template_key].append(build_script)
        
        # Learn environment by JDK version
        if env_name:
            jdk_match = re.search(r'OpenJDK\s+([\d.]+)', env_name)
            if jdk_match:
                jdk_version = jdk_match.group(1)
                if jdk_version not in self.learned_patterns['env_by_jdk']:
                    self.learned_patterns['env_by_jdk'][jdk_version] = []
                
                self.learned_patterns['env_by_jdk'][jdk_version].append({
                    'name': env_name,
                    'id': env_id
                })
        
        # Learn environment by tool
        if env_name:
            if 'Mvn' in env_name:
                tool = 'maven'
            elif 'Gradle' in env_name:
                tool = 'gradle'
            else:
                tool = 'unknown'
            
            if tool not in self.learned_patterns['env_by_tool']:
                self.learned_patterns['env_by_tool'][tool] = []
            
            self.learned_patterns['env_by_tool'][tool].append({
                'name': env_name,
                'id': env_id
            })
    
    def predict_build_config(self, group_id: str, artifact_id: str, version: str) -> Optional[Dict]:
        """Predict complete build configuration"""
        artifact_key = f"{group_id}:{artifact_id}"
        
        # Get build script
        build_script = self._predict_build_script(artifact_key, group_id, artifact_id)
        
        # Get environment
        environment = self._predict_environment(artifact_key, build_script)
        
        if not build_script and not environment:
            return None
        
        return {
            'group_id': group_id,
            'artifact_id': artifact_id,
            'version': version,
            'build_script': build_script,
            'environment': environment,
            'confidence': self._calculate_confidence(artifact_key, build_script, environment)
        }
    
    def _predict_build_script(self, artifact_key: str, group_id: str, artifact_id: str) -> Optional[str]:
        """Predict build script"""
        # Check exact artifact match
        if artifact_key in self.learned_patterns['build_scripts']:
            scripts = self.learned_patterns['build_scripts'][artifact_key]
            if scripts:
                # Return most common script
                script_counts = Counter(s['script'] for s in scripts)
                return script_counts.most_common(1)[0][0]
        
        # Check group-level patterns
        group_scripts = []
        for key, scripts in self.learned_patterns['build_scripts'].items():
            if key.startswith(group_id + ':'):
                group_scripts.extend(s['script'] for s in scripts)
        
        if group_scripts:
            script_counts = Counter(group_scripts)
            return script_counts.most_common(1)[0][0]
        
        # Fallback to common templates
        if 'maven_deploy' in self.learned_patterns['script_templates']:
            scripts = self.learned_patterns['script_templates']['maven_deploy']
            if scripts:
                return Counter(scripts).most_common(1)[0][0]
        
        return None
    
    def _predict_environment(self, artifact_key: str, build_script: Optional[str]) -> Optional[Dict]:
        """Predict environment"""
        # Check exact artifact match
        if artifact_key in self.learned_patterns['environments']:
            envs = self.learned_patterns['environments'][artifact_key]
            if envs:
                # Return most common environment
                env_counts = Counter((e['name'], e['id']) for e in envs)
                most_common = env_counts.most_common(1)[0][0]
                return {'name': most_common[0], 'id': most_common[1]}
        
        # Infer from build script
        if build_script:
            if 'mvn' in build_script.lower():
                tool = 'maven'
            elif 'gradle' in build_script.lower():
                tool = 'gradle'
            else:
                tool = 'maven'  # default
            
            if tool in self.learned_patterns['env_by_tool']:
                envs = self.learned_patterns['env_by_tool'][tool]
                if envs:
                    env_counts = Counter((e['name'], e['id']) for e in envs)
                    most_common = env_counts.most_common(1)[0][0]
                    return {'name': most_common[0], 'id': most_common[1]}
        
        # Default to most common environment
        all_envs = []
        for envs in self.learned_patterns['environments'].values():
            all_envs.extend((e['name'], e['id']) for e in envs)
        
        if all_envs:
            env_counts = Counter(all_envs)
            most_common = env_counts.most_common(1)[0][0]
            return {'name': most_common[0], 'id': most_common[1]}
        
        return None
    
    def _calculate_confidence(self, artifact_key: str, build_script: Optional[str], environment: Optional[Dict]) -> float:
        """Calculate prediction confidence"""
        confidence = 0.0
        
        # Exact artifact match gives high confidence
        if artifact_key in self.learned_patterns['build_scripts']:
            confidence += 0.5
        
        if artifact_key in self.learned_patterns['environments']:
            confidence += 0.3
        
        # Having both script and environment (IMPROVED: 0.2 -> 0.5)
        if build_script and environment:
            confidence += 0.5  # Generic templates are reliable
        
        # Bonus for group-level patterns (NEW)
        group_id = artifact_key.split(':')[0]
        group_matches = sum(1 for key in self.learned_patterns['build_scripts'].keys() 
                           if key.startswith(group_id + ':'))
        if group_matches > 0:
            confidence += 0.2  # We've built similar artifacts
        
        return min(confidence, 1.0)
    
    def get_statistics(self) -> Dict:
        """Get learning statistics"""
        return {
            'learned_artifacts': len(self.learned_patterns['build_scripts']),
            'learned_environments': len(self.learned_patterns['environments']),
            'script_templates': len(self.learned_patterns['script_templates']),
            'jdk_versions': len(self.learned_patterns['env_by_jdk']),
            'tools': len(self.learned_patterns['env_by_tool'])
        }


if __name__ == '__main__':
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: build_config_learner.py <command> [args]", file=sys.stderr)
        print("Commands:", file=sys.stderr)
        print("  train <pnc_harvest.jsonl>", file=sys.stderr)
        print("  predict <group_id> <artifact_id> <version>", file=sys.stderr)
        print("  stats", file=sys.stderr)
        sys.exit(1)
    
    command = sys.argv[1]
    learner = BuildConfigLearner()
    
    if command == 'train':
        if len(sys.argv) < 3:
            print("Usage: train <pnc_harvest.jsonl>", file=sys.stderr)
            sys.exit(1)
        
        count = learner.train_from_pnc_data(sys.argv[2])
        stats = learner.get_statistics()
        print(f"\nStatistics:")
        print(f"  Learned artifacts: {stats['learned_artifacts']}")
        print(f"  Learned environments: {stats['learned_environments']}")
        print(f"  Script templates: {stats['script_templates']}")
    
    elif command == 'predict':
        if len(sys.argv) < 5:
            print("Usage: predict <group_id> <artifact_id> <version>", file=sys.stderr)
            sys.exit(1)
        
        result = learner.predict_build_config(sys.argv[2], sys.argv[3], sys.argv[4])
        if result:
            print(json.dumps(result, indent=2))
        else:
            print("No prediction available", file=sys.stderr)
            sys.exit(1)
    
    elif command == 'stats':
        stats = learner.get_statistics()
        print(json.dumps(stats, indent=2))
    
    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)
