#!/usr/bin/env python3
"""
Fix SCM URLs in PNC batch files using known corrections
"""

import sys
import re
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent / 'lib' / 'ai'))

from scm_corrections import get_scm_info

def fix_batch_file(batch_file: Path):
    """Fix SCM URLs in a batch file"""
    
    with open(batch_file) as f:
        content = f.read()
    
    # Find all build entries
    build_pattern = r'- name: "([^"]+)"\s+project: "([^"]+)"\s+buildType: "([^"]+)"\s+scmUrl: "([^"]+)"\s+scmRevision: "([^"]+)"'
    
    fixes_made = 0
    
    def fix_build(match):
        nonlocal fixes_made
        name = match.group(1)
        project = match.group(2)
        build_type = match.group(3)
        old_scm_url = match.group(4)
        old_scm_rev = match.group(5)
        
        # Extract GAV from name (format: groupId-artifactId-version-AUTOBUILD)
        name_parts = name.replace('-AUTOBUILD', '').rsplit('-', 1)
        if len(name_parts) != 2:
            return match.group(0)
        
        version = name_parts[1]
        group_artifact = name_parts[0].rsplit('-', 1)
        if len(group_artifact) != 2:
            return match.group(0)
        
        group_id = group_artifact[0].replace('-', '.')
        artifact_id = group_artifact[1]
        
        # Get correct SCM info
        scm_info = get_scm_info(group_id, artifact_id, version)
        
        if scm_info:
            new_scm_url = scm_info['scmUrl']
            new_scm_rev = scm_info['scmRevision']
            
            # Extract project from SCM URL
            new_project = new_scm_url.replace('https://github.com/', '').replace('.git', '')
            
            if new_scm_url != old_scm_url or new_scm_rev != old_scm_rev:
                fixes_made += 1
                return f'- name: "{name}"\n  project: "{new_project}"\n  buildType: "{build_type}"\n  scmUrl: "{new_scm_url}"\n  scmRevision: "{new_scm_rev}"'
        
        return match.group(0)
    
    # Apply fixes
    new_content = re.sub(build_pattern, fix_build, content)
    
    if fixes_made > 0:
        with open(batch_file, 'w') as f:
            f.write(new_content)
    
    return fixes_made

if __name__ == '__main__':
    batch_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('output-camel-4.22-pnc-batches')
    
    total_fixes = 0
    for batch_file in sorted(batch_dir.glob('*.yaml')):
        print(f"Processing {batch_file.name}...", end=' ')
        fixes = fix_batch_file(batch_file)
        total_fixes += fixes
        if fixes > 0:
            print(f"✓ Fixed {fixes} SCM URLs")
        else:
            print("No changes needed")
    
    print(f"\nTotal SCM URLs fixed: {total_fixes}")
