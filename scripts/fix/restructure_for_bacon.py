#!/usr/bin/env python3
"""
Restructure batch files for bacon PIG format
Bacon expects: batch-dir/build-config.yaml
"""

import sys
import shutil
from pathlib import Path

def restructure_batch(batch_file: Path, output_dir: Path):
    """Convert single YAML to bacon PIG directory structure"""
    
    # Extract batch name (e.g., camel-4.22-pnc-batch-001)
    batch_name = batch_file.stem
    
    # Create batch directory
    batch_dir = output_dir / batch_name
    batch_dir.mkdir(parents=True, exist_ok=True)
    
    # Copy YAML as build-config.yaml
    shutil.copy(batch_file, batch_dir / 'build-config.yaml')
    
    return batch_dir

if __name__ == '__main__':
    input_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('output-camel-4.22-pnc-batches')
    output_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path('output-camel-4.22-bacon-batches')
    
    output_dir.mkdir(parents=True, exist_ok=True)
    
    batch_count = 0
    for batch_file in sorted(input_dir.glob('*.yaml')):
        print(f"Restructuring {batch_file.name}...", end=' ')
        batch_dir = restructure_batch(batch_file, output_dir)
        batch_count += 1
        print(f"✓ Created {batch_dir.name}/")
    
    print(f"\nTotal batches restructured: {batch_count}")
    print(f"Output directory: {output_dir}")
    print()
    print("Usage:")
    print(f"  bacon pig run {output_dir}/camel-4.22-pnc-batch-001")
