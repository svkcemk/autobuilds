#!/usr/bin/env python3
"""
Update elasticsearch-java with correct production build script
"""

import sys
import re
from pathlib import Path

CORRECT_BUILD_SCRIPT = '''gradle --info --stacktrace \\
    -Doss=true -Dbuild.snapshot=false -Dlicense.key=/dev/null \\
    :java-client:sourcesJar publishMavenPublicationToMavenLocal \\
    -x test \\
    -x forbiddenApis \\
    -x signMavenPublication \\
    -x checkstyleMain \\
    -x checkstyleTest \\
    -x javadoc

export VERSION=$(ls $HOME/.m2/repository/co/elastic/clients/elasticsearch-java/ | head -1)
echo "Deploying version: ${VERSION}"

mvn deploy:deploy-file \\
    -Dfile=$HOME/.m2/repository/co/elastic/clients/elasticsearch-java/${VERSION}/elasticsearch-java-${VERSION}.jar \\
    -DpomFile=$HOME/.m2/repository/co/elastic/clients/elasticsearch-java/${VERSION}/elasticsearch-java-${VERSION}.pom \\
    -Dsources=$HOME/.m2/repository/co/elastic/clients/elasticsearch-java/${VERSION}/elasticsearch-java-${VERSION}-sources.jar \\
    -DrepositoryId=indy-mvn \\
    -Durl=${AProxDeployUrl}'''

def update_elasticsearch_config(config_file: Path):
    """Update elasticsearch build script in config file"""
    
    with open(config_file) as f:
        content = f.read()
    
    if 'elasticsearch-java' not in content:
        return False
    
    # Find and replace the buildScript section for elasticsearch
    pattern = r'(- name: "co-elastic-clients-elasticsearch-java[^"]*".*?buildScript: \|)(.*?)(\n  description:)'
    
    def replace_script(match):
        prefix = match.group(1)
        suffix = match.group(3)
        # Indent the script properly (4 spaces)
        indented_script = '\n    ' + CORRECT_BUILD_SCRIPT.replace('\n', '\n    ')
        return prefix + indented_script + suffix
    
    new_content = re.sub(pattern, replace_script, content, flags=re.DOTALL)
    
    if new_content != content:
        with open(config_file, 'w') as f:
            f.write(new_content)
        return True
    
    return False

if __name__ == '__main__':
    batch_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('output-camel-4.22-bacon-batches')
    
    updated = 0
    for batch_subdir in sorted(batch_dir.glob('*/')):
        config_file = batch_subdir / 'build-config.yaml'
        if config_file.exists():
            if update_elasticsearch_config(config_file):
                print(f"✓ Updated {batch_subdir.name}")
                updated += 1
    
    print(f"\nTotal configs updated: {updated}")
