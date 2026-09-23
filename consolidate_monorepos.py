#!/usr/bin/env python3
"""
Consolidate monorepo artifacts into single build configs
"""

import sys
import re
from pathlib import Path
from collections import defaultdict

# Known monorepos - one build produces multiple artifacts
MONOREPOS = {
    'ca.uhn.hapi.fhir': {
        'name': 'hapifhir-hapi-fhir-8.10.1-AUTOBUILD',
        'scmUrl': 'https://github.com/hapifhir/hapi-fhir.git',
        'scmRevision': 'v8.10.1',
        'project': 'hapifhir/hapi-fhir',
        'description': 'HAPI FHIR - monorepo build producing all FHIR modules',
        'artifacts': [
            'ca.uhn.hapi.fhir:hapi-fhir-base:8.10.1',
            'ca.uhn.hapi.fhir:hapi-fhir-client:8.10.1',
            'ca.uhn.hapi.fhir:hapi-fhir-structures-dstu2:8.10.1',
            'ca.uhn.hapi.fhir:hapi-fhir-structures-dstu2.1:8.10.1',
            'ca.uhn.hapi.fhir:hapi-fhir-structures-dstu3:8.10.1',
            'ca.uhn.hapi.fhir:hapi-fhir-structures-hl7org-dstu2:8.10.1',
            'ca.uhn.hapi.fhir:hapi-fhir-structures-r4:8.10.1',
            'ca.uhn.hapi.fhir:hapi-fhir-structures-r5:8.10.1',
        ]
    },
    'ai.djl': {
        'name': 'deepjavalibrary-djl-0.36.0-AUTOBUILD',
        'scmUrl': 'https://github.com/deepjavalibrary/djl.git',
        'scmRevision': 'v0.36.0',
        'project': 'deepjavalibrary/djl',
        'description': 'Deep Java Library - monorepo build producing all DJL modules',
        'artifacts': [
            'ai.djl:api:0.36.0',
            'ai.djl.huggingface:tokenizers:0.36.0',
            'ai.djl.timeseries:timeseries:0.36.0',
        ]
    },
    'software.amazon.awssdk': {
        'name': 'aws-aws-sdk-java-v2-2.50.2-AUTOBUILD',
        'scmUrl': 'https://github.com/aws/aws-sdk-java-v2.git',
        'scmRevision': '2.50.2',
        'project': 'aws/aws-sdk-java-v2',
        'description': 'AWS SDK for Java v2 - monorepo build producing all AWS modules',
        'artifacts': []  # Will be populated from batch files
    }
}

def consolidate_batch(batch_file: Path):
    """Consolidate monorepo builds in a batch file"""
    
    with open(batch_file) as f:
        content = f.read()
    
    # Track which artifacts to remove
    artifacts_to_remove = set()
    monorepo_builds = {}
    
    # Find all builds
    build_pattern = r'- name: "([^"]+)".*?(?=- name:|$)'
    builds = list(re.finditer(build_pattern, content, re.DOTALL))
    
    # Identify monorepo artifacts
    for build in builds:
        name = build.group(1)
        
        # Check if this is a monorepo artifact
        for group_prefix, monorepo_info in MONOREPOS.items():
            if name.startswith(group_prefix.replace('.', '-')):
                artifacts_to_remove.add(name)
                
                # Track this monorepo
                if group_prefix not in monorepo_builds:
                    monorepo_builds[group_prefix] = monorepo_info.copy()
    
    if not artifacts_to_remove:
        return 0
    
    # Remove individual artifact builds
    new_content = content
    for build in builds:
        name = build.group(1)
        if name in artifacts_to_remove:
            new_content = new_content.replace(build.group(0), '')
    
    # Add consolidated monorepo builds
    builds_section = []
    for group_prefix, info in monorepo_builds.items():
        build_entry = f'''- name: "{info['name']}"
  project: "{info['project']}"
  buildType: "MVN"
  scmUrl: "{info['scmUrl']}"
  scmRevision: "{info['scmRevision']}"
  environmentName: "OpenJDK 11.0; Mvn 3.8.6"
  buildScript: |
    mvn deploy -DrpmDeploymentRepository="indy-mvn::default::${{AProxDeployUrl}}"
  description: "{info['description']}"

'''
        builds_section.append(build_entry)
    
    # Insert consolidated builds after the "builds:" line
    builds_marker = 'builds:\n'
    if builds_marker in new_content:
        parts = new_content.split(builds_marker, 1)
        new_content = parts[0] + builds_marker + ''.join(builds_section) + parts[1]
    
    # Write back
    with open(batch_file, 'w') as f:
        f.write(new_content)
    
    return len(artifacts_to_remove)

if __name__ == '__main__':
    batch_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('output-camel-4.22-pnc-batches')
    
    total_consolidated = 0
    for batch_file in sorted(batch_dir.glob('*.yaml')):
        print(f"Processing {batch_file.name}...", end=' ')
        count = consolidate_batch(batch_file)
        total_consolidated += count
        if count > 0:
            print(f"✓ Consolidated {count} artifacts into monorepo builds")
        else:
            print("No monorepo artifacts found")
    
    print(f"\nTotal artifacts consolidated: {total_consolidated}")
