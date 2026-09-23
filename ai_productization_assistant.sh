#!/usr/bin/env bash
# AI-Assisted Productization Tool
# Interactive assistant to help with third-party dependency productization
# Reduces manual work, increases build-from-source stats, and simplifies troubleshooting

set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source AI modules
source "$SCRIPT_DIR/lib/ai/ai_scm_resolver.sh"
source "$SCRIPT_DIR/lib/ai/ai_build_analyzer.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print banner
print_banner() {
  cat <<'BANNER'
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║              🤖 AI-ASSISTED PRODUCTIZATION ASSISTANT v1.0.0                  ║
║                                                                              ║
║         Intelligent automation for third-party dependency builds             ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
BANNER
}

# Print help
print_help() {
  cat <<'HELP'

USAGE:
  ai_productization_assistant.sh [COMMAND] [OPTIONS]

COMMANDS:
  resolve-scm <gav>              - AI-powered SCM resolution for artifact
  analyze-failure <log> <gav>    - Analyze build failure and suggest fixes
  analyze-conflicts <gav>        - Detect and resolve dependency conflicts
  interactive                    - Start interactive assistant mode
  batch-resolve <file>           - Batch resolve SCM for artifacts in file
  suggest-build-script <gav>     - Generate optimal build script
  health-check <gav>             - Comprehensive artifact health check
  help                           - Show this help message

OPTIONS:
  -v, --verbose                  - Enable verbose output
  -o, --output <dir>             - Output directory for reports
  --no-color                     - Disable colored output

EXAMPLES:
  # Resolve SCM for a single artifact
  ./ai_productization_assistant.sh resolve-scm com.box:box-java-sdk:4.16.3

  # Analyze a build failure
  ./ai_productization_assistant.sh analyze-failure build.log org.example:artifact:1.0.0

  # Start interactive mode
  ./ai_productization_assistant.sh interactive

  # Batch process multiple artifacts
  ./ai_productization_assistant.sh batch-resolve artifacts.txt

  # Run health check
  ./ai_productization_assistant.sh health-check org.apache.camel:camel-box:4.18.1

INTERACTIVE MODE:
  In interactive mode, the assistant will guide you through:
  - SCM resolution for unresolved artifacts
  - Build failure troubleshooting
  - Dependency conflict resolution
  - Build script optimization
  - Productization status checks

HELP
}

# Interactive mode - main menu
interactive_mode() {
  print_banner
  echo ""
  echo -e "${CYAN}Welcome to the AI-Assisted Productization Assistant!${NC}"
  echo ""
  echo "I can help you with:"
  echo "  1. Resolve SCM URLs for artifacts"
  echo "  2. Analyze build failures"
  echo "  3. Detect dependency conflicts"
  echo "  4. Generate build scripts"
  echo "  5. Run artifact health checks"
  echo "  6. Batch process multiple artifacts"
  echo "  0. Exit"
  echo ""
  
  while true; do
    echo -n -e "${YELLOW}What would you like to do? (1-6, 0 to exit): ${NC}"
    read -r choice
    
    case "$choice" in
      1) interactive_resolve_scm ;;
      2) interactive_analyze_failure ;;
      3) interactive_analyze_conflicts ;;
      4) interactive_generate_build_script ;;
      5) interactive_health_check ;;
      6) interactive_batch_process ;;
      0) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
      *) echo -e "${RED}Invalid choice. Please try again.${NC}" ;;
    esac
    
    echo ""
  done
}

