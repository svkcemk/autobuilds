#!/usr/bin/env python3
"""
Auto-Fixer - Automatically detects and fixes common build configuration issues
Provides self-healing capabilities for the autobuilder
"""

import json
import subprocess
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from datetime import datetime


class AutoFixer:
    """
    Detects and automatically fixes common build configuration issues
    Learns from successful fixes to improve over time
    """
    
    def __init__(self, data_dir: str = None):
        """
        Initialize the Auto-Fixer
        
        Args:
            data_dir: Directory for storing fix history and patterns
        """
        if data_dir is None:
            data_dir = Path.home() / ".bob" / "ai" / "auto_fixer"
        
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)
        
        self.fix_history_file = self.data_dir / "fix_history.jsonl"
        self.success_rate_file = self.data_dir / "success_rates.json"
        
        self.success_rates = self._load_success_rates()
        
        # Map issue types to fix functions
        self.fix_strategies = {
            'scm_url_inaccessible': self.fix_scm_url_inaccessible,
            'scm_revision_invalid': self.fix_scm_revision_invalid,
            'invalid_environment': self.fix_invalid_environment,
            'invalid_build_script': self.fix_invalid_build_script,
            'missing_maven_flags': self.fix_missing_maven_flags,
        }
    
    def _load_success_rates(self) -> Dict:
        """Load fix success rates from disk"""
        if self.success_rate_file.exists():
            with open(self.success_rate_file) as f:
                return json.load(f)
        return {}
    
    def _save_success_rates(self):
        """Save fix success rates to disk"""
        with open(self.success_rate_file, 'w') as f:
            json.dump(self.success_rates, f, indent=2)
    
    def detect_issues(self, config_file: str, pom_file: str = None) -> List[Dict]:
        """
        Detect potential issues in build configuration
        
        Args:
            config_file: Path to build config JSON file
            pom_file: Optional path to POM file for deeper analysis
            
        Returns:
            List of detected issues with severity and auto-fix capability
        """
        issues = []
        
        # Load config
        try:
            with open(config_file) as f:
                config = json.load(f)
        except Exception as e:
            return [{
                'type': 'invalid_config_file',
                'severity': 'critical',
                'message': f"Cannot read config file: {e}",
                'auto_fixable': False
            }]
        
        # Check 1: SCM URL accessibility
        scm_url = config.get('scmUrl', '')
        if scm_url and not self._verify_scm_url(scm_url):
            issues.append({
                'type': 'scm_url_inaccessible',
                'severity': 'high',
                'message': f"SCM URL not accessible: {scm_url}",
                'auto_fixable': True,
                'config_file': config_file
            })
        
        # Check 2: SCM revision exists
        scm_revision = config.get('scmRevision', '')
        if scm_url and scm_revision and not self._verify_scm_revision(scm_url, scm_revision):
            issues.append({
                'type': 'scm_revision_invalid',
                'severity': 'high',
                'message': f"SCM revision not found: {scm_revision}",
                'auto_fixable': True,
                'config_file': config_file
            })
        
        # Check 3: Environment ID validity
        env_id = config.get('environmentId')
        if env_id and not self._verify_environment_id(env_id):
            issues.append({
                'type': 'invalid_environment',
                'severity': 'medium',
                'message': f"Invalid environment ID: {env_id}",
                'auto_fixable': True,
                'config_file': config_file
            })
        
        # Check 4: Build script syntax
        build_script = config.get('buildScript', '')
        if build_script:
            script_issues = self._check_build_script(build_script)
            if script_issues:
                issues.append({
                    'type': 'invalid_build_script',
                    'severity': 'medium',
                    'message': f"Build script issues: {', '.join(script_issues)}",
                    'details': script_issues,
                    'auto_fixable': True,
                    'config_file': config_file
                })
        
        # Check 5: Missing recommended Maven flags
        if build_script and 'mvn' in build_script:
            missing_flags = self._check_missing_maven_flags(build_script)
            if missing_flags:
                issues.append({
                    'type': 'missing_maven_flags',
                    'severity': 'low',
                    'message': f"Missing recommended Maven flags: {', '.join(missing_flags)}",
                    'details': missing_flags,
                    'auto_fixable': True,
                    'config_file': config_file
                })
        
        return issues
    
    def auto_fix_issues(self, issues: List[Dict], dry_run: bool = False) -> List[Dict]:
        """
        Automatically fix detected issues
        
        Args:
            issues: List of issues from detect_issues()
            dry_run: If True, only preview fixes without applying
            
        Returns:
            List of fix results with status
        """
        fixes_applied = []
        
        for issue in issues:
            if not issue.get('auto_fixable', False):
                fixes_applied.append({
                    'issue': issue,
                    'status': 'not_fixable',
                    'message': 'Issue cannot be automatically fixed'
                })
                continue
            
            fix_func = self.fix_strategies.get(issue['type'])
            if not fix_func:
                fixes_applied.append({
                    'issue': issue,
                    'status': 'no_strategy',
                    'message': f"No fix strategy for {issue['type']}"
                })
                continue
            
            try:
                if dry_run:
                    fix_preview = fix_func(issue, preview=True)
                    fixes_applied.append({
                        'issue': issue,
                        'fix': fix_preview,
                        'status': 'preview'
                    })
                else:
                    fix_result = fix_func(issue, preview=False)
                    fixes_applied.append({
                        'issue': issue,
                        'fix': fix_result,
                        'status': 'applied'
                    })
                    
                    # Record successful fix
                    self._record_fix(issue['type'], True)
            
            except Exception as e:
                fixes_applied.append({
                    'issue': issue,
                    'error': str(e),
                    'status': 'failed'
                })
                self._record_fix(issue['type'], False)
        
        return fixes_applied
    
    def fix_scm_url_inaccessible(self, issue: Dict, preview: bool = False) -> str:
        """
        Fix inaccessible SCM URL by trying common transformations
        
        Args:
            issue: Issue dict with config_file
            preview: If True, return preview without applying
            
        Returns:
            Description of fix applied or previewed
        """
        config_file = issue['config_file']
        with open(config_file) as f:
            config = json.load(f)
        
        current_url = config['scmUrl']
        
        # Try common transformations
        alternatives = [
            current_url.replace('git@github.com:', 'https://github.com/'),
            current_url.replace('git://', 'https://'),
            current_url.replace('.git', '') if current_url.endswith('.git') else current_url + '.git',
            current_url.replace('http://', 'https://'),
        ]
        
        # Test alternatives
        for alt_url in alternatives:
            if alt_url != current_url and self._verify_scm_url(alt_url):
                if preview:
                    return f"Would change SCM URL from {current_url} to {alt_url}"
                
                config['scmUrl'] = alt_url
                with open(config_file, 'w') as f:
                    json.dump(config, f, indent=2)
                
                return f"Changed SCM URL to {alt_url}"
        
        return "No valid alternative URL found"
    
    def fix_scm_revision_invalid(self, issue: Dict, preview: bool = False) -> str:
        """
        Fix invalid SCM revision by finding correct tag
        
        Args:
            issue: Issue dict with config_file
            preview: If True, return preview without applying
            
        Returns:
            Description of fix applied or previewed
        """
        config_file = issue['config_file']
        with open(config_file) as f:
            config = json.load(f)
        
        scm_url = config['scmUrl']
        current_revision = config['scmRevision']
        
        # Extract version from config name
        name = config.get('name', '')
        version_match = re.search(r'_(\d+\.\d+\.\d+[^_]*)$', name)
        if not version_match:
            return "Cannot extract version from config name"
        
        version = version_match.group(1)
        
        # Try common tag patterns
        tag_patterns = [
            f"v{version}",
            f"release-{version}",
            f"rel/{version}",
            version,
            f"{name.split('_')[1]}-{version}",  # artifact-version
        ]
        
        for tag in tag_patterns:
            if self._verify_scm_revision(scm_url, tag):
                if preview:
                    return f"Would change revision from {current_revision} to {tag}"
                
                config['scmRevision'] = tag
                with open(config_file, 'w') as f:
                    json.dump(config, f, indent=2)
                
                return f"Changed revision to {tag}"
        
        return "No valid revision found"
    
    def fix_invalid_environment(self, issue: Dict, preview: bool = False) -> str:
        """
        Fix invalid environment ID by selecting appropriate one
        
        Args:
            issue: Issue dict with config_file
            preview: If True, return preview without applying
            
        Returns:
            Description of fix applied or previewed
        """
        config_file = issue['config_file']
        with open(config_file) as f:
            config = json.load(f)
        
        current_env = config.get('environmentId')
        
        # Default to Java 11 environment (most common)
        new_env = 1200  # Java 11
        
        if preview:
            return f"Would change environment ID from {current_env} to {new_env} (Java 11)"
        
        config['environmentId'] = new_env
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=2)
        
        return f"Changed environment ID to {new_env} (Java 11)"
    
    def fix_invalid_build_script(self, issue: Dict, preview: bool = False) -> str:
        """
        Fix build script syntax errors
        
        Args:
            issue: Issue dict with config_file and details
            preview: If True, return preview without applying
            
        Returns:
            Description of fix applied or previewed
        """
        config_file = issue['config_file']
        with open(config_file) as f:
            config = json.load(f)
        
        script = config.get('buildScript', '')
        fixed_script = script
        
        # Fix common issues
        script_issues = issue.get('details', [])
        
        if 'missing_clean' in script_issues and 'clean' not in script:
            fixed_script = fixed_script.replace('mvn ', 'mvn clean ')
        
        if 'missing_deploy' in script_issues and 'deploy' not in script:
            fixed_script = fixed_script.replace('install', 'deploy')
        
        if preview:
            return f"Would change build script from '{script}' to '{fixed_script}'"
        
        config['buildScript'] = fixed_script
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=2)
        
        return f"Fixed build script: {fixed_script}"
    
    def fix_missing_maven_flags(self, issue: Dict, preview: bool = False) -> str:
        """
        Add missing recommended Maven flags
        
        Args:
            issue: Issue dict with config_file and details
            preview: If True, return preview without applying
            
        Returns:
            Description of fix applied or previewed
        """
        config_file = issue['config_file']
        with open(config_file) as f:
            config = json.load(f)
        
        script = config.get('buildScript', '')
        missing_flags = issue.get('details', [])
        
        # Add missing flags
        for flag in missing_flags:
            if flag not in script:
                script += f" {flag}"
        
        if preview:
            return f"Would add flags: {', '.join(missing_flags)}"
        
        config['buildScript'] = script
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=2)
        
        return f"Added Maven flags: {', '.join(missing_flags)}"
    
    def _verify_scm_url(self, url: str, timeout: int = 5) -> bool:
        """Verify if SCM URL is accessible"""
        try:
            result = subprocess.run(
                ['curl', '-I', '-s', '-f', '-m', str(timeout), url],
                capture_output=True,
                timeout=timeout + 1
            )
            return result.returncode == 0
        except:
            return False
    
    def _verify_scm_revision(self, url: str, revision: str, timeout: int = 10) -> bool:
        """Verify if SCM revision exists in repository"""
        try:
            # Try git ls-remote to check if revision exists
            result = subprocess.run(
                ['git', 'ls-remote', '--tags', '--heads', url, revision],
                capture_output=True,
                timeout=timeout
            )
            return result.returncode == 0 and len(result.stdout) > 0
        except:
            return False
    
    def _verify_environment_id(self, env_id: int) -> bool:
        """Verify if environment ID is valid"""
        # Common valid environment IDs
        valid_envs = {
            660,   # Java 8
            1200,  # Java 11
            316,   # Java 17
            1201,  # Java 11 + Maven 3.9
        }
        return env_id in valid_envs
    
    def _check_build_script(self, script: str) -> List[str]:
        """Check build script for common issues"""
        issues = []
        
        if 'mvn' not in script:
            issues.append('not_maven_script')
        
        if 'clean' not in script:
            issues.append('missing_clean')
        
        if 'deploy' not in script and 'install' not in script:
            issues.append('missing_deploy')
        
        return issues
    
    def _check_missing_maven_flags(self, script: str) -> List[str]:
        """Check for missing recommended Maven flags"""
        missing = []
        
        recommended_flags = {
            '-DskipTests': 'Skip tests for faster builds',
            '-Dartifactory.staging.skip=true': 'Skip Artifactory staging',
            '-DskipNexusStagingDeployMojo=true': 'Skip Nexus staging',
        }
        
        for flag, _ in recommended_flags.items():
            if flag not in script:
                missing.append(flag)
        
        return missing
    
    def _record_fix(self, issue_type: str, success: bool):
        """Record fix attempt for learning"""
        # Update success rates
        if issue_type not in self.success_rates:
            self.success_rates[issue_type] = {'attempts': 0, 'successes': 0}
        
        self.success_rates[issue_type]['attempts'] += 1
        if success:
            self.success_rates[issue_type]['successes'] += 1
        
        self._save_success_rates()
        
        # Log to history
        record = {
            'issue_type': issue_type,
            'success': success,
            'timestamp': datetime.now().isoformat()
        }
        
        with open(self.fix_history_file, 'a') as f:
            f.write(json.dumps(record) + '\n')
    
    def get_statistics(self) -> Dict:
        """Get auto-fix statistics"""
        stats = {
            'total_fixes': 0,
            'successful_fixes': 0,
            'by_type': {}
        }
        
        for issue_type, data in self.success_rates.items():
            attempts = data['attempts']
            successes = data['successes']
            success_rate = (successes / attempts * 100) if attempts > 0 else 0
            
            stats['total_fixes'] += attempts
            stats['successful_fixes'] += successes
            stats['by_type'][issue_type] = {
                'attempts': attempts,
                'successes': successes,
                'success_rate': f"{success_rate:.1f}%"
            }
        
        if stats['total_fixes'] > 0:
            stats['overall_success_rate'] = f"{stats['successful_fixes'] / stats['total_fixes'] * 100:.1f}%"
        else:
            stats['overall_success_rate'] = "N/A"
        
        return stats


