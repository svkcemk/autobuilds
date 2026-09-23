#!/usr/bin/env python3
"""
Unified Build Config Predictor
Combines SCM resolution with build script and environment prediction
"""

import json
import sys
from pathlib import Path

# Import both learners
sys.path.insert(0, str(Path(__file__).parent))
from scm_pattern_learner import SCMPatternLearner
from build_config_learner import BuildConfigLearner
from url_transformer import URLTransformer


class UnifiedPredictor:
    """Unified predictor for complete build configurations"""
    
    def __init__(self):
        self.scm_learner = SCMPatternLearner()
        self.build_learner = BuildConfigLearner()
    
    def predict_complete_config(self, group_id: str, artifact_id: str, version: str) -> dict:
        """Predict complete build configuration including SCM, script, and environment"""
        
        # Get SCM prediction
        scm_result = self.scm_learner.predict_scm(group_id, artifact_id, version, verify_urls=False)
        
        # Get build config prediction
        build_result = self.build_learner.predict_build_config(group_id, artifact_id, version)
        
        # Combine results
        result = {
            'artifact': {
                'group_id': group_id,
                'artifact_id': artifact_id,
                'version': version
            },
            'scm': None,
            'build_config': None,
            'overall_confidence': 0.0
        }
        
        if scm_result:
            # Transform downstream URLs to upstream
            scm_url = scm_result['scm_url']
            if URLTransformer.is_downstream_url(scm_url):
                scm_url = URLTransformer.transform_to_upstream(scm_url)
            
            result['scm'] = {
                'url': scm_url,
                'revision': scm_result['scm_revision'],
                'confidence': scm_result['confidence'],
                'method': scm_result['method']
            }
        
        if build_result:
            result['build_config'] = {
                'build_script': build_result['build_script'],
                'environment': build_result['environment'],
                'confidence': build_result['confidence']
            }
        
        # Calculate overall confidence
        confidences = []
        if scm_result:
            confidences.append(scm_result['confidence'])
        if build_result:
            confidences.append(build_result['confidence'])
        
        if confidences:
            result['overall_confidence'] = sum(confidences) / len(confidences)
        
        return result
    
    def format_for_yaml(self, prediction: dict) -> str:
        """Format prediction as YAML build config"""
        lines = []
        
        artifact = prediction['artifact']
        lines.append(f"# Build config for {artifact['group_id']}:{artifact['artifact_id']}:{artifact['version']}")
        lines.append(f"# Overall confidence: {prediction['overall_confidence']:.0%}")
        lines.append("")
        
        lines.append("name: " + f"{artifact['artifact_id']}-{artifact['version']}")
        lines.append(f"project: {artifact['group_id']}")
        lines.append("")
        
        if prediction['scm']:
            scm = prediction['scm']
            lines.append("scmRepository:")
            lines.append(f"  url: {scm['url']}")
            lines.append(f"scmRevision: {scm['revision']}")
            lines.append(f"# SCM confidence: {scm['confidence']:.0%}, method: {scm['method']}")
            lines.append("")
        
        if prediction['build_config']:
            config = prediction['build_config']
            if config['environment']:
                env = config['environment']
                lines.append("environment:")
                lines.append(f"  id: {env['id']}")
                lines.append(f"  name: {env['name']}")
                lines.append("")
            
            if config['build_script']:
                lines.append("buildScript: |")
                for line in config['build_script'].split('\n'):
                    lines.append(f"  {line}")
                lines.append(f"# Build config confidence: {config['confidence']:.0%}")
        
        return '\n'.join(lines)


if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("Usage: unified_predictor.py <group_id> <artifact_id> <version> [--yaml]", file=sys.stderr)
        print("Example: unified_predictor.py com.google.protobuf protobuf-java 4.34.2", file=sys.stderr)
        sys.exit(1)
    
    group_id = sys.argv[1]
    artifact_id = sys.argv[2]
    version = sys.argv[3]
    output_yaml = '--yaml' in sys.argv
    
    predictor = UnifiedPredictor()
    result = predictor.predict_complete_config(group_id, artifact_id, version)
    
    if output_yaml:
        print(predictor.format_for_yaml(result))
    else:
        print(json.dumps(result, indent=2))
