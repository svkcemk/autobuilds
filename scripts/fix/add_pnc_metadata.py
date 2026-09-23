#!/usr/bin/env python3
"""
Add missing PNC metadata fields to batch configs
"""

import sys
from pathlib import Path

# PNC metadata template
PNC_METADATA = """
outputPrefixes:
  releaseFile: "camel-4.22-third-party"
  releaseDir: "camel-4.22-third-party"
flow:
  licensesGeneration:
    strategy: "IGNORE"
  repositoryGeneration:
    strategy: "IGNORE"
    additionalArtifacts: []
    externalAdditionalArtifacts: []
    externalAdditionalConfigs: []
    excludeArtifacts: []
    sourceBuilds: []
    excludeSourceBuilds: []
    filterArtifacts: []
    includeJavadoc: false
    includeLicenses: false
    includeMavenMetadata: false
    ignored: []
    stages: []
    parameters: {}
    steps: []
  javadocGeneration:
    strategy: "IGNORE"
    sourceBuilds: []
    customPmeParameters: []
    alignmentParameters: []
  sourcesGeneration:
    strategy: "IGNORE"
    sourceBuild: null
    sourceArtifact: null
    whitelistedArtifacts: []
    additionalExternalSources: []
    excludeSourceBuilds: []
addons:
  notYetAlignedFromDependencyTree: null
draft: true
"""

def add_metadata_to_batch(batch_file: Path):
    """Add PNC metadata to batch file"""
    
    with open(batch_file) as f:
        content = f.read()
    
    # Check if metadata already exists
    if 'outputPrefixes:' in content:
        return False
    
    # Append metadata at the end
    new_content = content.rstrip() + '\n' + PNC_METADATA
    
    with open(batch_file, 'w') as f:
        f.write(new_content)
    
    return True

if __name__ == '__main__':
    batch_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('output-camel-4.22-pnc-batches')
    
    total_modified = 0
    for batch_file in sorted(batch_dir.glob('*.yaml')):
        print(f"Processing {batch_file.name}...", end=' ')
        modified = add_metadata_to_batch(batch_file)
        if modified:
            total_modified += 1
            print("✓ Added PNC metadata")
        else:
            print("Already has metadata")
    
    print(f"\nTotal files modified: {total_modified}")