# CLI interface for testing
if __name__ == '__main__':
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: auto_fixer.py <config_file> [--dry-run]")
        print("Example: auto_fixer.py output/build-configs/org_apache_camel_camel-kafka_4.18.1.yaml.json")
        sys.exit(1)
    
    config_file = sys.argv[1]
    dry_run = '--dry-run' in sys.argv
    
    fixer = AutoFixer()
    
    print(f"Analyzing: {config_file}")
    print()
    
    # Detect issues
    issues = fixer.detect_issues(config_file)
    
    if not issues:
        print("✅ No issues detected!")
        sys.exit(0)
    
    print(f"Found {len(issues)} issue(s):")
    print()
    
    for i, issue in enumerate(issues, 1):
        print(f"{i}. [{issue['severity'].upper()}] {issue['message']}")
        print(f"   Auto-fixable: {'Yes' if issue['auto_fixable'] else 'No'}")
        print()
    
    # Auto-fix
    if dry_run:
        print("DRY RUN - Previewing fixes:")
    else:
        print("Applying fixes:")
    print()
    
    fixes = fixer.auto_fix_issues(issues, dry_run=dry_run)
    
    for i, fix in enumerate(fixes, 1):
        status_icon = {
            'preview': '👁️',
            'applied': '✅',
            'failed': '❌',
            'not_fixable': '⚠️',
            'no_strategy': '❓'
        }.get(fix['status'], '?')
        
        print(f"{i}. {status_icon} {fix['status'].upper()}")
        if 'fix' in fix:
            print(f"   {fix['fix']}")
        elif 'error' in fix:
            print(f"   Error: {fix['error']}")
        elif 'message' in fix:
            print(f"   {fix['message']}")
        print()
    
    # Show statistics
    stats = fixer.get_statistics()
    if stats['total_fixes'] > 0:
        print("Auto-Fix Statistics:")
        print(f"  Total fixes attempted: {stats['total_fixes']}")
        print(f"  Successful fixes: {stats['successful_fixes']}")
        print(f"  Overall success rate: {stats['overall_success_rate']}")