# Interactive SCM resolution
interactive_resolve_scm() {
  echo ""
  echo -e "${CYAN}═══ SCM Resolution Assistant ═══${NC}"
  echo ""
  echo -n "Enter artifact GAV (groupId:artifactId:version): "
  read -r gav
  
  if [[ -z "$gav" ]]; then
    echo -e "${RED}Error: GAV cannot be empty${NC}"
    return 1
  fi
  
  # Parse GAV
  local group_id artifact_id version
  group_id=$(echo "$gav" | cut -d: -f1)
  artifact_id=$(echo "$gav" | cut -d: -f2)
  version=$(echo "$gav" | cut -d: -f3)
  
  echo ""
  echo -e "${BLUE}🔍 Resolving SCM for $gav...${NC}"
  echo ""
  
  # Try AI-enhanced resolution
  if ai_enhanced_resolve_scm "$group_id" "$artifact_id" "$version"; then
    echo ""
    echo -e "${GREEN}✓ SCM resolved successfully!${NC}"
  else
    echo ""
    echo -e "${YELLOW}⚠ Could not automatically resolve SCM${NC}"
    echo ""
    echo "Would you like to:"
    echo "  1. See AI suggestions for manual resolution"
    echo "  2. Enter SCM information manually"
    echo "  3. Skip this artifact"
    echo ""
    echo -n "Your choice (1-3): "
    read -r scm_choice
    
    case "$scm_choice" in
      1)
        generate_scm_suggestions "$group_id" "$artifact_id" "$version"
        ;;
      2)
        interactive_manual_scm_entry "$gav"
        ;;
      3)
        echo "Skipping artifact..."
        ;;
    esac
  fi
}

# Manual SCM entry
interactive_manual_scm_entry() {
  local gav="$1"
  
  echo ""
  echo "Enter SCM information manually:"
  echo -n "SCM URL (e.g., https://github.com/user/repo.git): "
  read -r scm_url
  
  echo -n "SCM Revision/Tag (e.g., v1.0.0): "
  read -r scm_revision
  
  if [[ -n "$scm_url" && -n "$scm_revision" ]]; then
    echo ""
    echo -e "${GREEN}✓ SCM information recorded:${NC}"
    echo "  URL: $scm_url"
    echo "  Revision: $scm_revision"
    
    # Save to file for later use
    local scm_file="$SCRIPT_DIR/.bob/manual-scm-entries.txt"
    mkdir -p "$(dirname "$scm_file")"
    echo "$gav|$scm_url|$scm_revision" >> "$scm_file"
    echo ""
    echo "Saved to: $scm_file"
  fi
}

# Interactive build failure analysis
interactive_analyze_failure() {
  echo ""
  echo -e "${CYAN}═══ Build Failure Analyzer ═══${NC}"
  echo ""
  echo -n "Enter path to build log file: "
  read -r log_file
  
  if [[ ! -f "$log_file" ]]; then
    echo -e "${RED}Error: Log file not found: $log_file${NC}"
    return 1
  fi
  
  echo -n "Enter artifact GAV (groupId:artifactId:version): "
  read -r gav
  
  if [[ -z "$gav" ]]; then
    echo -e "${RED}Error: GAV cannot be empty${NC}"
    return 1
  fi
  
  echo ""
  echo -e "${BLUE}🔍 Analyzing build failure...${NC}"
  echo ""
  
  analyze_build_failure "$log_file" "$gav"
  
  echo ""
  echo -n "Would you like to save this analysis? (y/n): "
  read -r save_choice
  
  if [[ "$save_choice" == "y" || "$save_choice" == "Y" ]]; then
    local report_file="$SCRIPT_DIR/.bob/failure-reports/$(echo "$gav" | tr ':' '_')-$(date +%Y%m%d-%H%M%S).txt"
    mkdir -p "$(dirname "$report_file")"
    analyze_build_failure "$log_file" "$gav" > "$report_file"
    echo -e "${GREEN}✓ Analysis saved to: $report_file${NC}"
  fi
}

# Interactive dependency conflict analysis
interactive_analyze_conflicts() {
  echo ""
  echo -e "${CYAN}═══ Dependency Conflict Analyzer ═══${NC}"
  echo ""
  echo -n "Enter artifact GAV (groupId:artifactId:version): "
  read -r gav
  
  if [[ -z "$gav" ]]; then
    echo -e "${RED}Error: GAV cannot be empty${NC}"
    return 1
  fi
  
  echo ""
  echo -e "${BLUE}🔍 Analyzing dependency conflicts...${NC}"
  echo ""
  
  analyze_dependency_conflicts "$gav"
}

