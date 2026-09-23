#!/usr/bin/env python3
import xml.etree.ElementTree as ET
import urllib.request

url = "https://indy.corp.redhat.com/api/content/maven/hosted/pnc-builds/com/redhat/quarkus/platform/quarkus-bom/3.33.2.SP3-redhat-00002/quarkus-bom-3.33.2.SP3-redhat-00002.pom"

try:
    with urllib.request.urlopen(url, timeout=10) as response:
        tree = ET.parse(response)
        root = tree.getroot()
        ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
        
        print("Checking for BOM imports (type=pom, scope=import)...")
        dep_mgmt = root.find('.//m:dependencyManagement/m:dependencies', ns)
        
        if dep_mgmt:
            bom_imports = []
            camel_cxf_imports = []
            
            for dep in dep_mgmt.findall('m:dependency', ns):
                dep_type = dep.find('m:type', ns)
                scope = dep.find('m:scope', ns)
                
                if dep_type is not None and dep_type.text == 'pom' and scope is not None and scope.text == 'import':
                    group = dep.find('m:groupId', ns)
                    artifact = dep.find('m:artifactId', ns)
                    version = dep.find('m:version', ns)
                    
                    if group is not None and artifact is not None:
                        gav = f"{group.text}:{artifact.text}:{version.text if version is not None else 'unknown'}"
                        bom_imports.append(gav)
                        
                        if 'camel' in gav.lower() or 'cxf' in gav.lower():
                            camel_cxf_imports.append(gav)
            
            print(f"\nTotal BOM imports found: {len(bom_imports)}")
            print(f"Camel/CXF BOM imports found: {len(camel_cxf_imports)}")
            
            if camel_cxf_imports:
                print("\n=== Camel/CXF BOM Imports ===")
                for gav in camel_cxf_imports:
                    print(f"  - {gav}")
            else:
                print("\n❌ No Camel or CXF BOM imports found in this BOM")
                print("\nAll BOM imports:")
                for gav in bom_imports[:10]:
                    print(f"  - {gav}")
                if len(bom_imports) > 10:
                    print(f"  ... and {len(bom_imports) - 10} more")
        else:
            print("No dependencyManagement section found")
            
except Exception as e:
    print(f"Error: {e}")
