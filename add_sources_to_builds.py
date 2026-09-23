#!/usr/bin/env python3
"""
Add source JAR generation to all build scripts
"""

import sys
import re
from pathlib import Path

def add_sources_to_batch(batch_file: Path):
    """Add source JAR generation to all build scripts in batch file"""
    
    with open(batch_file) as f:
        content = f.read()
    
    # Pattern to match buildScript sections
    # Look for: buildScript: |\n    <commands>
    pattern = r'(buildScript: \|\n)((?:    .*\n)+)'
    
    def add_sources(match):
        header = match.group(1)
        script_lines = match.group(2)
        
        # Check if sources are already included
        if 'source:jar' in script_lines or 'maven-source-plugin' in script_lines:
            return match.group(0)
        
        # Add source:jar goal before deploy
        # Replace 'mvn deploy' or 'mvn ... deploy' with 'mvn ... source:jar deploy'
        modified_script = re.sub(
            r'(mvn\s+(?:.*?\s+)?)(deploy)',
            r'\1source:jar \2',
            script_lines
        )
        
        return header + modified_script
    
    new_content = re.sub(pattern, add_sources, content)
    
    # Count modifications
    modifications = len(re.findall(r'source:jar', new_content)) - len(re.findall(r'source:jar', content))
    
    if modifications > 0:
        with open(batch_file, 'w') as f:
            f.write(new_content)
    
    return modifications

if __name__ == '__main__':
    batch_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('output-camel-4.22-pnc-batches')
    
    total_modified = 0
    for batch_file in sorted(batch_dir.glob('*.yaml')):
        print(f"Processing {batch_file.name}...", end=' ')
        count = add_sources_to_batch(batch_file)
        total_modified += count
        if count > 0:
            print(f"✓ Added source:jar to {count} builds")
        else:
            print("Already has sources or no changes needed")
    
    print(f"\nTotal builds modified: {total_modified}")
