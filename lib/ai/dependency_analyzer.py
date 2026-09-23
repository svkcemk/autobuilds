#!/usr/bin/env python3
"""
Dependency Analyzer - Analyzes Maven dependencies between artifacts
"""

import sys
import json
import subprocess
from pathlib import Path
from typing import Dict, List, Set, Optional
import xml.etree.ElementTree as ET


class DependencyAnalyzer:
    """Analyze Maven dependencies for build ordering"""
    
    def __init__(self):
        self.artifact_map = {}  # GAV -> build config name
        self.dependencies = {}  # GAV -> list of dependency GAVs
    
    def load_artifacts(self, artifact_file: str):
        """Load list of artifacts to analyze"""
        with open(artifact_file) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                
                parts = line.split(':')
                if len(parts) >= 3:
                    group_id = parts[0]
                    artifact_id = parts[1]
                    version = parts[2]
                    gav = f"{group_id}:{artifact_id}:{version}"
                    
                    # Generate build config name
                    name = f"{group_id.replace('.', '-')}-{artifact_id}-{version}-AUTOBUILD"
                    self.artifact_map[gav] = name
    
    def analyze_dependencies(self, gav: str) -> List[str]:
        """
        Analyze dependencies for a single artifact
        Returns list of dependency GAVs that are in our artifact set
        """
        if gav in self.dependencies:
            return self.dependencies[gav]
        
        parts = gav.split(':')
        if len(parts) < 3:
            return []
        
        group_id, artifact_id, version = parts[0], parts[1], parts[2]
        
        # Try to fetch POM and parse dependencies
        try:
            # Use Maven to get effective POM
            result = subprocess.run(
                ['mvn', 'dependency:tree', 
                 f'-DgroupId={group_id}',
                 f'-DartifactId={artifact_id}',
                 f'-Dversion={version}',
                 '-DoutputType=text',
                 '-DoutputFile=/tmp/dep-tree.txt'],
                capture_output=True,
                timeout=30,
                cwd='/tmp'
            )
            
            if result.returncode == 0 and Path('/tmp/dep-tree.txt').exists():
                deps = self._parse_dependency_tree('/tmp/dep-tree.txt')
                self.dependencies[gav] = deps
                return deps
        except:
            pass
        
        # Fallback: no dependencies
        self.dependencies[gav] = []
        return []
    
    def _parse_dependency_tree(self, tree_file: str) -> List[str]:
        """Parse Maven dependency tree output"""
        deps = []
        
        with open(tree_file) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('['):
                    continue
                
                # Parse dependency line: [INFO] +- group:artifact:type:version:scope
                if '+- ' in line or '\\- ' in line:
                    parts = line.split()
                    if len(parts) >= 2:
                        dep_str = parts[-1]
                        dep_parts = dep_str.split(':')
                        if len(dep_parts) >= 3:
                            dep_gav = f"{dep_parts[0]}:{dep_parts[1]}:{dep_parts[3]}"
                            
                            # Only include if it's in our artifact set
                            if dep_gav in self.artifact_map:
                                deps.append(dep_gav)
        
        return deps
    
    def get_build_dependencies(self, gav: str) -> List[str]:
        """Get build config names for dependencies"""
        dep_gavs = self.analyze_dependencies(gav)
        return [self.artifact_map[dep_gav] for dep_gav in dep_gavs if dep_gav in self.artifact_map]
    
    def analyze_common_dependencies(self) -> Dict[str, List[str]]:
        """
        Analyze common dependency patterns
        Returns dict of common dependencies and artifacts that use them
        """
        common_deps = {}
        
        for gav in self.artifact_map.keys():
            deps = self.analyze_dependencies(gav)
            for dep in deps:
                if dep not in common_deps:
                    common_deps[dep] = []
                common_deps[dep].append(gav)
        
        # Sort by usage count
        sorted_deps = sorted(common_deps.items(), key=lambda x: len(x[1]), reverse=True)
        
        return dict(sorted_deps[:20])  # Top 20 common dependencies


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: dependency_analyzer.py <artifact_file>", file=sys.stderr)
        print("Example: dependency_analyzer.py unproductized-deps.txt", file=sys.stderr)
        sys.exit(1)
    
    analyzer = DependencyAnalyzer()
    analyzer.load_artifacts(sys.argv[1])
    
    print(f"Loaded {len(analyzer.artifact_map)} artifacts")
    print()
    
    # Analyze common dependencies
    print("Analyzing common dependencies...")
    common = analyzer.analyze_common_dependencies()
    
    print()
    print("Top common dependencies:")
    for dep_gav, users in list(common.items())[:10]:
        print(f"  {dep_gav} -> used by {len(users)} artifacts")
