#!/usr/bin/env python3
"""
SCM URL Corrections - Known correct SCM URLs for artifacts
"""

# Known correct SCM URLs from first-batch reference data and manual verification
KNOWN_SCM_URLS = {
    # Apache HttpComponents
    'org.apache.httpcomponents.core5': {
        'scmUrl': 'https://github.com/apache/httpcomponents-core.git',
        'tagPattern': 'rel/v{version}'
    },
    'org.apache.httpcomponents.client5': {
        'scmUrl': 'https://github.com/apache/httpcomponents-client.git',
        'tagPattern': 'rel/v{version}'
    },
    
    # Netty
    'io.netty': {
        'scmUrl': 'https://github.com/netty/netty.git',
        'tagPattern': 'netty-{version}'
    },
    
    # Reactive Streams
    'org.reactivestreams': {
        'scmUrl': 'https://github.com/reactive-streams/reactive-streams-jvm.git',
        'tagPattern': 'v{version}'
    },
    
    # Project Reactor
    'io.projectreactor': {
        'scmUrl': 'https://github.com/reactor/reactor-core.git',
        'tagPattern': 'v{version}'
    },
    
    # gRPC
    'io.grpc': {
        'scmUrl': 'https://github.com/grpc/grpc-java.git',
        'tagPattern': 'v{version}'
    },
    
    # AWS SDK v2
    'software.amazon.awssdk': {
        'scmUrl': 'https://github.com/aws/aws-sdk-java-v2.git',
        'tagPattern': '{version}'
    },
    
    # Kafka
    'org.apache.kafka': {
        'scmUrl': 'https://github.com/apache/kafka.git',
        'tagPattern': '{version}'
    },
    
    # Google Error Prone
    'com.google.errorprone': {
        'scmUrl': 'https://github.com/google/error-prone.git',
        'tagPattern': 'v{version}'
    },
    
    # JSpecify
    'org.jspecify': {
        'scmUrl': 'https://github.com/jspecify/jspecify.git',
        'tagPattern': 'v{version}'
    },
    
    # Deep Java Library (DJL)
    'ai.djl': {
        'scmUrl': 'https://github.com/deepjavalibrary/djl.git',
        'tagPattern': 'v{version}'
    },
    'ai.djl.huggingface': {
        'scmUrl': 'https://github.com/deepjavalibrary/djl.git',
        'tagPattern': 'v{version}'
    },
    'ai.djl.python': {
        'scmUrl': 'https://github.com/deepjavalibrary/djl.git',
        'tagPattern': 'v{version}'
    },
    'ai.djl.timeseries': {
        'scmUrl': 'https://github.com/deepjavalibrary/djl.git',
        'tagPattern': 'v{version}'
    },
    
    # HAPI FHIR (monorepo)
    'ca.uhn.hapi.fhir': {
        'scmUrl': 'https://github.com/hapifhir/hapi-fhir.git',
        'tagPattern': 'v{version}'
    },
    
    # Docling
    'ai.docling': {
        'scmUrl': 'https://github.com/DS4SD/docling.git',
        'tagPattern': 'v{version}'
    },
    
    # LZ4
    'at.yawk.lz4': {
        'scmUrl': 'https://github.com/lz4/lz4-java.git',
        'tagPattern': 'v{version}'
    },
}

def get_scm_info(group_id: str, artifact_id: str, version: str) -> dict:
    """
    Get correct SCM URL and revision for an artifact
    Returns dict with scmUrl and scmRevision
    """
    # Check for exact group match
    if group_id in KNOWN_SCM_URLS:
        info = KNOWN_SCM_URLS[group_id]
        return {
            'scmUrl': info['scmUrl'],
            'scmRevision': info['tagPattern'].format(version=version)
        }
    
    # Check for parent group match (e.g., com.google.cloud.* -> com.google.cloud)
    parts = group_id.split('.')
    for i in range(len(parts), 0, -1):
        parent_group = '.'.join(parts[:i])
        if parent_group in KNOWN_SCM_URLS:
            info = KNOWN_SCM_URLS[parent_group]
            return {
                'scmUrl': info['scmUrl'],
                'scmRevision': info['tagPattern'].format(version=version)
            }
    
    return None

if __name__ == '__main__':
    # Test
    test_cases = [
        ('ai.djl', 'api', '0.36.0'),
        ('ca.uhn.hapi.fhir', 'hapi-fhir-base', '8.10.1'),
        ('io.netty', 'netty-codec-http3', '4.2.15.Final'),
        ('software.amazon.awssdk', 's3', '2.50.2'),
    ]
    
    for group, artifact, version in test_cases:
        info = get_scm_info(group, artifact, version)
        print(f"{group}:{artifact}:{version}")
        if info:
            print(f"  SCM: {info['scmUrl']}")
            print(f"  Rev: {info['scmRevision']}")
        else:
            print("  No correction found")
        print()
