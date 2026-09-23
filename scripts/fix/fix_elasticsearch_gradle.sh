#!/bin/bash
# Fix elasticsearch-java to use Gradle

for batch_dir in output-camel-4.22-bacon-batches/*/; do
  config_file="${batch_dir}build-config.yaml"
  if [ -f "$config_file" ]; then
    if grep -q "elasticsearch-java" "$config_file"; then
      echo "Fixing elasticsearch-java in $(basename "$batch_dir")..."
      sed -i '' '/co-elastic-clients-elasticsearch-java/,/description:/ {
        s|buildType: "MVN"|buildType: "GRADLE"|
        s|mvn source:jar deploy.*|./gradlew :java-client:publishToMavenLocal -x test --no-daemon|
      }' "$config_file"
      echo "✓ Fixed"
    fi
  fi
done
