#!/usr/bin/env python3
"""
Enhanced PNC harvester for product versions
Harvests all build configs from a product version
"""

import json
import requests
import time
from pathlib import Path
from typing import List, Dict
import urllib3

# Disable SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class PNCProductHarvester:
    """Harvest all builds from a PNC product version"""
    
    def __init__(self, pnc_base_url: str = "https://orch.psi.redhat.com/pnc-rest/v2"):
        self.base_url = pnc_base_url
        self.session = requests.Session()
        self.session.headers.update({"Accept": "application/json"})
        self.session.verify = False
    
    def harvest_product_version(self, product_version_id: str) -> List[Dict]:
        """
        Harvest all build configs from a product version
        
        Args:
            product_version_id: PNC product version ID (e.g., "1730" for CEQ 4.18)
            
        Returns:
            List of build records with SCM info
        """
        builds = []
        
        print(f"Querying PNC for product version {product_version_id}...")
        
        # Get all build configs for this product version
        url = f"{self.base_url}/build-configs"
        params = {
            "q": f"productVersion.id=={product_version_id}",
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
        print(f"Found {len(all_configs)} build configs in product version")
        print()
        
        # Harvest SCM info from all configs
        print("Harvesting SCM info from build configs...")
        for i, config in enumerate(all_configs, 1):
            try:
                self._extract_build_info(config, builds)
                if i % 10 == 0:
                    print(f"  Processed {i}/{len(all_configs)} configs...")
            except Exception as e:
                print(f"  Warning: Failed to process config {config.get('id')}: {e}")
                continue
        
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
        # Common formats: 
        # - "groupId-artifactId-version-AUTOBUILD"
        # - "groupId.subgroup-artifactId-version"
        # - "artifactId-version"
        
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
                    # Has dots, likely group.artifact format
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
            "source": "pnc_product_harvest",
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
    
    if len(sys.argv) < 2:
        print("Usage: pnc_product_harvester.py <product_version_id> [output_file]")
        print()
        print("Examples:")
        print("  # Camel Extensions for Quarkus Third Party 4.18")
        print("  python3 pnc_product_harvester.py 1730 ceq-4.18-harvest.jsonl")
        print()
        print("  # Camel 4.18")
        print("  python3 pnc_product_harvester.py 1555 camel-4.18-harvest.jsonl")
        sys.exit(1)
    
    product_version_id = sys.argv[1]
    output = sys.argv[2] if len(sys.argv) > 2 else f"pnc-product-{product_version_id}-harvest.jsonl"
    
    print("="*60)
    print("PNC Product Version Harvester")
    print("="*60)
    print()
    
    harvester = PNCProductHarvester()
    builds = harvester.harvest_product_version(product_version_id)
    
    if builds:
        harvester.save_to_jsonl(builds, output)
        
        # Export summary
        summary_file = output.replace('.jsonl', '-summary.json')
        harvester.export_summary(builds, summary_file)
        
        print()
        print("="*60)
        print(f"✓ Successfully harvested {len(builds)} builds from product version {product_version_id}")
        print("="*60)
    else:
        print()
        print("="*60)
        print("✗ No builds found")
        print("="*60)
        sys.exit(1)
