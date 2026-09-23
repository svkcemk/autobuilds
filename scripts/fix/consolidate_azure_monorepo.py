#!/usr/bin/env python3
"""
Consolidate Azure SDK artifacts into single monorepo build
"""

import sys
import re
from pathlib import Path

# Azure SDK monorepo configuration
AZURE_MONOREPO = {
    'name': 'azure-azure-sdk-for-java-AUTOBUILD',
    'scmUrl': 'https://github.com/Azure/azure-sdk-for-java.git',
    'scmRevision': 'main',  # Use main branch or specific release tag
    'project': 'Azure/azure-sdk-for-java',
    'description': 'Azure SDK for Java - monorepo build producing all Azure modules',
    'buildScript': '''cd sdk
mvn -B -Danimal.sniffer.skip -Dcheckstyle.skip -Dcodesnippet.skip -Denforcer.skip -Djacoco.skip -Drevapi.skip -DskipTests -Dspotbugs.skip -Dspotless.skip clean source:jar deploy''',
    'artifacts': []  # Will be populated
}

def consolidate_batch(batch_file: Path):
    """Consolidate Azure SDK builds in a batch file"""
    
    with open(batch_file) as f:
        content = f.read()
    
    # Track which artifacts to remove
    artifacts_to_remove = set()
    has_azure = False
    
    # Find all builds
    build_pattern = r'- name: "([^"]+)".*?(?=- name:|outputPrefixes:)'
    builds = list(re.finditer(build_pattern, content, re.DOTALL))
    
    # Identify Azure artifacts
    for build in builds:
        name = build.group(1)
        if name.startswith('com-azure-'):
            artifacts_to_remove.add(name)
            has_azure = True
    
    if not has_azure:
        return 0
    
    # Remove individual Azure artifact builds
    new_content = content
    for build in builds:
        name = build.group(1)
        if name in artifacts_to_remove:
            new_content = new_content.replace(build.group(0), '')
    
    # Add consolidated Azure monorepo build
    azure_build = f'''- name: "{AZURE_MONOREPO['name']}"
  project: "{AZURE_MONOREPO['project']}"
  buildType: "MVN"
  scmUrl: "{AZURE_MONOREPO['scmUrl']}"
  scmRevision: "{AZURE_MONOREPO['scmRevision']}"
  environmentId: 316
  buildScript: |
    {AZURE_MONOREPO['buildScript']}
  description: "{AZURE_MONOREPO['description']}"

'''
    
    # Insert consolidated build after the "builds:" line
    builds_marker = 'builds:\n'
    if builds_marker in new_content:
        parts = new_content.split(builds_marker, 1)
        new_content = parts[0] + builds_marker + azure_build + parts[1]
    
    # Write back
    with open(batch_file, 'w') as f:
        f.write(new_content)
    
    return len(artifacts_to_remove)

if __name__ == '__main__':
    batch_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('output-camel-4.22-bacon-batches')
    
    total_consolidated = 0
    for batch_subdir in sorted(batch_dir.glob('*/')):
        batch_file = batch_subdir / 'build-config.yaml'
        if batch_file.exists():
            print(f"Processing {batch_subdir.name}...", end=' ')
            count = consolidate_batch(batch_file)
            total_consolidated += count
            if count > 0:
                print(f"✓ Consolidated {count} Azure artifacts")
            else:
                print("No Azure artifacts found")
    
    print(f"\nTotal Azure artifacts consolidated: {total_consolidated}")
