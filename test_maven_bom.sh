#!/bin/bash
# Test script to debug Maven BOM dependency resolution

echo "Testing Maven BOM dependency resolution..."
echo "==========================================="

BOM="org.apache.camel:camel-bom:4.18.1"

# Create a test project that imports the BOM and lists managed dependencies
cat > /tmp/test-pom.xml << 'TESTPOM'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    
    <groupId>test.analysis</groupId>
    <artifactId>bom-analyzer</artifactId>
    <version>1.0.0</version>
    <packaging>pom</packaging>
    
    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>org.apache.camel</groupId>
                <artifactId>camel-bom</artifactId>
                <version>4.18.1</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>
    
    <!-- Add some actual dependencies to trigger resolution -->
    <dependencies>
        <dependency>
            <groupId>org.apache.camel</groupId>
            <artifactId>camel-core</artifactId>
        </dependency>
    </dependencies>
</project>
TESTPOM

echo "Created test POM at /tmp/test-pom.xml"
echo ""
echo "Running Maven dependency:tree..."
cd /tmp
mvn -f test-pom.xml dependency:tree -DoutputFile=dep-tree.txt 2>&1 | tail -20

if [ -f dep-tree.txt ]; then
    echo ""
    echo "Dependencies found:"
    cat dep-tree.txt | head -30
else
    echo "ERROR: dependency:tree failed"
fi

echo ""
echo "Trying dependency:list..."
mvn -f test-pom.xml dependency:list -DoutputFile=dep-list.txt 2>&1 | tail -10

if [ -f dep-list.txt ]; then
    echo ""
    echo "Dependencies from list:"
    cat dep-list.txt | grep "org.apache.camel" | head -20
fi
