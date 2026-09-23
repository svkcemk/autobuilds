# Camel 4.22.0 Third-Party Dependencies - Final Productization Report

**Generated**: 2026-08-14
**Camel Version**: 4.22.0.redhat-00001
**Source**: PNC Builds Repository (Indy)

---

## Executive Summary

| Metric | Count | Percentage |
|--------|-------|------------|
| **Total Third-Party Dependencies** | 122 | 100% |
| **Already Productized** | 36 | 29.5% |
| **Need Productization** | 86 | 70.5% |

---

## ✅ Already Productized Dependencies (36)

These dependencies already have .redhat-00001 versions in PNC builds:

### Core Libraries (7)
- ✓ commons-codec:commons-codec:1.22.1.redhat-00001
- ✓ commons-io:commons-io:2.20.0.redhat-00001
- ✓ commons-logging:commons-logging:1.3.5.redhat-00001
- ✓ org.apache.commons:commons-csv:1.14.1.redhat-00001
- ✓ org.apache.commons:commons-lang3:3.17.0.redhat-00001
- ✓ org.apache.commons:commons-pool2:2.13.1.redhat-00001
- ✓ org.slf4j:slf4j-api:2.0.18.redhat-00001

### Jakarta EE APIs (8)
- ✓ jakarta.activation:jakarta.activation-api:2.1.4.redhat-00001
- ✓ jakarta.annotation:jakarta.annotation-api:3.0.0.redhat-00001
- ✓ jakarta.jms:jakarta.jms-api:3.1.0.redhat-00001
- ✓ jakarta.mail:jakarta.mail-api:2.1.5.redhat-00001
- ✓ jakarta.servlet:jakarta.servlet-api:6.1.0.redhat-00001
- ✓ jakarta.xml.bind:jakarta.xml.bind-api:4.0.5.redhat-00001
- ✓ jakarta.xml.soap:jakarta.xml.soap-api:3.0.2.redhat-00001
- ✓ jakarta.xml.ws:jakarta.xml.ws-api:4.0.3.redhat-00001

### XML Processing (6)
- ✓ com.fasterxml.woodstox:woodstox-core:7.2.1.redhat-00001
- ✓ com.sun.istack:istack-commons-runtime:4.1.2.redhat-00001
- ✓ org.codehaus.woodstox:stax2-api:4.3.0.redhat-00001
- ✓ org.glassfish.jaxb:jaxb-core:4.0.9.redhat-00001
- ✓ org.glassfish.jaxb:jaxb-runtime:4.0.9.redhat-00001
- ✓ org.glassfish.jaxb:txw2:4.0.9.redhat-00001

### Messaging (3)
- ✓ org.apache.qpid:proton-j:0.34.1.redhat-00001
- ✓ org.apache.qpid:qpid-jms-client:2.10.0.redhat-00001
- ✓ org.eclipse.angus:angus-mail:2.0.5.redhat-00001

### HTTP & Networking (2)
- ✓ org.apache.httpcomponents.core5:httpcore5:5.4.3.redhat-00001
- ✓ org.apache.httpcomponents.core5:httpcore5-h2:5.4.3.redhat-00001

### Monitoring (2)
- ✓ io.micrometer:micrometer-commons:1.16.6.redhat-00001
- ✓ io.micrometer:micrometer-observation:1.16.6.redhat-00001

### Utilities (8)
- ✓ org.apache.velocity:velocity-engine-core:2.4.1.redhat-00001
- ✓ org.apache.ws.xmlschema:xmlschema-core:2.3.2.redhat-00001
- ✓ org.eclipse.angus:angus-activation:2.0.3.redhat-00001
- ✓ org.jspecify:jspecify:1.0.0.redhat-00001
- ✓ org.ow2.asm:asm:9.10.1.redhat-00001
- ✓ org.quartz-scheduler:quartz:2.5.2.redhat-00001
- ✓ org.reactivestreams:reactive-streams:1.0.4.redhat-00001
- ✓ software.amazon.eventstream:eventstream:1.0.1.redhat-00001

---

## ❌ Need Productization (86 dependencies)