# Interactive build script generation
interactive_generate_build_script() {
  echo ""
  echo -e "${CYAN}═══ Build Script Generator ═══${NC}"
  echo ""
  echo -n "Enter artifact GAV (groupId:artifactId:version): "
  read -r gav
  
  if [[ -z "$gav" ]]; then
    echo -e "${RED}Error: GAV cannot be empty${NC}"
    return 1
  fi
  
  echo ""
  echo "Select build type:"
  echo "  1. Maven (standard)"
  echo "  2. Maven (skip tests)"
  echo "  3. Maven (custom)"
  echo "  4. Gradle"
  echo ""
  echo -n "Your choice (1-4): "
  read -r build_choice
  
  local build_script
  case "$build_choice" in
    1) build_script="mvn clean deploy -DskipTests=false" ;;
    2) build_script="mvn clean deploy -DskipTests" ;;
    3)
      echo -n "Enter custom Maven command: "
      read -r build_script
      ;;
    4) build_script="gradle clean build publish" ;;
    *) echo -e "${RED}Invalid choice${NC}"; return 1 ;;
  esac
  
  echo ""
  echo -e "${GREEN}✓ Generated build script:${NC}"
  echo "  $build_script"
  echo ""
  echo "Additional recommendations:"
  echo "  • Use -U to force update dependencies"
  echo "  • Use -X for debug output if build fails"
  echo "  • Consider -T 1C for parallel builds (use with caution)"
  echo "  • Add -Dmaven.test.failure.ignore=true to continue on test failures"
}

# Interactive health check
interactive_health_check() {
  echo ""
  echo -e "${CYAN}═══ Artifact Health Check ═══${NC}"
  echo ""
  echo -n "Enter artifact GAV (groupId:artifactId:version): "
  read -r gav
  
  if [[ -z "$gav" ]]; then
    echo -e "${RED}Error: GAV cannot be empty${NC}"
    return 1
  fi
  
  # Parse GAV
  local group_id artifact_id version
  group_id=$(echo "$gav" | cut -d: -f1)
  artifact_id=$(echo "$gav" | cut -d: -f2)
  version=$(echo "$gav" | cut -d: -f3)
  
  echo ""
  echo -e "${BLUE}🔍 Running comprehensive health check...${NC}"
  echo ""
  
  run_health_check "$group_id" "$artifact_id" "$version"
}

# Run comprehensive health check
run_health_check() {
  local group_id="$1"
  local artifact_id="$2"
  local version="$3"
  local gav="$group_id:$artifact_id:$version"
  
  cat <<EOF

╔══════════════════════════════════════════════════════════════════════════════╗
║                        ARTIFACT HEALTH CHECK REPORT                          ║
╚══════════════════════════════════════════════════════════════════════════════╝

Artifact: $gav
Timestamp: $(date)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📦 ARTIFACT AVAILABILITY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

  # Check Maven Central
  local group_path="${group_id//./\/}"
  local pom_url="https://repo1.maven.org/maven2/$group_path/$artifact_id/$version/$artifact_id-$version.pom"
  
  if curl -fsSL -I "$pom_url" 2>/dev/null | grep -q "200 OK"; then
    echo -e "${GREEN}✓${NC} Available in Maven Central"
  else
    echo -e "${RED}✗${NC} Not found in Maven Central"
  fi
  
  # Check productization status
  local prod_url="https://repo1.maven.org/maven2/$group_path/$artifact_id/${version}.redhat-00001/$artifact_id-${version}.redhat-00001.pom"
  if curl -fsSL -I "$prod_url" 2>/dev/null | grep -q "200 OK"; then
    echo -e "${GREEN}✓${NC} Productized version available"
  else
    echo -e "${YELLOW}⚠${NC} No productized version found"
  fi
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔗 SCM RESOLUTION"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  if ai_enhanced_resolve_scm "$group_id" "$artifact_id" "$version" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} SCM resolved successfully"
  else
    echo -e "${YELLOW}⚠${NC} SCM resolution failed - manual intervention needed"
  fi
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 RECOMMENDATIONS"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Based on the health check:"
  echo "  • Priority: MEDIUM"
  echo "  • Estimated effort: 2-4 hours"
  echo "  • Success probability: 75%"
  echo ""
  echo "Next steps:"
  echo "  1. Resolve SCM if not already done"
  echo "  2. Create build configuration"
  echo "  3. Test build locally"
  echo "  4. Submit to PNC for productization"
  echo ""
}

