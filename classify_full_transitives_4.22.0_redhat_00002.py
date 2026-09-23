from pathlib import Path
import urllib.request
import urllib.error
import re
import collections
from datetime import datetime

base = Path('/Users/soghosh/autobuilds')
full_dir = base / 'camel-4.22.0-full-analysis'
report_dir = base / 'camel-4.22.0-redhat-00002-report'
indy = 'https://indy.corp.redhat.com/api/content/maven/hosted/pnc-builds'

deps_file = full_dir / 'all-third-party-deps.txt'
components_file = full_dir / 'all-camel-components.txt'
prod_file = report_dir / 'productized-deps.txt'
unprod_file = report_dir / 'unproductized-deps.txt'
prod_det_file = report_dir / 'productized-deps-detailed.txt'
unprod_det_file = report_dir / 'unproductized-deps-detailed.txt'
by_group_file = report_dir / 'by-group.txt'
summary_file = report_dir / 'analysis-summary.txt'
report_md = report_dir / 'PRODUCTIZATION_REPORT.md'
unresolved_path = report_dir / 'unresolved-artifacts.txt'

deps = [l.strip() for l in deps_file.read_text().splitlines() if l.strip()]
components = [l.strip() for l in components_file.read_text().splitlines() if l.strip()]
report_dir.mkdir(parents=True, exist_ok=True)

prod, unprod = [], []
prod_det, unprod_det = [], []
cache = {}

for dep in deps:
    parts = [p.strip() for p in dep.split(':')]
    if len(parts) != 3:
        unprod.append(dep)
        unprod_det.append(f'{dep} -&gt; invalid dependency format')
        continue

    g, a, v = parts

    if '.redhat-' in v or '-redhat-' in v:
        prod.append(dep)
        prod_det.append(f'{dep} -&gt; already productized in source list')
        continue

    key = (g, a)
    if key not in cache:
        url = f"{indy}/{g.replace('.', '/')}/{a}/maven-metadata.xml"
        try:
            with urllib.request.urlopen(url, timeout=10) as r:
                cache[key] = r.read().decode('utf-8', 'replace')
        except Exception:
            cache[key] = ''
    md = cache[key]
    matches = re.findall(rf'&lt;version&gt;{re.escape(v)}\.redhat-[^&lt;]+&lt;/version&gt;', md)
    if not matches:
        matches = re.findall(rf'&lt;version&gt;{re.escape(v)}\.redhat-[^&lt;]+&lt;/version&gt;'.replace('&lt;', '<').replace('&gt;', '>'), md)
    if matches:
        mv = matches[-1].replace('&lt;version&gt;', '').replace('&lt;/version&gt;', '').replace('<version>', '').replace('</version>', '')
        prod.append(f'{g}:{a}:{mv}')
        prod_det.append(f'{dep} -&gt; {mv}')
    else:
        unprod.append(dep)
        unprod_det.append(f'{dep} -&gt; no matching .redhat-* version found in Indy metadata')

prod_file.write_text('\n'.join(prod) + ('\n' if prod else ''))
unprod_file.write_text('\n'.join(unprod) + ('\n' if unprod else ''))
prod_det_file.write_text('\n'.join(prod_det) + ('\n' if prod_det else ''))
unprod_det_file.write_text('\n'.join(unprod_det) + ('\n' if unprod_det else ''))

groups = collections.Counter(d.split(':', 1)[0] for d in deps)
by_group_lines = [f'{count:7d} {group}' for group, count in groups.most_common()]
by_group_file.write_text('\n'.join(by_group_lines) + ('\n' if by_group_lines else ''))

unresolved = [l.strip() for l in unresolved_path.read_text().splitlines() if l.strip()] if unresolved_path.exists() else []
summary_file.write_text(
    'Top dependency groups:\n' +
    '\n'.join(by_group_lines[:20]) +
    '\n\nUnresolved artifacts:\n' +
    ('\n'.join(unresolved) if unresolved else 'None') +
    '\n'
)

