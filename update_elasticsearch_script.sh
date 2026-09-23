#!/bin/bash
# Update elasticsearch-java with correct build script

NEW_SCRIPT='gradle --info --stacktrace \\
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
    -Durl=${AProxDeployUrl}'

for batch_dir in output-camel-4.22-bacon-batches/*/; do
  config_file="${batch_dir}build-config.yaml"
  if [ -f "$config_file" ] && grep -q "elasticsearch-java" "$config_file"; then
    echo "Updating $(basename "$batch_dir")..."
    
    # Use Python to properly replace the buildScript section
    python3 << 'PYTHON'
import sys
import re

config_file = sys.argv[1]
new_script = sys.argv[2]

with open(config_file, 'r') as f:
    content = f.read()

# Find and replace the elasticsearch buildScript
pattern = r'(- name: "co-elastic-clients-elasticsearch-java[^"]*".*?buildScript: \|)(.*?)(\n  description:)'
replacement = r'\1\n    ' + new_script.replace('\n', '\n    ') + r'\3'

new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)

with open(config_file, 'w') as f:
    f.write(new_content)

print(f"✓ Updated {config_file}")
PYTHON
    python3 - "$config_file" "$NEW_SCRIPT"
  fi
done
