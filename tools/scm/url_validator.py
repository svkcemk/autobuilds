#!/usr/bin/env python3
"""
Smart URL Validator - Intelligent URL validation with caching and learning
Validates SCM URLs efficiently with parallel processing and historical data
"""

import json
import subprocess
import asyncio
import hashlib
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor, as_completed


class SmartURLValidator:
    """
    Intelligently validates and ranks SCM URLs
    Uses historical success rates and parallel processing
    """
    
    def __init__(self, data_dir: str = None, cache_ttl_hours: int = 24):
        """
        Initialize the Smart URL Validator
        
        Args:
            data_dir: Directory for storing cache and statistics
            cache_ttl_hours: Cache time-to-live in hours
        """
        if data_dir is None:
            data_dir = Path.home() / ".bob" / "ai" / "url_validator"
        
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)
        
        self.success_cache_file = self.data_dir / "success_cache.json"
        self.failure_cache_file = self.data_dir / "failure_cache.json"
        self.stats_file = self.data_dir / "validation_stats.json"
        
        self.cache_ttl = timedelta(hours=cache_ttl_hours)
        
        self.success_cache = self._load_cache(self.success_cache_file)
        self.failure_cache = self._load_cache(self.failure_cache_file)
        self.stats = self._load_stats()
    
    def _load_cache(self, cache_file: Path) -> Dict:
        """Load cache from disk"""
        if cache_file.exists():
            with open(cache_file) as f:
                return json.load(f)
        return {}
    
    def _save_cache(self, cache: Dict, cache_file: Path):
        """Save cache to disk"""
        with open(cache_file, 'w') as f:
            json.dump(cache, f, indent=2)
    
    def _load_stats(self) -> Dict:
        """Load validation statistics"""
        if self.stats_file.exists():
            with open(self.stats_file) as f:
                return json.load(f)
        return {
            'total_validations': 0,
            'cache_hits': 0,
            'successful_validations': 0,
            'failed_validations': 0
        }
    
    def _save_stats(self):
        """Save validation statistics"""
        with open(self.stats_file, 'w') as f:
            json.dump(self.stats, f, indent=2)
    
    def _is_cache_valid(self, cache_entry: Dict) -> bool:
        """Check if cache entry is still valid"""
        if 'timestamp' not in cache_entry:
            return False
        
        cached_time = datetime.fromisoformat(cache_entry['timestamp'])
        return datetime.now() - cached_time < self.cache_ttl
    
    def validate_url(self, url: str, timeout: int = 5) -> Dict:
        """
        Validate single URL with caching
        
        Args:
            url: URL to validate
            timeout: Timeout in seconds
            
        Returns:
            Dict with validation result
        """
        url_hash = hashlib.md5(url.encode()).hexdigest()
        
        # Check success cache
        if url_hash in self.success_cache:
            cache_entry = self.success_cache[url_hash]
            if self._is_cache_valid(cache_entry):
                self.stats['cache_hits'] += 1
                self.stats['total_validations'] += 1
                self._save_stats()
                return {
                    'url': url,
                    'valid': True,
                    'score': cache_entry['score'],
                    'cached': True,
                    'checks': cache_entry.get('checks', [])
                }
        
        # Check failure cache
        if url_hash in self.failure_cache:
            cache_entry = self.failure_cache[url_hash]
            if self._is_cache_valid(cache_entry):
                self.stats['cache_hits'] += 1
                self.stats['total_validations'] += 1
                self._save_stats()
                return {
                    'url': url,
                    'valid': False,
                    'score': 0.0,
                    'cached': True,
                    'checks': ['cached_failure']
                }
        
        # Perform validation
        result = self._validate_url_fresh(url, timeout)
        
        # Update cache
        cache_entry = {
            'score': result['score'],
            'checks': result['checks'],
            'timestamp': datetime.now().isoformat()
        }
        
        if result['valid']:
            self.success_cache[url_hash] = cache_entry
            self._save_cache(self.success_cache, self.success_cache_file)
            self.stats['successful_validations'] += 1
        else:
            self.failure_cache[url_hash] = cache_entry
            self._save_cache(self.failure_cache, self.failure_cache_file)
            self.stats['failed_validations'] += 1
        
        self.stats['total_validations'] += 1
        self._save_stats()
        
        return result
    
    def _validate_url_fresh(self, url: str, timeout: int) -> Dict:
        """
        Perform fresh validation of URL
        
        Args:
            url: URL to validate
            timeout: Timeout in seconds
            
        Returns:
            Dict with validation result
        """
        score = 0.0
        checks = []
        
        # Check 1: HTTP HEAD request (40% weight)
        if self._check_http_accessible(url, timeout):
            score += 0.4
            checks.append('http_accessible')
        else:
            return {
                'url': url,
                'valid': False,
                'score': 0.0,
                'checks': ['http_failed'],
                'cached': False
            }
        
        # Check 2: Git protocol check (30% weight)
        if self._check_git_protocol(url, timeout):
            score += 0.3
            checks.append('git_valid')
        
        # Check 3: Repository metadata (20% weight)
        if self._check_repo_metadata(url, timeout):
            score += 0.2
            checks.append('metadata_valid')
        
        # Check 4: Historical success rate (10% weight)
        historical_score = self._get_historical_score(url)
        score += historical_score * 0.1
        if historical_score > 0:
            checks.append('historical_success')
        
        return {
            'url': url,
            'valid': score >= 0.4,  # Minimum threshold
            'score': score,
            'checks': checks,
            'cached': False
        }
    
    def _check_http_accessible(self, url: str, timeout: int) -> bool:
        """Check if URL is accessible via HTTP HEAD"""
        try:
            result = subprocess.run(
                ['curl', '-I', '-s', '-f', '-m', str(timeout), url],
                capture_output=True,
                timeout=timeout + 1
            )
            return result.returncode == 0
        except:
            return False
    
    def _check_git_protocol(self, url: str, timeout: int) -> bool:
        """Check if URL supports git protocol"""
        try:
            result = subprocess.run(
                ['git', 'ls-remote', '--heads', url],
                capture_output=True,
                timeout=timeout
            )
            return result.returncode == 0
        except:
            return False
    
    def _check_repo_metadata(self, url: str, timeout: int) -> bool:
        """Check if repository has valid metadata"""
        try:
            # Try to get repository info
            result = subprocess.run(
                ['git', 'ls-remote', '--tags', url],
                capture_output=True,
                timeout=timeout
            )
            # Check if we got any tags
            return result.returncode == 0 and len(result.stdout) > 0
        except:
            return False
    
    def _get_historical_score(self, url: str) -> float:
        """Get historical success score for URL"""
        url_hash = hashlib.md5(url.encode()).hexdigest()
        
        if url_hash in self.success_cache:
            # URL has been successful before
            return 1.0
        
        # Check for similar URLs (same domain)
        domain = self._extract_domain(url)
        similar_successes = sum(
            1 for cached_url in self.success_cache.values()
            if self._extract_domain(cached_url.get('url', '')) == domain
        )
        
        if similar_successes > 0:
            return min(similar_successes / 10.0, 1.0)
        
        return 0.0
    
    def _extract_domain(self, url: str) -> str:
        """Extract domain from URL"""
        import re
        match = re.search(r'https?://([^/]+)', url)
        return match.group(1) if match else ''
    
    def validate_urls_parallel(self, urls: List[str], max_workers: int = 10, 
                               timeout: int = 5) -> List[Dict]:
        """
        Validate multiple URLs in parallel
        
        Args:
            urls: List of URLs to validate
            max_workers: Maximum number of parallel workers
            timeout: Timeout per URL in seconds
            
        Returns:
            List of validation results, sorted by score (highest first)
        """
        results = []
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            # Submit all validation tasks
            future_to_url = {
                executor.submit(self.validate_url, url, timeout): url 
                for url in urls
            }
            
            # Collect results as they complete
            for future in as_completed(future_to_url):
                try:
                    result = future.result()
                    results.append(result)
                except Exception as e:
                    url = future_to_url[future]
                    results.append({
                        'url': url,
                        'valid': False,
                        'score': 0.0,
                        'error': str(e),
                        'cached': False
                    })
        
        # Sort by score (highest first)
        results.sort(key=lambda x: x['score'], reverse=True)
        
        return results
    
    def get_valid_urls(self, urls: List[str], max_workers: int = 10,
                      timeout: int = 5, min_score: float = 0.4) -> List[str]:
        """
        Get list of valid URLs from candidates
        
        Args:
            urls: List of candidate URLs
            max_workers: Maximum number of parallel workers
            timeout: Timeout per URL in seconds
            min_score: Minimum score threshold
            
        Returns:
            List of valid URLs
        """
        results = self.validate_urls_parallel(urls, max_workers, timeout)
        return [r['url'] for r in results if r['valid'] and r['score'] >= min_score]
    
    def clear_cache(self, older_than_hours: int = None):
        """
        Clear cache entries
        
        Args:
            older_than_hours: If specified, only clear entries older than this
        """
        if older_than_hours is None:
            # Clear all
            self.success_cache = {}
            self.failure_cache = {}
        else:
            # Clear old entries
            cutoff = datetime.now() - timedelta(hours=older_than_hours)
            
            self.success_cache = {
                k: v for k, v in self.success_cache.items()
                if datetime.fromisoformat(v.get('timestamp', '2000-01-01')) > cutoff
            }
            
            self.failure_cache = {
                k: v for k, v in self.failure_cache.items()
                if datetime.fromisoformat(v.get('timestamp', '2000-01-01')) > cutoff
            }
        
        self._save_cache(self.success_cache, self.success_cache_file)
        self._save_cache(self.failure_cache, self.failure_cache_file)
    
    def get_statistics(self) -> Dict:
        """Get validation statistics"""
        cache_hit_rate = 0.0
        if self.stats['total_validations'] > 0:
            cache_hit_rate = self.stats['cache_hits'] / self.stats['total_validations'] * 100
        
        success_rate = 0.0
        total_fresh = self.stats['successful_validations'] + self.stats['failed_validations']
        if total_fresh > 0:
            success_rate = self.stats['successful_validations'] / total_fresh * 100
        
        return {
            'total_validations': self.stats['total_validations'],
            'cache_hits': self.stats['cache_hits'],
            'cache_hit_rate': f"{cache_hit_rate:.1f}%",
            'successful_validations': self.stats['successful_validations'],
            'failed_validations': self.stats['failed_validations'],
            'success_rate': f"{success_rate:.1f}%",
            'cached_successes': len(self.success_cache),
            'cached_failures': len(self.failure_cache)
        }