root_count = len(components)
third_party_count = len(deps)
productized_count = len(prod)
unproductized_count = len(unprod)
unresolved_count = len(unresolved)
prod_pct = f"{(productized_count / third_party_count * 100):.1f}" if third_party_count else "0.0"
unprod_pct = f"{(unproductized_count / third_party_count * 100):.1f}" if third_party_count else "0.0"

def filt(patterns: str) -> str:
    rx = re.compile(patterns)
    vals = [d for d in unprod if rx.search(d)]
    return '\n'.join(vals) if vals else 'None'

generated = datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S %Z')

report_md.write_text(f"""# Camel 4.22.0.redhat-00002 - Full Transitive Dependency Productization Analysis

**Generated**: {generated}
**Analysis Scope**: Full transitive dependencies of all Camel components from Camel 4.22.0
**Productized Camel Version Target**: 4.22.0.redhat-00002
**Indy Source**: {indy}
**Discovery Source**: /Users/soghosh/autobuilds/camel-4.22.0-full-analysis

---

## Executive Summary

| Metric | Count |
|--------|-------|
| Root Artifacts Analysed | {root_count} |
| Third-Party Dependencies Checked | {third_party_count} |
| Already Productized | {productized_count} ({prod_pct}%) |
| Need Productization | {unproductized_count} ({unprod_pct}%) |
| Unresolved Artifacts | {unresolved_count} |

---

## Scope and Method

This report is based on **full transitive dependency analysis of all Camel components**, not BOM-managed entries.

1. Enumerated all Camel components from the Camel BOM.
2. Downloaded each component POM from Indy and extracted third-party compile dependencies.
3. Aggregated the unique third-party dependency set across all components.
4. Checked each dependency in Indy using `maven-metadata.xml`.
5. Marked a dependency as productized if any matching `.redhat-*` version exists for the same upstream version.

---

## Top 20 Third-Party Dependency Groups

```text
{chr(10).join(by_group_lines[:20])}
```

---

## Already Productized Dependencies

```text
{prod_det_file.read_text().rstrip() if prod_det else 'None'}
```

---

## Dependencies Needing Productization

```text
{unprod_det_file.read_text().rstrip() if unprod_det else 'None'}
```

---

## Unresolved Artifacts from Analysis

```text
{chr(10).join(unresolved) if unresolved else 'None'}
```

---

## Priority Build Waves

### Wave 1: Core Libraries
```text
{filt(r'(slf4j|log4j|commons-|guava|jakarta|javax)')}
```

### Wave 2: Messaging
```text
{filt(r'(kafka|qpid|activemq|amqp|jms|pulsar|rabbitmq)')}
```

### Wave 3: Data Formats
```text
{filt(r'(jackson|jaxb|xml|json|yaml|protobuf|avro)')}
```

### Wave 4: Networking
```text
{filt(r'(netty|http|okhttp|jetty|undertow)')}
```

### Wave 5: Framework and Integration
```text
{filt(r'(spring|cxf|micrometer|aws|quartz)')}
```

---

## Evidence Files

- `all-camel-components.txt`
- `all-third-party-deps.txt`
- `productized-deps.txt`
- `productized-deps-detailed.txt`
- `unproductized-deps.txt`
- `unproductized-deps-detailed.txt`
- `by-group.txt`
- `analysis-summary.txt`

---

## Key Findings

- This corrected analysis uses the **full transitive dependency set across all Camel components**.
- The discovered unique third-party dependency set contains **{third_party_count}** dependencies.
- **{productized_count}** are already productized in Indy.
- **{unproductized_count}** still need productization.
- **{unresolved_count}** unresolved artifacts remain from prior analysis assets.
""")

print(f'CLASSIFIED={third_party_count} PRODUCTIZED={productized_count} UNPRODUCTIZED={unproductized_count}')