#!/usr/bin/env python3
"""
Add dependency relationships to PNC batch configs
"""

import sys
import re
from pathlib import Path

def analyze_dependencies(artifacts):
    """
    Analyze dependencies based on common patterns
    Returns dict of artifact -> list of dependency names
    """
    deps = {}
    artifact_names = {}
    
    # Build name mapping
    for artifact in artifacts:
        parts = artifact.split(':')
        if len(parts) >= 3:
            group_id, artifact_id, version = parts[0], parts[1], parts[2]
            name = f"{group_id.replace('.', '-')}-{artifact_id}-{version}-AUTOBUILD"
            artifact_names[artifact] = name
    
    # Define dependency patterns
    for artifact in artifacts:
        parts = artifact.split(':')
        if len(parts) < 3:
            continue
            
        group_id = parts[0]
        artifact_id = parts[1]
        artifact_deps = []
        
        # AWS SDK dependencies
        if group_id == 'software.amazon.awssdk':
            # All AWS SDK modules depend on core modules
            for core in ['aws-core', 'sdk-core', 'auth', 'regions']:
                core_gav = f"software.amazon.awssdk:{core}:{parts[2]}"
                if core_gav in artifact_names and core_gav != artifact:
                    artifact_deps.append(artifact_names[core_gav])
        
        # Azure SDK dependencies
        elif group_id == 'com.azure':
            core_gav = f"com.azure:azure-core:{parts[2]}"
            if core_gav in artifact_names and core_gav != artifact:
                artifact_deps.append(artifact_names[core_gav])
        
        # Google Cloud dependencies
        elif group_id.startswith('com.google.cloud'):
            for core in ['google-cloud-core', 'gax']:
                core_gav = f"com.google.api:gax:{parts[2]}"
                if core_gav in artifact_names and core_gav != artifact:
                    artifact_deps.append(artifact_names[core_gav])
        
        # Apache HttpComponents
        elif group_id == 'org.apache.httpcomponents.client5':
            core_gav = f"org.apache.httpcomponents.core5:httpcore5:{parts[2]}"
            if core_gav in artifact_names and core_gav != artifact:
                artifact_deps.append(artifact_names[core_gav])
        
        if artifact_deps:
            deps[artifact] = artifact_deps
    
    return deps

def add_dependencies_to_batch(batch_file):
    """Add dependencies field to builds in batch file"""
    
    # Read batch file
    with open(batch_file) as f:
        content = f.read()
    
    # Extract artifacts from batch
    artifacts = []
    for match in re.finditer(r'- name: "([^"]+)"', content):
        name = match.group(1)
        # Extract GAV from name (reverse the naming convention)
        # Format: groupId-artifactId-version-AUTOBUILD
        parts = name.replace('-AUTOBUILD', '').rsplit('-', 1)
        if len(parts) == 2:
            artifact_version = parts[1]
            group_artifact = parts[0].rsplit('-', 1)
            if len(group_artifact) == 2:
                group_id = group_artifact[0].replace('-', '.')
                artifact_id = group_artifact[1]
                gav = f"{group_id}:{artifact_id}:{artifact_version}"
                artifacts.append(gav)
    
    # Analyze dependencies
    deps = analyze_dependencies(artifacts)
    
    # Add dependencies to content
    modified_content = content
    for artifact, dep_list in deps.items():
        parts = artifact.split(':')
        if len(parts) >= 3:
            group_id, artifact_id, version = parts[0], parts[1], parts[2]
            name = f"{group_id.replace('.', '-')}-{artifact_id}-{version}-AUTOBUILD"
            
            # Find the build entry and add dependencies
            pattern = f'(- name: "{name}".*?description: "[^"]*")'
            
            def add_deps(match):
                build_entry = match.group(1)
                deps_yaml = "\n  dependencies:"
                for dep_name in dep_list:
                    deps_yaml += f'\n  - "{dep_name}"'
                return build_entry + deps_yaml
            
            modified_content = re.sub(pattern, add_deps, modified_content, flags=re.DOTALL)
    
    # Write back
    with open(batch_file, 'w') as f:
        f.write(modified_content)
    
    return len(deps)

if __name__ == '__main__':
    batch_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('output-camel-4.22-pnc-batches')
    
    total_deps = 0
    for batch_file in sorted(batch_dir.glob('*.yaml')):
        print(f"Processing {batch_file.name}...")
        count = add_dependencies_to_batch(batch_file)
        total_deps += count
        if count > 0:
            print(f"  Added dependencies to {count} artifacts")
    
    print(f"\nTotal artifacts with dependencies: {total_deps}")
