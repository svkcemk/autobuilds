#!/usr/bin/env python3
"""
Generate PNC build configs for additional artifacts not in original 472 list
"""

import yaml
from pathlib import Path

# Additional artifacts to productize
ADDITIONAL_ARTIFACTS = [
    {
        "groupId": "com.fasterxml.woodstox",
        "artifactId": "woodstox-core",
        "version": "7.2.2",
        "scmUrl": "https://github.com/FasterXML/woodstox.git",
        "scmRevision": "woodstox-core-7.2.2",
        "buildType": "MVN"
    },
    {
        "groupId": "org.apache.cxf.xjc-utils",
        "artifactId": "cxf-xjc-runtime",
        "version": "4.2.0",
        "scmUrl": "https://github.com/apache/cxf-xjc-utils.git",
        "scmRevision": "cxf-xjc-utils-4.2.0",
        "buildType": "MVN"
    },
    {
        "groupId": "org.apache.cxf.xjcplugins",
        "artifactId": "cxf-xjc-boolean",
        "version": "4.2.0",
        "scmUrl": "https://github.com/apache/cxf-xjc-utils.git",
        "scmRevision": "cxf-xjc-utils-4.2.0",
        "buildType": "MVN"
    },
    {
        "groupId": "org.apache.cxf.xjcplugins",
        "artifactId": "cxf-xjc-dv",
        "version": "4.2.0",
        "scmUrl": "https://github.com/apache/cxf-xjc-utils.git",
        "scmRevision": "cxf-xjc-utils-4.2.0",
        "buildType": "MVN"
    },
    {
        "groupId": "org.apache.cxf.xjcplugins",
        "artifactId": "cxf-xjc-javadoc",
        "version": "4.2.0",
        "scmUrl": "https://github.com/apache/cxf-xjc-utils.git",
        "scmRevision": "cxf-xjc-utils-4.2.0",
        "buildType": "MVN"
    },
    {
        "groupId": "org.apache.cxf.xjcplugins",
        "artifactId": "cxf-xjc-pl",
        "version": "4.2.0",
        "scmUrl": "https://github.com/apache/cxf-xjc-utils.git",
        "scmRevision": "cxf-xjc-utils-4.2.0",
        "buildType": "MVN"
    },
    {
        "groupId": "org.apache.cxf.xjcplugins",
        "artifactId": "cxf-xjc-ts",
        "version": "4.2.0",
        "scmUrl": "https://github.com/apache/cxf-xjc-utils.git",
        "scmRevision": "cxf-xjc-utils-4.2.0",
        "buildType": "MVN"
    },
    {
        "groupId": "org.apache.cxf.xjcplugins",
        "artifactId": "cxf-xjc-wsdlextension",
        "version": "4.2.0",
        "scmUrl": "https://github.com/apache/cxf-xjc-utils.git",
        "scmRevision": "cxf-xjc-utils-4.2.0",
        "buildType": "MVN"
    },
    {
        "groupId": "org.jvnet.mimepull",
        "artifactId": "mimepull",
        "version": "1.11.0",
        "scmUrl": "https://github.com/eclipse-ee4j/metro-mimepull.git",
        "scmRevision": "1.11.0",
        "buildType": "MVN"
    }
]

def generate_build_config(artifact):
    """Generate a single build config"""
    name = f"{artifact['groupId'].replace('.', '-')}-{artifact['artifactId']}-{artifact['version']}-AUTOBUILD"
    project = artifact['scmUrl'].replace('https://github.com/', '').replace('.git', '')
    
    build_script = f"mvn source:jar deploy -DskipTests -DrpmDeploymentRepository=\"indy-mvn::default::${{AProxDeployUrl}}\""
    
    return {
        "name": name,
        "project": project,
        "buildType": artifact['buildType'],
        "scmUrl": artifact['scmUrl'],
        "scmRevision": artifact['scmRevision'],
        "environmentId": 316,
        "buildScript": build_script,
        "description": f"Auto-generated build config for {artifact['groupId']}:{artifact['artifactId']}:{artifact['version']}"
    }

def main():
    output_dir = Path("output-camel-4.22-bacon-batches/camel-4.22-pnc-batch-033")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Generate build configs
    build_configs = [generate_build_config(artifact) for artifact in ADDITIONAL_ARTIFACTS]
    
    # Create the YAML structure
    config = {
        "builds": build_configs,
        "outputPrefixes": {
            "releaseFile": "camel-4.22-third-party-additional",
            "releaseDir": "camel-4.22-third-party-additional"
        },
        "flow": {
            "licensesGeneration": {
                "strategy": "IGNORE"
            },
            "repositoryGeneration": {
                "strategy": "DOWNLOAD"
            },
            "javadocGeneration": {
                "strategy": "IGNORE"
            },
            "sourcesGeneration": {
                "strategy": "DOWNLOAD"
            }
        },
        "addons": {
            "communityDepAnalysis": {
                "enabled": True
            }
        }
    }
    
    # Write to file
    output_file = output_dir / "build-config.yaml"
    with open(output_file, 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False, width=1000)
    
    print(f"✓ Generated batch-033 with {len(build_configs)} build configs")
    print(f"  Location: {output_file}")
    print(f"\nArtifacts included:")
    for artifact in ADDITIONAL_ARTIFACTS:
        print(f"  - {artifact['groupId']}:{artifact['artifactId']}:{artifact['version']}")

if __name__ == '__main__':
    main()
