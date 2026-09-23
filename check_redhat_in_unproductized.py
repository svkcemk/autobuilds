from pathlib import Path

p = Path('/Users/soghosh/autobuilds/camel-4.22.0-redhat-00002-report/unproductized-deps.txt')
bad = []
for i, line in enumerate(p.read_text().splitlines(), 1):
    s = line.strip()
    if not s:
        continue
    parts = [x.strip() for x in s.split(':')]
    if len(parts) >= 3 and 'redhat-' in parts[-1]:
        bad.append((i, s))

print(f'count={len(bad)}')
for i, s in bad[:100]:
    print(f'{i}:{s}')
