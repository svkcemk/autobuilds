# Build Config Generation Summary

Generated: Fri May 29 17:57:17 IST 2026
Input file: camel-test/filtered-dependencies.txt

## Statistics

- Total dependencies processed: 0
- Build configs created: 0

## Output Files

- Build configs: `test-output/build-configs/`
- Summary: `test-output/SUMMARY.md`

## Next Steps

1. Review the generated configs in: `test-output/build-configs/`
2. Update SCM URLs with actual repository locations
3. Use bacon CLI to create builds in PNC:
   ```bash
   for config in test-output/build-configs/*.yaml; do
       bacon pnc build-config create -f "$config"
   done
   ```

## Sample Config

```yaml

```
