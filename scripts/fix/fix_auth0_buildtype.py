#!/usr/bin/env python3
"""
Fix auth0 buildType from GRADLE to MVN and update build script
"""

import sys
import re
from pathlib import Path

def fix_auth0_in_file(file_path: Path):
    """Fix auth0 buildType and build script"""
    
    with open(file_path) as f:
        content = f.read()
    
    # Pattern to match auth0 build entry
    pattern = r'(- name: "com-auth0-java-jwt[^"]*".*?buildType: ")GRADLE(".*?buildScript: \|.*?)(gradle[^\n]+)'
    
    def fix_auth0(match):
        prefix = match.group(1)
        middle = match.group(2)
        old_script = match.group(3)
        
        # Replace with MVN build
        new_script = 'mvn source:jar deploy -DrpmDeploymentRepository="indy-mvn::default::${AProxDeployUrl}"'
        return f'{prefix}MVN{middle}    {new_script}'
    
    new_content = re.sub(pattern, fix_auth0, content, flags=re.DOTALL)
    
    changes = content != new_content
    
    if changes:
        with open(file_path, 'w') as f:
            f.write(new_content)
    
    return changes

if __name__ == '__main__':
    batch_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('output-camel-4.22-bacon-batches')
    
    total_fixes = 0
    for batch_subdir in sorted(batch_dir.glob('*/')):
        config_file = batch_subdir / 'build-config.yaml'
        if config_file.exists():
            if fix_auth0_in_file(config_file):
                print(f"✓ Fixed auth0 in {batch_subdir.name}")
                total_fixes += 1
    
    print(f"\nTotal files fixed: {total_fixes}")