### Critical Priority - Core Libraries (3)
```
at.yawk.lz4:lz4-java:1.11.1
com.mchange:c3p0:0.14.1
com.mchange:mchange-commons-java:0.6.1
```

### High Priority - Netty (All 19 components)
```
io.netty:netty-buffer:4.2.16.Final
io.netty:netty-codec-base:4.2.16.Final
io.netty:netty-codec-compression:4.2.16.Final
io.netty:netty-codec-http:4.2.16.Final
io.netty:netty-codec-http2:4.1.136.Final
io.netty:netty-codec-marshalling:4.2.16.Final
io.netty:netty-codec-protobuf:4.2.16.Final
io.netty:netty-codec:4.2.16.Final
io.netty:netty-common:4.2.16.Final
io.netty:netty-handler:4.2.16.Final
io.netty:netty-resolver:4.2.16.Final
io.netty:netty-transport-classes-epoll:4.2.16.Final
io.netty:netty-transport-classes-kqueue:4.1.130.Final
io.netty:netty-transport-native-epoll:4.2.16.Final
io.netty:netty-transport-native-kqueue:4.2.16.Final
io.netty:netty-transport-native-unix-common:4.2.16.Final
io.netty:netty-transport:4.2.16.Final
```

### High Priority - Jackson (5)
```
com.fasterxml.jackson.core:jackson-annotations:2.22
com.fasterxml.jackson.core:jackson-core:2.22.1
com.fasterxml.jackson.core:jackson-databind:2.22.1
com.fasterxml.jackson.dataformat:jackson-dataformat-yaml:2.22.1
```

### High Priority - Apache CXF 4.2.3 (All 11 components)
**Note**: Camel 4.22.0 uses CXF **4.2.3** (not 4.2.2)

```
org.apache.cxf:cxf-core:4.2.3
org.apache.cxf:cxf-rt-bindings-soap:4.2.3
org.apache.cxf:cxf-rt-bindings-xml:4.2.3
org.apache.cxf:cxf-rt-databinding-jaxb:4.2.3
org.apache.cxf:cxf-rt-features-logging:4.2.3
org.apache.cxf:cxf-rt-frontend-jaxws:4.2.3
org.apache.cxf:cxf-rt-frontend-simple:4.2.3
org.apache.cxf:cxf-rt-transports-http:4.2.3
org.apache.cxf:cxf-rt-ws-addr:4.2.3
org.apache.cxf:cxf-rt-ws-policy:4.2.3
org.apache.cxf:cxf-rt-wsdl:4.2.3
```

### Medium Priority - Spring Framework (9)
```
org.springframework:spring-aop:7.0.8
org.springframework:spring-beans:7.0.8
org.springframework:spring-context:7.0.8
org.springframework:spring-core:7.0.8
org.springframework:spring-expression:7.0.8
org.springframework:spring-jdbc:7.0.8
org.springframework:spring-jms:7.0.8
org.springframework:spring-messaging:7.0.8
org.springframework:spring-tx:7.0.8
```

### Medium Priority - AWS SDK (All 29 components)
```
software.amazon.awssdk:annotations:2.50.2
software.amazon.awssdk:apache5-client:2.50.2
software.amazon.awssdk:arns:2.50.2
software.amazon.awssdk:auth:2.50.2
software.amazon.awssdk:aws-core:2.50.2
software.amazon.awssdk:aws-query-protocol:2.50.2
software.amazon.awssdk:aws-xml-protocol:2.50.2
software.amazon.awssdk:checksums-spi:2.50.2
software.amazon.awssdk:checksums:2.50.2
software.amazon.awssdk:crt-core:2.50.2
software.amazon.awssdk:endpoints-spi:2.50.2
software.amazon.awssdk:http-auth-aws-eventstream:2.50.2
software.amazon.awssdk:http-auth-aws:2.50.2
software.amazon.awssdk:http-auth-spi:2.50.2
software.amazon.awssdk:http-auth:2.50.2
software.amazon.awssdk:http-client-spi:2.50.2
software.amazon.awssdk:identity-spi:2.50.2
software.amazon.awssdk:json-utils:2.50.2
software.amazon.awssdk:metrics-spi:2.50.2
software.amazon.awssdk:netty-nio-client:2.50.2
software.amazon.awssdk:profiles:2.50.2
software.amazon.awssdk:protocol-core:2.50.2
software.amazon.awssdk:regions:2.50.2
software.amazon.awssdk:retries-spi:2.50.2
software.amazon.awssdk:retries:2.50.2
software.amazon.awssdk:s3:2.50.2
software.amazon.awssdk:sdk-core:2.50.2
software.amazon.awssdk:sts:2.50.2
software.amazon.awssdk:third-party-jackson-core:2.50.2
software.amazon.awssdk:utils-lite:2.50.2
software.amazon.awssdk:utils:2.50.2
```

