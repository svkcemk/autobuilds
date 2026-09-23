#!/usr/bin/env python3
"""
Extended SCM URL Corrections - Comprehensive list of known correct SCM URLs
"""

# Extended known correct SCM URLs
KNOWN_SCM_URLS = {
    # From batch 1 (already covered)
    'org.apache.httpcomponents.core5': {
        'scmUrl': 'https://github.com/apache/httpcomponents-core.git',
        'tagPattern': 'rel/v{version}'
    },
    'org.apache.httpcomponents.client5': {
        'scmUrl': 'https://github.com/apache/httpcomponents-client.git',
        'tagPattern': 'rel/v{version}'
    },
    'io.netty': {
        'scmUrl': 'https://github.com/netty/netty.git',
        'tagPattern': 'netty-{version}'
    },
    'org.reactivestreams': {
        'scmUrl': 'https://github.com/reactive-streams/reactive-streams-jvm.git',
        'tagPattern': 'v{version}'
    },
    'io.projectreactor': {
        'scmUrl': 'https://github.com/reactor/reactor-core.git',
        'tagPattern': 'v{version}'
    },
    'io.grpc': {
        'scmUrl': 'https://github.com/grpc/grpc-java.git',
        'tagPattern': 'v{version}'
    },
    'software.amazon.awssdk': {
        'scmUrl': 'https://github.com/aws/aws-sdk-java-v2.git',
        'tagPattern': '{version}'
    },
    'org.apache.kafka': {
        'scmUrl': 'https://github.com/apache/kafka.git',
        'tagPattern': '{version}'
    },
    'com.google.errorprone': {
        'scmUrl': 'https://github.com/google/error-prone.git',
        'tagPattern': 'v{version}'
    },
    'org.jspecify': {
        'scmUrl': 'https://github.com/jspecify/jspecify.git',
        'tagPattern': 'v{version}'
    },
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
    'ca.uhn.hapi.fhir': {
        'scmUrl': 'https://github.com/hapifhir/hapi-fhir.git',
        'tagPattern': 'v{version}'
    },
    'ai.docling': {
        'scmUrl': 'https://github.com/DS4SD/docling.git',
        'tagPattern': 'v{version}'
    },
    'at.yawk.lz4': {
        'scmUrl': 'https://github.com/lz4/lz4-java.git',
        'tagPattern': 'v{version}'
    },
    
    # Batch 2 corrections
    'com.alibaba': {
        'scmUrl': 'https://github.com/alibaba/fastjson2.git',
        'tagPattern': '{version}'
    },
    'com.apptasticsoftware': {
        'scmUrl': 'https://github.com/w3stling/rssreader.git',
        'tagPattern': 'v{version}'
    },
    'com.arangodb': {
        'scmUrl': 'https://github.com/arangodb/arangodb-java-driver.git',
        'tagPattern': '{version}'
    },
    'com.atlassian.jira': {
        'scmUrl': 'https://github.com/atlassian/jira-rest-java-client.git',
        'tagPattern': 'v{version}'
    },
    'com.atlassian.oai': {
        'scmUrl': 'https://github.com/atlassian-labs/swagger-request-validator.git',
        'tagPattern': 'v{version}'
    },
    'com.atlassian.sal': {
        'scmUrl': 'https://github.com/atlassian/sal.git',
        'tagPattern': 'sal-parent-{version}'
    },
    'com.auth0': {
        'scmUrl': 'https://github.com/auth0/java-jwt.git',
        'tagPattern': '{version}'
    },
    'com.azure': {
        'scmUrl': 'https://github.com/Azure/azure-sdk-for-java.git',
        'tagPattern': 'azure-core_{version}'
    },
    'com.azure.resourcemanager': {
        'scmUrl': 'https://github.com/Azure/azure-sdk-for-java.git',
        'tagPattern': 'azure-resourcemanager_{version}'
    },
    'co.elastic.clients': {
        'scmUrl': 'https://github.com/elastic/elasticsearch-java.git',
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
    
    # Check for parent group match
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