# CLI interface for testing
if __name__ == '__main__':
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: url_validator.py <url1> [url2] [url3] ...")
        print("Example: url_validator.py https://github.com/apache/camel.git")
        sys.exit(1)
    
    urls = sys.argv[1:]
    
    validator = SmartURLValidator()
    
    print(f"Validating {len(urls)} URL(s)...")
    print()
    
    if len(urls) == 1:
        # Single URL validation
        result = validator.validate_url(urls[0])
        
        status = "✅ VALID" if result['valid'] else "❌ INVALID"
        cached = " (cached)" if result['cached'] else ""
        
        print(f"{status}{cached}")
        print(f"URL: {result['url']}")
        print(f"Score: {result['score']:.2f}")
        print(f"Checks: {', '.join(result['checks'])}")
    else:
        # Multiple URL validation (parallel)
        results = validator.validate_urls_parallel(urls)
        
        print("Validation Results:")
        print("-" * 80)
        
        for i, result in enumerate(results, 1):
            status = "✅" if result['valid'] else "❌"
            cached = " (cached)" if result['cached'] else ""
            
            print(f"{i}. {status} {result['url']}{cached}")
            print(f"   Score: {result['score']:.2f} | Checks: {', '.join(result['checks'])}")
            print()
    
    # Show statistics
    print()
    print("Validation Statistics:")
    print("-" * 80)
    stats = validator.get_statistics()
    for key, value in stats.items():
        print(f"{key.replace('_', ' ').title()}: {value}")
