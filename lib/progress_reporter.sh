#!/usr/bin/env bash
# Progress Reporting Library
# Provides enhanced progress tracking with visual feedback
# Part of the PNC Build Config Generator UX improvements

set -euo pipefail

# Colors and symbols
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Unicode symbols (with ASCII fallbacks)
if [[ "${TERM:-}" == *"256color"* ]] || [[ "${TERM:-}" == "xterm"* ]]; then
  CHECKMARK="✓"
  CROSSMARK="✗"
  ARROW="→"
  SPINNER=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
else
  CHECKMARK="+"
  CROSSMARK="x"
  ARROW="->"
  SPINNER=("-" "\\" "|" "/")
fi

# Progress bar characters
PROGRESS_FILLED="━"
PROGRESS_EMPTY="─"
PROGRESS_WIDTH=20

# Global state
CURRENT_STEP=0
TOTAL_STEPS=0
STEP_START_TIME=0

# Initialize progress tracking
# Args: total_steps
progress_init() {
  TOTAL_STEPS="$1"
  CURRENT_STEP=0
  echo "" >&2
}

# Start a new step
# Args: step_name
progress_step() {
  local step_name="$1"
  ((CURRENT_STEP++))
  STEP_START_TIME=$(date +%s)
  
  printf "${BLUE}[%d/%d]${NC} %s... " "$CURRENT_STEP" "$TOTAL_STEPS" "$step_name" >&2
}

# Complete current step with success
# Args: [message]
progress_success() {
  local message="${1:-}"
  local elapsed=$(($(date +%s) - STEP_START_TIME))
  
  if [[ -n "$message" ]]; then
    printf "${GREEN}${CHECKMARK}${NC} %s (${elapsed}s)\n" "$message" >&2
  else
    printf "${GREEN}${CHECKMARK}${NC} (${elapsed}s)\n" >&2
  fi
}

# Complete current step with failure
# Args: [message]
progress_fail() {
  local message="${1:-}"
  local elapsed=$(($(date +%s) - STEP_START_TIME))
  
  if [[ -n "$message" ]]; then
    printf "${RED}${CROSSMARK}${NC} %s (${elapsed}s)\n" "$message" >&2
  else
    printf "${RED}${CROSSMARK}${NC} (${elapsed}s)\n" >&2
  fi
}

# Show progress bar
# Args: current total [prefix]
progress_bar() {
  local current="$1"
  local total="$2"
  local prefix="${3:-Progress}"
  
  local percent=$((current * 100 / total))
  local filled=$((current * PROGRESS_WIDTH / total))
  local empty=$((PROGRESS_WIDTH - filled))
  
  local bar=""
  for ((i=0; i<filled; i++)); do
    bar+="$PROGRESS_FILLED"
  done
  for ((i=0; i<empty; i++)); do
    bar+="$PROGRESS_EMPTY"
  done
  
  printf "\r${BLUE}[%3d%%]${NC} %s ${bar} %d/%d" \
    "$percent" "$prefix" "$current" "$total" >&2
}

