#!/usr/bin/env bash
# Timeout Wrapper for macOS/Linux Compatibility
# Provides a portable timeout function that works on both macOS and Linux

# Portable timeout function
# Args: timeout_seconds command [args...]
# Returns: command exit code, or 124 if timeout
run_with_timeout() {
  local timeout_seconds="$1"
  shift
  local command=("$@")
  
  # Try GNU timeout first (Linux)
  if command -v timeout &> /dev/null; then
    timeout "$timeout_seconds" "${command[@]}"
    return $?
  fi
  
  # Fallback for macOS: manual timeout implementation
  "${command[@]}" &
  local pid=$!
  
  # Start timeout killer in background
  (
    sleep "$timeout_seconds"
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null
    fi
  ) &
  local killer_pid=$!
  
  # Wait for command to complete
  local exit_code=0
  if wait "$pid" 2>/dev/null; then
    exit_code=$?
  else
    exit_code=124  # Timeout exit code
  fi
  
  # Kill the timeout killer if command finished
  kill -9 "$killer_pid" 2>/dev/null
  wait "$killer_pid" 2>/dev/null
  
  return $exit_code
}

# Export for use in subshells
export -f run_with_timeout
