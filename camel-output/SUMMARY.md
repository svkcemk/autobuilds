# Build Config Generation Summary

Generated: Fri May 29 18:28:53 IST 2026
Input file: camel-test/all-dependencies.txt

## Statistics

- Total dependencies processed: 515
- Build configs created: 515

## Output Files

- Build configs: `camel-output//build-configs/`
- Summary: `camel-output//SUMMARY.md`

## Next Steps

1. Review the generated configs in: `camel-output//build-configs/`
2. Update SCM URLs with actual repository locations
3. Use bacon CLI to create builds in PNC:
   ```bash
   for config in camel-output//build-configs/*.yaml; do
       bacon pnc build-config create -f "$config"
   done
   ```

## Sample Config

```yaml
==> camel-output//build-configs/org.apache.camel_camel-activemq_4.18.1.yaml <==
name: org.apache.camel_camel-activemq_4.18.1
description: "Build configuration for camel-activemq 4.18.1"
project: camel-activemq
scmRepository:
  url: "https://github.com/placeholder/camel-activemq.git"
  revision: "4.18.1"
buildScript: "mvn clean deploy -DskipTests"
environment:
  name: "OpenJDK 11"
buildType: MVN

==> camel-output//build-configs/org.apache.camel_camel-activemq6_4.18.1.yaml <==
name: org.apache.camel_camel-activemq6_4.18.1
description: "Build configuration for camel-activemq6 4.18.1"
```
