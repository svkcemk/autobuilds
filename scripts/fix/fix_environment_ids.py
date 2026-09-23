#!/usr/bin/env python3
"""
Fix environment format - replace environmentName with environmentId
"""

import sys
import re
from pathlib import Path

# PNC Environment IDs (from reference config)
ENVIRONMENT_IDS = {
    'OpenJDK 11.0; Mvn 3.8.6': 316,
    'OpenJDK 17.0; Mvn 3.9.1': 316,  # Using same ID, adjust if different
}

def fix_environment_in_file(file_path: Path):
    """Replace environmentName with environmentId"""
    
    with open(file_path) as f:
        content = f.read()
    
    # Replace environmentName: "..." with environmentId: <id>
    def replace_env(match):
        env_name = match.group(1)
        env_id = ENVIRONMENT_IDS.get(env_name, 316)  # Default to 316
        return f'  environmentId: {env_id}'
    
    new_content = re.sub(
        r'  environmentName: "([^"]+)"',
        replace_env,
        content
    )
    
    changes = content.count('environmentName:')
    
    if changes > 0:
        with open(file_path, 'w') as f:
            f.write(new_content)
    
    return changes

if __name__ == '__main__':
    batch_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('output-camel-4.22-bacon-batches')
    
    total_changes = 0
    for batch_subdir in sorted(batch_dir.glob('*/')):
        config_file = batch_subdir / 'build-config.yaml'
        if config_file.exists():
            print(f"Processing {batch_subdir.name}...", end=' ')
            changes = fix_environment_in_file(config_file)
            total_changes += changes
            if changes > 0:
                print(f"✓ Fixed {changes} environment references")
            else:
                print("No changes needed")
    
    print(f"\nTotal environment references fixed: {total_changes}")
