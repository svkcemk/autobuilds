#!/usr/bin/env python3
"""
PNC Bulk Harvester - Harvest ALL successful builds from PNC
Fetches from general build-configs endpoint with pagination
"""

import json
import requests
import time
from pathlib import Path
from typing import List, Dict
import urllib3

# Disable SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class PNCBulkHarvester:
    """Harvest all successful builds from PNC"""
    
    def __init__(self, pnc_base_url: str = "https://orch.psi.redhat.com/pnc-rest/v2"):
        self.base_url = pnc_base_url
        self.session = requests.Session()
        self.session.headers.update({"Accept": "application/json"})
        self.session.verify = False
    
    def harvest_all_builds(self, max_pages: int = 50, page_size: int = 200) -> List[Dict]:
        """
        Harvest all build configs from PNC with pagination
        
        Args:
            max_pages: Maximum number of pages to fetch (default 50 = 10,000 builds)
            page_size: Number of builds per page (max 200)
            
        Returns:
            List of build records with SCM info
        """
        builds = []
        
        print(f"Harvesting builds from PNC (max {max_pages} pages x {page_size} builds)...")
        print()
        
        for page in range(max_pages):
            print(f"Fetching page {page + 1}/{max_pages}...")
            
            url = f"{self.base_url}/build-configs"
            params = {
                "pageIndex": page,
                "pageSize": page_size,
                "sort": "=desc=modificationTime"
            }
            
            try:
                response = self.session.get(url, params=params, timeout=30)
                response.raise_for_status()
                data = response.json()
            except requests.exceptions.RequestException as e:
                print(f"  Error fetching page {page + 1}: {e}")
                break
            
            configs = data.get('content', [])
            if not configs:
                print(f"  No more builds found at page {page + 1}")
                break
            
            print(f"  Processing {len(configs)} configs...")
            for config in configs:
                try:
                    self._extract_build_info(config, builds)
                except Exception as e:
                    continue
            
            print(f"  Total builds harvested so far: {len(builds)}")
            
            # Check if we've reached the last page
            total_pages = data.get('totalPages', 0)
            if page + 1 >= total_pages:
                print(f"  Reached last page ({total_pages} total)")
                break
            
            # Small delay to avoid overwhelming the server
            time.sleep(0.5)
        
        return builds
    
    def _extract_build_info(self, config: Dict, builds: List[Dict]):
        """Extract build info from a config and add to builds list"""
        name = config.get('name', '')
        
        # Extract SCM info
        scm_repo = config.get('scmRepository', {})
        scm_url = scm_repo.get('internalUrl') or scm_repo.get('externalUrl')
        scm_revision = config.get('scmRevision')
        
        if not scm_url or not scm_revision:
            return
        
        # Parse artifact info from name
        group_id = None
        artifact_id = None
        version = None
        
        # Try to parse from name
        if '-AUTOBUILD' in name:
            # Format: com.google.code.findbugs-jsr305-3.0.2-AUTOBUILD
            parts = name.replace('-AUTOBUILD', '').rsplit('-', 2)
            if len(parts) >= 3:
                group_artifact = parts[0]
                version = parts[-1]
                
                # Split group and artifact
                if '.' in group_artifact:
                    ga_parts = group_artifact.rsplit('-', 1)
                    if len(ga_parts) == 2:
                        group_id = ga_parts[0].replace('-', '.')
                        artifact_id = ga_parts[1]
                    else:
                        group_id = group_artifact.replace('-', '.')
                        artifact_id = group_artifact.split('.')[-1]
                else:
                    group_id = "unknown"
                    artifact_id = group_artifact
        elif name.startswith('upstream-'):
            # Format: upstream-kryo-4.0.2
            parts = name.replace('upstream-', '').rsplit('-', 1)
            if len(parts) == 2:
                artifact_id = parts[0]
                version = parts[1]
                
                # Try to infer group from project
                project = config.get('project', {})
                project_name = project.get('name', '')
                if '/' in project_name:
                    org, proj = project_name.split('/', 1)
                    group_id = f"com.{org}.{proj}".replace('-', '.')
                else:
                    group_id = f"com.{artifact_id}".replace('-', '.')
        else:
            # Try standard parsing
            parts = name.split('-')
            if len(parts) >= 2:
                version = parts[-1]
                artifact_id = '-'.join(parts[:-1])
                
                # Try to infer group from project
                project = config.get('project', {})
                project_name = project.get('name', '')
                if '/' in project_name:
                    org, proj = project_name.split('/', 1)
                    group_id = f"org.{org}.{proj}".replace('-', '.')
                else:
                    group_id = f"org.{artifact_id}".replace('-', '.')
        
        if not all([group_id, artifact_id, version]):
            return
        
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
            "modification_time": config.get('modificationTime'),
            "source": "pnc_bulk_harvest",
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        }
        
        builds.append(build_record)
    
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
            "top_artifacts": dict(sorted(
                {k: len(v) for k, v in by_artifact.items()}.items(),
                key=lambda x: x[1],
                reverse=True
            )[:50]),
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
    
    max_pages = 50  # Default: 10,000 builds
    page_size = 200
    output = "pnc-bulk-harvest.jsonl"
    
    if len(sys.argv) > 1:
        max_pages = int(sys.argv[1])
    if len(sys.argv) > 2:
        output = sys.argv[2]
    
    print("="*60)
    print("PNC Bulk Harvester")
    print("="*60)
    print(f"Max pages: {max_pages}")
    print(f"Page size: {page_size}")
    print(f"Max builds: {max_pages * page_size}")
    print()
    
    harvester = PNCBulkHarvester()
    builds = harvester.harvest_all_builds(max_pages=max_pages, page_size=page_size)
    
    if builds:
        harvester.save_to_jsonl(builds, output)
        
        # Export summary
        summary_file = output.replace('.jsonl', '-summary.json')
        harvester.export_summary(builds, summary_file)
        
        print()
        print("="*60)
        print(f"✓ Successfully harvested {len(builds)} builds")
        print("="*60)
        print()
        print("Next steps:")
        print(f"  1. Train AI: python3 lib/ai/quick_train.py {output}")
        print(f"  2. Validate: python3 lib/ai/quick_validate.py <test-file>")
    else:
        print()
        print("="*60)
        print("✗ No builds found")
        print("="*60)
        sys.exit(1)