### Lower Priority - Miscellaneous (10)
```
com.apptasticsoftware:rssreader:3.12.0
com.github.mwiede:jsch:2.28.6
commons-net:commons-net:3.13.0
org.apache.activemq:activemq-client-jakarta:5.19.9
org.apache.httpcomponents.client5:httpclient5:5.6.3
org.apache.kafka:kafka-clients:4.3.1
org.apache.neethi:neethi:3.2.3
org.fusesource.hawtbuf:hawtbuf:1.11
org.yaml:snakeyaml:2.5
wsdl4j:wsdl4j:1.6.3
xml-resolver:xml-resolver:1.2
```

---

## Recommended Build Strategy

### Phase 1: Build Netty (19 deps) - CRITICAL
Netty is used by many other components. Build all Netty modules first.

**Estimated Time**: 1-2 days

### Phase 2: Build CXF (11 deps) - HIGH PRIORITY
Required for camel-cxf-soap and web services support.

**Estimated Time**: 1 day

### Phase 3: Build Jackson (5 deps) - HIGH PRIORITY
Core data format library used throughout Camel.

**Estimated Time**: 4-6 hours

### Phase 4: Build Spring (9 deps) - MEDIUM PRIORITY
Required for Spring integration components.

**Estimated Time**: 1 day

### Phase 5: Build AWS SDK (29 deps) - OPTIONAL
Only needed if using camel-aws components.

**Estimated Time**: 2-3 days

### Phase 6: Build Remaining (13 deps) - LOW PRIORITY
Miscellaneous dependencies for specific use cases.

**Estimated Time**: 1 day

---

## Total Effort Estimate

- **If building all 86 dependencies**: 6-8 days
- **If building only critical (Netty + CXF + Jackson)**: 2-3 days
- **If building only Netty**: 1-2 days

---

## Recommendation

### Option 1: Minimal Productization (Recommended)
Build only the most critical dependencies:
- ✅ Netty (19 deps) - Used by many components
- ✅ CXF (11 deps) - Required for web services
- ✅ Jackson (5 deps) - Core data format library

**Total**: 35 dependencies, 2-3 days effort

### Option 2: Comprehensive Productization
Build all 86 dependencies for complete control.

**Total**: 86 dependencies, 6-8 days effort

### Option 3: Use Upstream (Fastest)
Use the 36 already-productized dependencies and let Maven resolve the remaining 86 from Maven Central.

**Total**: 0 additional builds, immediate availability

---

## Next Steps

1. **Review this report** and decide on build strategy
2. **Generate build configs** for selected dependencies:
   ```bash
   # Create a file with dependencies to build
   cat > deps-to-build.txt <<EOF
   # Add GAVs here, one per line
   io.netty:netty-common:4.2.16.Final
   io.netty:netty-buffer:4.2.16.Final
   # ... etc
   EOF
   
   # Generate build configs
   ./generate_build_configs.sh -r deps-to-build.txt \
     -c build-config-camel-4.22.0.yaml \
     -o camel-selected-builds \
     --format both
   ```

3. **Create builds in PNC** using bacon CLI
4. **Monitor and verify** build success

---

## Files Generated

- `camel-productized-check-results.txt` - Full check results
- `CAMEL_PRODUCTIZATION_FINAL_REPORT.md` - This report

---

**Analysis Complete** - Ready for build decision
