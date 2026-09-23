#!/usr/bin/env python3
"""
PNC Build Config Generator - Generates PNC-compatible build configurations
Follows the format from https://gitlab.cee.redhat.com/soghosh/build-configurations
"""

import sys
import json
from pathlib import Path
from typing import Dict, Optional

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from scm_pattern_learner import SCMPatternLearner
from build_config_learner import BuildConfigLearner
from url_transformer import URLTransformer


class PNCConfigGenerator:
    """Generate PNC-compatible build configurations"""
    
    def __init__(self):
        self.scm_learner = SCMPatternLearner()
        self.build_learner = BuildConfigLearner()
    
    def generate_config(self, group_id: str, artifact_id: str, version: str) -> Optional[Dict]:
        """Generate complete PNC build configuration"""
        
        # Get SCM prediction
        scm_result = self.scm_learner.predict_scm(group_id, artifact_id, version, verify_urls=False)
        
        # Get build config prediction
        build_result = self.build_learner.predict_build_config(group_id, artifact_id, version)
        
        if not scm_result:
            return None
        
        # Transform downstream URLs to upstream
        scm_url = scm_result['scm_url']
        if URLTransformer.is_downstream_url(scm_url):
            scm_url = URLTransformer.transform_to_upstream(scm_url)
        
        # Determine build type
        build_type = self._detect_build_type(group_id, artifact_id, build_result)
        
        # Get environment name (not ID)
        environment_name = self._get_environment_name(group_id, artifact_id, build_result, build_type)
        
        # Get build script
        build_script = self._get_build_script(group_id, artifact_id, build_result, build_type)
        
        # Generate PNC-compatible name
        name = self._generate_name(group_id, artifact_id, version)
        
        # Generate project path
        project = self._generate_project(group_id, artifact_id, scm_url)
        
        # Calculate overall confidence
        scm_confidence = scm_result['confidence']
        build_confidence = build_result['confidence'] if build_result else 0.5
        overall_confidence = (scm_confidence + build_confidence) / 2
        
        return {
            'name': name,
            'project': project,
            'buildScript': build_script,
            'scmUrl': scm_url,
            'scmRevision': scm_result['scm_revision'],
            'environmentName': environment_name,
            'buildType': build_type,
            'description': f"Auto-generated build config for {group_id}:{artifact_id}:{version}",
            '_metadata': {
                'overall_confidence': overall_confidence,
                'scm_confidence': scm_confidence,
                'build_confidence': build_confidence,
                'scm_method': scm_result['method']
            }
        }
    
    def _detect_build_type(self, group_id: str, artifact_id: str, build_result: Optional[Dict]) -> str:
        """Detect build type (MVN or GRADLE)"""
        if build_result and build_result.get('build_script'):
            script = build_result['build_script'].lower()
            if 'gradle' in script:
                return 'GRADLE'
        
        # Default to Maven (most common in Java ecosystem)
        return 'MVN'
    
    def _get_environment_name(self, group_id: str, artifact_id: str, 
                             build_result: Optional[Dict], build_type: str) -> str:
        """Get environment name based on artifact and build type"""
        
        # Infer from group_id patterns FIRST (more accurate than generic learned patterns)
        group_lower = group_id.lower()
        
        # Spring Boot / Spring Framework - typically needs Java 17+
        if 'springframework' in group_lower or 'spring' in artifact_id.lower():
            return "OpenJDK 17.0; Mvn 3.9.1"
        
        # Quarkus - needs Java 17+
        if 'quarkus' in group_lower or 'quarkus' in artifact_id.lower():
            return "OpenJDK 17.0; Mvn 3.9.1"
        
        # AWS SDK v2 - needs Java 8+
        if 'amazon' in group_lower or 'aws' in group_lower:
            return "OpenJDK 11.0; Mvn 3.8.6"
        
        # Azure SDK - needs Java 8+
        if 'azure' in group_lower or 'microsoft' in group_lower:
            return "OpenJDK 11.0; Mvn 3.8.6"
        
        # Google Cloud - needs Java 8+
        if 'google' in group_lower or 'googleapis' in group_lower:
            return "OpenJDK 11.0; Mvn 3.8.6"
        
        # Apache projects - typically Java 8 or 11
        if 'apache' in group_lower:
            # Newer Apache projects use Java 11+
            if any(x in artifact_id.lower() for x in ['camel', 'kafka', 'flink', 'spark']):
                return "OpenJDK 11.0; Mvn 3.8.6"
            return "OpenJDK 1.8; Mvn 3.6.3"
        
        # Eclipse projects - typically Java 11+
        if 'eclipse' in group_lower:
            return "OpenJDK 11.0; Mvn 3.8.6"
        
        # Netty - Java 8+
        if 'netty' in group_lower:
            return "OpenJDK 11.0; Mvn 3.8.6"
        
        # Gradle builds
        if build_type == 'GRADLE':
            return "OpenJDK 11.0; Gradle 7.6"
        
        # Default: Java 11 with Maven 3.8.6 (most common modern setup)
        return "OpenJDK 11.0; Mvn 3.8.6"
    
    def _get_build_script(self, group_id: str, artifact_id: str, 
                         build_result: Optional[Dict], build_type: str) -> str:
        """Get build script based on build type and learned patterns"""
        
        # If we have learned script, use it
        if build_result and build_result.get('build_script'):
            return build_result['build_script']
        
        # Generate appropriate script based on build type
        if build_type == 'GRADLE':
            return 'gradle publish -x test -x javadoc --stacktrace'
        
        # Maven default with common flags
        return 'mvn clean deploy -DskipTests -Denforcer.skip -Dgpg.skip'
    
    def _generate_name(self, group_id: str, artifact_id: str, version: str) -> str:
        """Generate PNC build config name following convention"""
        # Convert group_id dots to hyphens
        group_part = group_id.replace('.', '-')
        
        # Format: groupId-artifactId-version-AUTOBUILD
        return f"{group_part}-{artifact_id}-{version}-AUTOBUILD"
    
    def _generate_project(self, group_id: str, artifact_id: str, scm_url: str) -> str:
        """Generate project path from SCM URL"""
        # Extract org/repo from GitHub URL
        # Example: https://github.com/aws/aws-sdk-java-v2.git -> aws/aws-sdk-java-v2
        
        if 'github.com' in scm_url:
            parts = scm_url.split('github.com/')
            if len(parts) > 1:
                repo_path = parts[1].replace('.git', '')
                return repo_path
        
        # Fallback: use group_id/artifact_id
        org = group_id.split('.')[0] if '.' in group_id else group_id
        return f"{org}/{artifact_id}"
    
    def format_as_yaml(self, config: Dict) -> str:
        """Format configuration as YAML for PNC"""
        metadata = config.pop('_metadata', {})
        
        lines = []
        lines.append(f"# Build config for {config.get('description', 'artifact')}")
        lines.append(f"# Overall confidence: {metadata.get('overall_confidence', 0):.0%}")
        lines.append(f"# SCM confidence: {metadata.get('scm_confidence', 0):.0%}, method: {metadata.get('scm_method', 'unknown')}")
        lines.append(f"# Build confidence: {metadata.get('build_confidence', 0):.0%}")
        lines.append("")
        
        # Required fields in PNC format
        lines.append(f"name: \"{config['name']}\"")
        lines.append(f"project: \"{config['project']}\"")
        lines.append(f"buildType: \"{config['buildType']}\"")
        lines.append(f"scmUrl: \"{config['scmUrl']}\"")
        lines.append(f"scmRevision: \"{config['scmRevision']}\"")
        lines.append(f"environmentName: \"{config['environmentName']}\"")
        lines.append("")
        
        # Build script (multiline)
        lines.append("buildScript: |")
        for line in config['buildScript'].split('\n'):
            lines.append(f"  {line}")
        lines.append("")
        
        # Optional description
        if config.get('description'):
            lines.append(f"description: \"{config['description']}\"")
        
        return '\n'.join(lines)


if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("Usage: pnc_config_generator.py <group_id> <artifact_id> <version> [--yaml]", file=sys.stderr)
        print("Example: pnc_config_generator.py software.amazon.awssdk s3 2.50.2 --yaml", file=sys.stderr)
        sys.exit(1)
    
    group_id = sys.argv[1]
    artifact_id = sys.argv[2]
    version = sys.argv[3]
    output_yaml = '--yaml' in sys.argv
    
    generator = PNCConfigGenerator()
    config = generator.generate_config(group_id, artifact_id, version)
    
    if not config:
        print("Failed to generate configuration", file=sys.stderr)
        sys.exit(1)
    
    if output_yaml:
        print(generator.format_as_yaml(config))
    else:
        print(json.dumps(config, indent=2))
