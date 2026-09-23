#!/usr/bin/env python3
"""
URL Transformer - Converts downstream PNC mirror URLs to upstream public repositories
"""

import re
from typing import Optional, Dict, List

class URLTransformer:
    """Transform downstream PNC URLs to upstream public repositories"""
    
    # Mapping of downstream prefixes to upstream organizations
    UPSTREAM_MAPPINGS = {
        # AWS
        'git@github.ibm.com:pnc-prod/aws-': 'https://github.com/aws/',
        'git@github.ibm.com:pnc-prod/Amazon-': 'https://github.com/aws/',
        'git@github.ibm.com:pnc-prod/amazon-': 'https://github.com/aws/',
        
        # Apache
        'git@github.ibm.com:pnc-prod/apache-': 'https://github.com/apache/',
        
        # Azure/Microsoft
        'git@github.ibm.com:pnc-prod/Azure-': 'https://github.com/Azure/',
        'git@github.ibm.com:pnc-prod/azure-': 'https://github.com/Azure/',
        'git@github.ibm.com:pnc-prod/microsoft-': 'https://github.com/microsoft/',
        
        # Google
        'git@github.ibm.com:pnc-prod/googleapis-': 'https://github.com/googleapis/',
        'git@github.ibm.com:pnc-prod/google-': 'https://github.com/google/',
        'git@github.ibm.com:pnc-prod/GoogleCloudPlatform-': 'https://github.com/GoogleCloudPlatform/',
        
        # Eclipse
        'git@github.ibm.com:pnc-prod/eclipse-': 'https://github.com/eclipse/',
        'git@github.ibm.com:pnc-prod/eclipse-ee4j-': 'https://github.com/eclipse-ee4j/',
        
        # Netty
        'git@github.ibm.com:pnc-prod/netty-': 'https://github.com/netty/',
        
        # Other common organizations
        'git@github.ibm.com:pnc-prod/FasterXML-': 'https://github.com/FasterXML/',
        'git@github.ibm.com:pnc-prod/reactor-': 'https://github.com/reactor/',
        'git@github.ibm.com:pnc-prod/spring-projects-': 'https://github.com/spring-projects/',
        'git@github.ibm.com:pnc-prod/square-': 'https://github.com/square/',
        'git@github.ibm.com:pnc-prod/ehcache-': 'https://github.com/ehcache/',
    }
    
    # Repository name transformations (remove common prefixes)
    REPO_NAME_TRANSFORMS = {
        'aws-sdk-java-v2': 'aws-sdk-java-v2',
        'apache-httpcomponents-client': 'httpcomponents-client',
        'apache-httpcomponents-core': 'httpcomponents-core',
        'googleapis-java-': 'java-',  # googleapis-java-storage -> java-storage
    }
    
    @classmethod
    def transform_to_upstream(cls, url: str) -> str:
        """
        Transform downstream PNC URL to upstream public repository
        
        Args:
            url: Downstream URL (e.g., git@github.ibm.com:pnc-prod/aws-aws-sdk-java-v2.git)
            
        Returns:
            Upstream URL (e.g., https://github.com/aws/aws-sdk-java-v2.git)
        """
        if not url:
            return url
        
        # Already upstream?
        if 'github.ibm.com' not in url and 'gitlab.cee.redhat.com' not in url:
            return url
        
        # Try each mapping
        for downstream_prefix, upstream_prefix in cls.UPSTREAM_MAPPINGS.items():
            if url.startswith(downstream_prefix):
                # Extract repo name
                repo_name = url[len(downstream_prefix):]
                
                # Apply repo name transformations
                for old_pattern, new_pattern in cls.REPO_NAME_TRANSFORMS.items():
                    if old_pattern in repo_name:
                        repo_name = repo_name.replace(old_pattern, new_pattern)
                
                # Construct upstream URL
                return upstream_prefix + repo_name
        
        # Fallback: try to extract organization and repo from URL
        # Pattern: git@github.ibm.com:pnc-prod/{org}-{repo}.git
        match = re.match(r'git@github\.ibm\.com:pnc-prod/([^-]+)-(.+)\.git', url)
        if match:
            org = match.group(1)
            repo = match.group(2)
            
            # Common organization mappings
            org_map = {
                'aws': 'aws',
                'Amazon': 'aws',
                'apache': 'apache',
                'Azure': 'Azure',
                'google': 'google',
                'googleapis': 'googleapis',
                'eclipse': 'eclipse',
                'netty': 'netty',
            }
            
            if org in org_map:
                return f"https://github.com/{org_map[org]}/{repo}.git"
        
        # If no transformation found, return original
        return url
    
    @classmethod
    def is_downstream_url(cls, url: str) -> bool:
        """Check if URL is a downstream PNC mirror"""
        if not url:
            return False
        return 'github.ibm.com' in url or 'gitlab.cee.redhat.com' in url
    
    @classmethod
    def get_upstream_info(cls, url: str) -> Dict[str, str]:
        """
        Get upstream repository information
        
        Returns:
            Dict with 'url', 'organization', 'repository'
        """
        upstream_url = cls.transform_to_upstream(url)
        
        # Extract org and repo from GitHub URL
        match = re.match(r'https://github\.com/([^/]+)/(.+?)(?:\.git)?$', upstream_url)
        if match:
            return {
                'url': upstream_url,
                'organization': match.group(1),
                'repository': match.group(2).replace('.git', '')
            }
        
        return {
            'url': upstream_url,
            'organization': 'unknown',
            'repository': 'unknown'
        }


if __name__ == '__main__':
    import sys
    
    # Test cases
    test_urls = [
        'git@github.ibm.com:pnc-prod/aws-aws-sdk-java-v2.git',
        'git@github.ibm.com:pnc-prod/apache-httpcomponents-client.git',
        'git@github.ibm.com:pnc-prod/Azure-azure-cosmos-sdk-for-java.git',
        'git@github.ibm.com:pnc-prod/googleapis-java-storage.git',
        'git@github.ibm.com:pnc-prod/ehcache-ehcache3.git',
        'https://github.com/netty/netty.git',  # Already upstream
    ]
    
    if len(sys.argv) > 1:
        # Transform provided URL
        url = sys.argv[1]
        transformed = URLTransformer.transform_to_upstream(url)
        print(f"Original:    {url}")
        print(f"Transformed: {transformed}")
        print(f"Is downstream: {URLTransformer.is_downstream_url(url)}")
    else:
        # Run tests
        print("=== URL Transformation Tests ===\n")
        for url in test_urls:
            transformed = URLTransformer.transform_to_upstream(url)
            info = URLTransformer.get_upstream_info(url)
            print(f"Original:    {url}")
            print(f"Transformed: {transformed}")
            print(f"Org:         {info['organization']}")
            print(f"Repo:        {info['repository']}")
            print()