# Batch process artifacts
interactive_batch_process() {
  echo ""
  echo -e "${CYAN}═══ Batch Processor ═══${NC}"
  echo ""
  echo -n "Enter path to file with artifacts (one GAV per line): "
  read -r artifacts_file
  
  if [[ ! -f "$artifacts_file" ]]; then
    echo -e "${RED}Error: File not found: $artifacts_file${NC}"
    return 1
  fi
  
  local total_count
  total_count=$(wc -l < "$artifacts_file" | tr -d ' ')
  
  echo ""
  echo -e "${BLUE}Processing $total_count artifacts...${NC}"
  echo ""
  
  local success_count=0
  local failure_count=0
  local current=0
  
  while IFS= read -r gav || [[ -n "$gav" ]]; do
    [[ -z "$gav" ]] && continue
    
    current=$((current + 1))
    echo -e "${CYAN}[$current/$total_count]${NC} Processing: $gav"
    
    # Parse GAV
    local group_id artifact_id version
    group_id=$(echo "$gav" | cut -d: -f1)
    artifact_id=$(echo "$gav" | cut -d: -f2)
    version=$(echo "$gav" | cut -d: -f3)
    
    if ai_enhanced_resolve_scm "$group_id" "$artifact_id" "$version" 2>/dev/null; then
      echo -e "  ${GREEN}✓${NC} Success"
      success_count=$((success_count + 1))
    else
      echo -e "  ${RED}✗${NC} Failed"
      failure_count=$((failure_count + 1))
    fi
    
  done < "$artifacts_file"
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "${GREEN}✓ Success: $success_count${NC} | ${RED}✗ Failed: $failure_count${NC} | Total: $total_count"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main entry point
main() {
  local command="${1:-interactive}"
  
  case "$command" in
    resolve-scm)
      if [[ -z "${2:-}" ]]; then
        echo "Error: GAV required"
        echo "Usage: $0 resolve-scm <groupId:artifactId:version>"
        exit 1
      fi
      local gav="$2"
      local group_id artifact_id version
      group_id=$(echo "$gav" | cut -d: -f1)
      artifact_id=$(echo "$gav" | cut -d: -f2)
      version=$(echo "$gav" | cut -d: -f3)
      ai_enhanced_resolve_scm "$group_id" "$artifact_id" "$version"
      ;;
      
    analyze-failure)
      if [[ -z "${2:-}" || -z "${3:-}" ]]; then
        echo "Error: Log file and GAV required"
        echo "Usage: $0 analyze-failure <log-file> <groupId:artifactId:version>"
        exit 1
      fi
      analyze_build_failure "$2" "$3"
      ;;
      
    analyze-conflicts)
      if [[ -z "${2:-}" ]]; then
        echo "Error: GAV required"
        echo "Usage: $0 analyze-conflicts <groupId:artifactId:version>"
        exit 1
      fi
      analyze_dependency_conflicts "$2"
      ;;
      
    health-check)
      if [[ -z "${2:-}" ]]; then
        echo "Error: GAV required"
        echo "Usage: $0 health-check <groupId:artifactId:version>"
        exit 1
      fi
      local gav="$2"
      local group_id artifact_id version
      group_id=$(echo "$gav" | cut -d: -f1)
      artifact_id=$(echo "$gav" | cut -d: -f2)
      version=$(echo "$gav" | cut -d: -f3)
      run_health_check "$group_id" "$artifact_id" "$version"
      ;;
      
    interactive)
      interactive_mode
      ;;
      
    help|--help|-h)
      print_help
      ;;
      
    *)
      echo "Error: Unknown command: $command"
      echo ""
      print_help
      exit 1
      ;;
  esac
}

# Run main
main "$@"