# Show spinner with message
# Args: message
# Usage: Call repeatedly in a loop, will animate spinner
progress_spinner() {
  local message="$1"
  local idx=$(($(date +%s) % ${#SPINNER[@]}))
  
  printf "\r${BLUE}${SPINNER[$idx]}${NC} %s" "$message" >&2
}

# Clear current line
progress_clear_line() {
  printf "\r\033[K" >&2
}

# Show detailed progress with multiple metrics
# Args: current total success failed [message]
progress_detailed() {
  local current="$1"
  local total="$2"
  local success="$3"
  local failed="$4"
  local message="${5:-Processing}"
  
  local percent=$((current * 100 / total))
  local filled=$((current * PROGRESS_WIDTH / total))
  local empty=$((PROGRESS_WIDTH - filled))
  
  local bar=""
  for ((i=0; i<filled; i++)); do
    bar+="$PROGRESS_FILLED"
  done
  for ((i=0; i<empty; i++)); do
    bar+="$PROGRESS_EMPTY"
  done
  
  printf "\r${BLUE}[%3d%%]${NC} %s ${bar} %d/%d (${GREEN}${CHECKMARK} %d${NC} ${RED}${CROSSMARK} %d${NC})" \
    "$percent" "$message" "$current" "$total" "$success" "$failed" >&2
}

# Show time estimate
# Args: current total elapsed_seconds
progress_estimate() {
  local current="$1"
  local total="$2"
  local elapsed="$3"
  
  if [[ $current -eq 0 ]]; then
    echo "Estimating..."
    return
  fi
  
  local rate=$((elapsed / current))
  local remaining=$((total - current))
  local eta=$((remaining * rate))
  
  local eta_min=$((eta / 60))
  local eta_sec=$((eta % 60))
  
  if [[ $eta_min -gt 0 ]]; then
    echo "ETA: ${eta_min}m ${eta_sec}s"
  else
    echo "ETA: ${eta_sec}s"
  fi
}

# Show summary at the end
# Args: total_items success_count failed_count elapsed_seconds
progress_summary() {
  local total="$1"
  local success="$2"
  local failed="$3"
  local elapsed="$4"
  
  echo "" >&2
  echo -e "${BLUE}=== Summary ===${NC}" >&2
  echo -e "  Total Items: $total" >&2
  echo -e "  ${GREEN}Successful: $success${NC}" >&2
  
  if [[ $failed -gt 0 ]]; then
    echo -e "  ${RED}Failed: $failed${NC}" >&2
  fi
  
  local elapsed_min=$((elapsed / 60))
  local elapsed_sec=$((elapsed % 60))
  
  if [[ $elapsed_min -gt 0 ]]; then
    echo -e "  Time: ${elapsed_min}m ${elapsed_sec}s" >&2
  else
    echo -e "  Time: ${elapsed_sec}s" >&2
  fi
  
  if [[ $success -gt 0 ]]; then
    local rate=$((elapsed / success))
    echo -e "  Rate: ${rate}s per item" >&2
  fi
}

# Show hierarchical progress (for nested operations)
# Args: level message
progress_nested() {
  local level="$1"
  local message="$2"
  
  local indent=""
  for ((i=0; i<level; i++)); do
    indent+="  "
  done
  
  echo -e "${indent}${BLUE}${ARROW}${NC} $message" >&2
}

# Show table header
# Args: col1_width col2_width col3_width header1 header2 header3
progress_table_header() {
  local w1="$1"
  local w2="$2"
  local w3="$3"
  local h1="$4"
  local h2="$5"
  local h3="$6"
  
  printf "${BLUE}%-${w1}s  %-${w2}s  %-${w3}s${NC}\n" "$h1" "$h2" "$h3" >&2
  
  local line=""
  for ((i=0; i<w1+w2+w3+4; i++)); do
    line+="-"
  done
  echo "$line" >&2
}

# Show table row
# Args: col1_width col2_width col3_width value1 value2 value3
progress_table_row() {
  local w1="$1"
  local w2="$2"
  local w3="$3"
  local v1="$4"
  local v2="$5"
  local v3="$6"
  
  printf "%-${w1}s  %-${w2}s  %-${w3}s\n" "$v1" "$v2" "$v3" >&2
}

# Show live updating counter
# Args: label value [unit]
progress_counter() {
  local label="$1"
  local value="$2"
  local unit="${3:-}"
  
  printf "\r${BLUE}%s:${NC} %s %s" "$label" "$value" "$unit" >&2
}

# Format duration in human-readable format
# Args: seconds
format_duration() {
  local seconds="$1"
  
  if [[ $seconds -lt 60 ]]; then
    echo "${seconds}s"
  elif [[ $seconds -lt 3600 ]]; then
    local min=$((seconds / 60))
    local sec=$((seconds % 60))
    echo "${min}m ${sec}s"
  else
    local hour=$((seconds / 3600))
    local min=$(((seconds % 3600) / 60))
    echo "${hour}h ${min}m"
  fi
}

# Format file size in human-readable format
# Args: bytes
format_size() {
  local bytes="$1"
  
  if [[ $bytes -lt 1024 ]]; then
    echo "${bytes}B"
  elif [[ $bytes -lt 1048576 ]]; then
    echo "$((bytes / 1024))KB"
  elif [[ $bytes -lt 1073741824 ]]; then
    echo "$((bytes / 1048576))MB"
  else
    echo "$((bytes / 1073741824))GB"
  fi
}

# Show phase header
# Args: phase_number phase_name
progress_phase() {
  local phase_num="$1"
  local phase_name="$2"
  
  echo "" >&2
  echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}" >&2
  echo -e "${BLUE}║${NC} Phase $phase_num: $phase_name" >&2
  echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}" >&2
  echo "" >&2
}

# Example usage function (for documentation)
progress_example() {
  cat <<'EXAMPLE'
# Example 1: Simple step-by-step progress
progress_init 5
progress_step "Analyzing dependencies"
sleep 1
progress_success "Found 45 dependencies"

progress_step "Resolving SCM URLs"
sleep 1
progress_success "Resolved 40/45"

# Example 2: Progress bar
for i in {1..100}; do
  progress_bar $i 100 "Processing"
  sleep 0.05
done
echo ""

# Example 3: Detailed progress with metrics
for i in {1..50}; do
  progress_detailed $i 50 $((i-2)) 2 "Processing items"
  sleep 0.1
done
echo ""

# Example 4: Summary
progress_summary 50 48 2 120

EXAMPLE
}
