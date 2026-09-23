#!/usr/bin/env python3
"""
Quick PNC harvester focused on Camel 4.22 builds
Minimal implementation for immediate results
"""

import json
import requests
from pathlib import Path
from typing import List, Dict
import time


class CamelPNCHarvester:
    """Harvest Camel 4.22 build data from PNC"""
    
    def __init__(self, pnc_base_url: str = "https://orch.psi.redhat.com/pnc-rest/v2"):
        self.base_url = pnc_base_url
        self.session = requests.Session()
        self.session.headers.update({"Accept": "application/json"})
        # Disable SSL verification for internal Red Hat infrastructure
        self.session.verify = False
        # Suppress SSL warnings
        import urllib3
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    
    def harvest_camel_builds(self, version_pattern: str = "4.22") -> List[Dict]:
        """
        Harvest all Camel builds matching version pattern
        
        Args:
            version_pattern: Version to match (e.g., "4.22")
            
        Returns:
            List of build records with SCM info
        """
        builds = []
        
        # Step 1: Find Camel build group
        print(f"Step 1: Finding Camel {version_pattern} build group...")
        
        # Query for group configs (build groups)
        gc_url = f"{self.base_url}/group-configs"
        gc_params = {
            "q": f"name=like=*Camel*{version_pattern}*",
            "pageSize": 10
        }
        
        try:
            response = self.session.get(gc_url, params=gc_params, timeout=30)
            response.raise_for_status()
            gc_data = response.json()
        except requests.exceptions.RequestException as e:
            print(f"Error querying group configs: {e}")
            # Fallback: try direct build config query
            return self._harvest_by_build_configs(version_pattern, builds)
        
        group_configs = gc_data.get('content', [])
        if not group_configs:
            print(f"No build group found, trying direct build config query...")
            return self._harvest_by_build_configs(version_pattern, builds)
        
        gc = group_configs[0]
        gc_id = gc.get('id')
        gc_name = gc.get('name')
        print(f"Found build group: {gc_name} (ID: {gc_id})")
        
        # Get build configs from group
        build_config_ids = gc.get('buildConfigs', {})
        print(f"Build group contains {len(build_config_ids)} build configs")
        print()
        
        # Step 2: Fetch each build config
        print("Step 2: Fetching build config details...")
        
        for bc_id in build_config_ids.keys():
            try:
                bc_url = f"{self.base_url}/build-configs/{bc_id}"
                response = self.session.get(bc_url, timeout=30)
                response.raise_for_status()
                config = response.json()
                self._extract_build_info(config, builds, version_pattern)
            except Exception as e:
                print(f"  Warning: Failed to fetch build config {bc_id}: {e}")
                continue
        
        return builds
    
    def _harvest_by_build_configs(self, version_pattern: str, builds: List[Dict]) -> List[Dict]:
        """Fallback: harvest by querying build configs directly"""
        print(f"Querying build configs with name pattern...")
        
        url = f"{self.base_url}/build-configs"
        params = {
            "q": f"name=like=*{version_pattern}*",
            "pageSize": 200
        }
        
        try:
            response = self.session.get(url, params=params, timeout=30)
            response.raise_for_status()
            data = response.json()
        except requests.exceptions.RequestException as e:
            print(f"Error querying build configs: {e}")
            return builds
        
        all_configs = data.get('content', [])
        print(f"Found {len(all_configs)} build configs")
        print()
        
        for config in all_configs:
            self._extract_build_info(config, builds, version_pattern)
        
        return builds
    
    def _extract_build_info(self, config: Dict, builds: List[Dict], version_pattern: str):
        """Extract build info from a config and add to builds list"""
        name = config.get('name', '')
        
        # Extract SCM info
        scm_repo = config.get('scmRepository', {})
        scm_url = scm_repo.get('internalUrl') or scm_repo.get('externalUrl')
        scm_revision = config.get('scmRevision')
        
        if not scm_url or not scm_revision:
            return
        
        # Parse artifact info from name
        # Common formats: "camel-4.22.0", "cxf-4.2.3", "groupId_artifactId_version"
        parts = name.split('_')
        if len(parts) >= 3:
            group_id = parts[0].replace('_', '.')
            artifact_id = parts[1]
            version = parts[2]
        else:
            # Handle formats like "camel-4.22.0" or "cxf-4.2.3"
            if '-' in name:
                name_parts = name.split('-')
                # Last part is usually version
                version = name_parts[-1]
                # Everything before is artifact
                artifact_id = '-'.join(name_parts[:-1])
            else:
                artifact_id = name
                version = version_pattern
            
            # Infer group ID from artifact
            if artifact_id.startswith('camel'):
                group_id = "org.apache.camel"
            elif artifact_id.startswith('cxf'):
                group_id = "org.apache.cxf"
            else:
                # Try to get from project
                project = config.get('project', {})
                project_name = project.get('name', '')
                if '/' in project_name:
                    org, proj = project_name.split('/', 1)
                    group_id = f"org.{org}.{proj}".replace('-', '.')
                else:
                    group_id = f"org.{artifact_id}".replace('-', '.')
        
        build_record = {
            "build_config_id": config.get('id'),
            "name": name,
            "group_id": group_id,
            "artifact_id": artifact_id,
            "version": version,
            "scm_url": scm_url,
            "scm_revision": scm_revision,
            "build_script": config.get('buildScript', ''),
            "environment_id": config.get('environment', {}).get('id'),
            "environment_name": config.get('environment', {}).get('name'),
            "source": "pnc_harvest",
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        }
        
        builds.append(build_record)
        print(f"  ✓ {group_id}:{artifact_id}:{version}")
    
    def save_to_jsonl(self, builds: List[Dict], output_file: str):
        """Save builds to JSONL file"""
        output_path = Path(output_file)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_path, 'w') as f:
            for build in builds:
                f.write(json.dumps(build) + '\n')
        
        print(f"\nSaved {len(builds)} builds to {output_file}")
    
    def export_summary(self, builds: List[Dict], output_file: str):
        """Export summary statistics"""
        output_path = Path(output_file)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Calculate statistics
        total_builds = len(builds)
        unique_artifacts = len(set(f"{b['group_id']}:{b['artifact_id']}" for b in builds))
        unique_scm_urls = len(set(b['scm_url'] for b in builds))
        
        # Group by artifact
        by_artifact = {}
        for build in builds:
            key = f"{build['group_id']}:{build['artifact_id']}"
            if key not in by_artifact:
                by_artifact[key] = []
            by_artifact[key].append(build['version'])
        
        summary = {
            "total_builds": total_builds,
            "unique_artifacts": unique_artifacts,
            "unique_scm_urls": unique_scm_urls,
            "artifacts": {k: sorted(v) for k, v in by_artifact.items()},
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        }
        
        with open(output_path, 'w') as f:
            json.dump(summary, f, indent=2)
        
        print(f"\nSummary Statistics:")
        print(f"  Total builds: {total_builds}")
        print(f"  Unique artifacts: {unique_artifacts}")
        print(f"  Unique SCM URLs: {unique_scm_urls}")
        print(f"\nSummary saved to {output_file}")


if __name__ == '__main__':
    import sys
    
    version = sys.argv[1] if len(sys.argv) > 1 else "4.22"
    output = sys.argv[2] if len(sys.argv) > 2 else "pnc-camel-harvest.jsonl"
    
    print("="*60)
    print("PNC Camel Build Harvester")
    print("="*60)
    print()
    
    harvester = CamelPNCHarvester()
    builds = harvester.harvest_camel_builds(version)
    
    if builds:
        harvester.save_to_jsonl(builds, output)
        
        # Export summary
        summary_file = output.replace('.jsonl', '-summary.json')
        harvester.export_summary(builds, summary_file)
        
        print()
        print("="*60)
        print(f"✓ Successfully harvested {len(builds)} Camel {version} builds from PNC")
        print("="*60)
    else:
        print()
        print("="*60)
        print("✗ No builds found")
        print("="*60)
        sys.exit(1)
