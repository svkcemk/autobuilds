#!/bin/bash
# Quick fix to clean up the managed dependencies

echo "Cleaning up managed dependencies..."
sed 's/^[[:space:]]*//; s/[[:space:]]*$//' ./camel-test/managed-dependencies.txt | \
  sed 's/[[:space:]]\+/:/g' > ./camel-test/managed-dependencies-clean.txt

echo "Before (with spaces):"
head -3 ./camel-test/managed-dependencies.txt

echo ""
echo "After (cleaned):"
head -3 ./camel-test/managed-dependencies-clean.txt

echo ""
echo "Now re-running filter with cleaned data..."
cp ./camel-test/managed-dependencies-clean.txt ./camel-test/all-dependencies.txt

# Re-run just the filtering part
./generate_transitive_builds_v2.sh --output ./camel-test --verbose 2>&1 | grep -A 5 "Filtering"
