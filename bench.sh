#!/bin/bash

################################################################################
# LLM Inference Performance Benchmark Script
################################################################################
#
# DESCRIPTION:
#   A comprehensive benchmarking tool for comparing inference performance
#   between llama.cpp and vLLM serving backends. Measures response latency,
#   throughput (tokens/second), and provides detailed statistical analysis.
#
# AUTHOR:
#   Minsu Kim 
#   https://github.com/minkim26
#
# VERSION:
#   2.0.0
#
# CREATED:
#   2025-06-12
#
# LAST MODIFIED:
#   2025-06-20
#
# COMPATIBILITY:
#   - Bash 4.0+
#   - Linux/macOS/WSL
#   - Requires: curl, jq, bc, bsdmainutils
#
# LICENSE:
#   MIT License - See LICENSE file for details
#
# USAGE:
#   ./bench.sh [OPTIONS]
#   See --help for detailed usage information
#
################################################################################

# Exit immediately if a command exits with a non-zero status
set -e

################################################################################
# CONFIGURATION CONSTANTS
################################################################################
# These constants define the default behavior of the benchmark script.
# They can be overridden via command-line arguments.

# Default API endpoints for the LLM serving backends
# These should match your local deployment configuration
LLAMACPP_ENDPOINT="http://127.0.0.1:8001"  # llama.cpp server endpoint
VLLM_ENDPOINT="http://127.0.0.1:8000"      # vLLM server endpoint

# Model identifier - must match the model name in your serving backend
MODEL_NAME="your-model-name"

# Test execution parameters
REQUESTS_PER_TEST=5        # Number of requests per test scenario
TEMPERATURE=0.7            # Sampling temperature (0.0 = deterministic, 2.0 = very random)
TOKEN_LIST=(256)           # Array of max token counts to test
MAX_RETRIES=3              # Maximum retry attempts for failed requests
TIMEOUT=60                 # Request timeout in seconds

# Test prompts - designed to test different complexity levels
# Simple prompt: Quick response, minimal processing
SIMPLE_PROMPT="What is the capital of France?"

# Complex prompt: Requires more reasoning and longer response
COMPLEX_PROMPT="Explain how machine learning works in simple terms with examples."

################################################################################
# GLOBAL VARIABLES
################################################################################
# Runtime variables that control script execution and state

# Execution mode settings
ENGINE="both"                    # Target engine(s): "llama", "vllm", or "both"
VERBOSE=false                    # Enable verbose logging output
DRY_RUN=false                   # Show configuration without executing tests

# Output and logging configuration
TIMESTAMP=$(date +%Y%m%d_%H%M%S)                    # Unique timestamp for this run
OUTPUT_DIR="./logs/benchmarkresults$TIMESTAMP"     # Output directory path
LOG_FILE="$OUTPUT_DIR/benchmark.log"               # Main log file path
LOGGING_INITIALIZED=false                          # Track logging initialization state

################################################################################
# ANSI COLOR CODES
################################################################################
# Terminal color codes for enhanced output readability
# These provide consistent visual feedback across different operations

readonly RED='\033[0;31m'        # Error messages and failures
readonly GREEN='\033[0;32m'      # Success messages and headers
readonly YELLOW='\033[1;33m'     # Warnings and section headers
readonly BLUE='\033[0;34m'       # Information and file paths
readonly NC='\033[0m'            # No Color - reset to default

################################################################################
# INPUT VALIDATION FUNCTIONS
################################################################################
# These functions ensure all user inputs are valid before script execution
# begins. This prevents runtime errors and provides clear feedback.

#######################################
# Validates temperature parameter is within valid LLM range
# LLM temperature typically ranges from 0.0 (deterministic) to 2.0 (highly random)
# Arguments:
#   $1 - Temperature value to validate
# Returns:
#   0 if valid, 1 if invalid
# Outputs:
#   Error message to stderr if validation fails
#######################################
validate_temperature() {
    local temp="$1"
    
    # Check if input is a valid number (integer or decimal)
    if ! [[ "$temp" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        echo -e "${RED}Error: Temperature must be a number, got: $temp${NC}" >&2
        return 1
    fi
    
    # Check if temperature is within valid range [0.0, 2.0]
    if (( $(echo "$temp < 0.0" | bc -l) )) || (( $(echo "$temp > 2.0" | bc -l) )); then
        echo -e "${RED}Error: Temperature must be between 0.0 and 2.0, got: $temp${NC}" >&2
        return 1
    fi
    
    return 0
}

#######################################
# Validates that a value is a positive integer
# Used for request counts, token counts, retry limits, etc.
# Arguments:
#   $1 - Value to validate
#   $2 - Human-readable name for error messages
# Returns:
#   0 if valid, 1 if invalid
# Outputs:
#   Error message to stderr if validation fails
#######################################
validate_positive_integer() {
    local value="$1"
    local name="$2"
    
    # Check if value matches positive integer pattern (no leading zeros except for single zero)
    if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${RED}Error: $name must be a positive integer, got: $value${NC}" >&2
        return 1
    fi
    
    return 0
}

#######################################
# Validates comma-separated list of token counts
# Ensures each token count is a positive integer and provides warnings
# for unusually high values that might cause performance issues
# Arguments:
#   $1 - Comma-separated string of token counts
# Returns:
#   0 if all valid, 1 if any invalid
# Outputs:
#   Error messages and warnings as appropriate
#######################################
validate_token_list() {
    local tokens="$1"
    local -a token_array
    
    # Split comma-separated string into array
    IFS=',' read -ra token_array <<< "$tokens"
    
    # Validate each token count individually
    for token in "${token_array[@]}"; do
        if ! validate_positive_integer "$token" "Token count" 2>/dev/null; then
            echo -e "${RED}Error: Invalid token count in list: $token${NC}" >&2
            return 1
        fi
        
        # Warn about potentially problematic high token counts
        if (( token > 4096 )); then
            echo -e "${YELLOW}Warning: Token count $token is quite high and may cause issues${NC}" >&2
        fi
    done
    
    return 0
}

#######################################
# Validates URL format for API endpoints
# Ensures URLs follow basic HTTP/HTTPS format
# Arguments:
#   $1 - URL to validate
#   $2 - Human-readable name for error messages
# Returns:
#   0 if valid, 1 if invalid
# Outputs:
#   Error message to stderr if validation fails
#######################################
validate_url() {
    local url="$1"
    local name="$2"
    
    # Check basic URL format: protocol://domain
    if ! [[ "$url" =~ ^https?://[^[:space:]]+$ ]]; then
        echo -e "${RED}Error: Invalid URL format for $name: $url${NC}" >&2
        return 1
    fi
    
    return 0
}

#######################################
# Validates timeout value is within reasonable bounds
# Prevents timeouts that are too short (causing false failures)
# or too long (causing tests to hang indefinitely)
# Arguments:
#   $1 - Timeout value in seconds
# Returns:
#   0 if valid, 1 if invalid
# Outputs:
#   Error message to stderr if validation fails
#######################################
validate_timeout() {
    local timeout="$1"
    
    # First check if it's a positive integer
    if ! validate_positive_integer "$timeout" "Timeout" 2>/dev/null; then
        echo -e "${RED}Error: Timeout must be a positive integer${NC}" >&2
        return 1
    fi
    
    # Check reasonable bounds: 5 seconds minimum, 300 seconds (5 minutes) maximum
    if (( timeout < 5 )) || (( timeout > 300 )); then
        echo -e "${RED}Error: Timeout must be between 5 and 300 seconds, got: $timeout${NC}" >&2
        return 1
    fi
    
    return 0
}

################################################################################
# COMMAND-LINE ARGUMENT PARSER
################################################################################
# Comprehensive argument parsing with validation and help system
# Supports both short (-x) and long (--option) argument formats

#######################################
# Parses and validates all command-line arguments
# Performs comprehensive validation of all inputs before proceeding
# Updates global variables based on provided arguments
# Arguments:
#   $@ - All command-line arguments passed to script
# Returns:
#   0 on success, exits with code 1 on validation failure
# Side Effects:
#   - Updates global configuration variables
#   - May exit script on validation errors
#   - Displays help and exits on --help
#######################################
parse_args() {
    # Process arguments in pairs (option + value)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            # Engine selection: which LLM backend(s) to test
            -e|--engine)
                if [[ -z "$2" ]]; then
                    echo -e "${RED}Error: --engine requires a value${NC}" >&2
                    exit 1
                fi
                ENGINE="$2"
                shift 2
                ;;
                
            # Token count configuration: comma-separated list
            -n|--tokens)
                if [[ -z "$2" ]]; then
                    echo -e "${RED}Error: --tokens requires a value${NC}" >&2
                    exit 1
                fi
                validate_token_list "$2" || exit 1
                IFS=',' read -ra TOKEN_LIST <<< "$2"
                shift 2
                ;;
                
            # Temperature setting for LLM sampling
            -t|--temperature)
                if [[ -z "$2" ]]; then
                    echo -e "${RED}Error: --temperature requires a value${NC}" >&2
                    exit 1
                fi
                validate_temperature "$2" || exit 1
                TEMPERATURE="$2"
                shift 2
                ;;
                
            # Number of requests per test scenario
            -r|--requests)
                if [[ -z "$2" ]]; then
                    echo -e "${RED}Error: --requests requires a value${NC}" >&2
                    exit 1
                fi
                validate_positive_integer "$2" "Requests per test" || exit 1
                # Warn about high request counts that may take excessive time
                if (( $2 > 100 )); then
                    echo -e "${YELLOW}Warning: High request count ($2) may take a long time${NC}" >&2
                fi
                REQUESTS_PER_TEST="$2"
                shift 2
                ;;
                
            # Custom llama.cpp endpoint override
            --llamacpp-endpoint)
                if [[ -z "$2" ]]; then
                    echo -e "${RED}Error: --llamacpp-endpoint requires a value${NC}" >&2
                    exit 1
                fi
                validate_url "$2" "llama.cpp endpoint" || exit 1
                LLAMACPP_ENDPOINT="$2"
                shift 2
                ;;
                
            # Custom vLLM endpoint override
            --vllm-endpoint)
                if [[ -z "$2" ]]; then
                    echo -e "${RED}Error: --vllm-endpoint requires a value${NC}" >&2
                    exit 1
                fi
                validate_url "$2" "vLLM endpoint" || exit 1
                VLLM_ENDPOINT="$2"
                shift 2
                ;;
                
            # Model name configuration
            -m|--model)
                if [[ -z "$2" ]]; then
                    echo -e "${RED}Error: --model requires a value${NC}" >&2
                    exit 1
                fi
                MODEL_NAME="$2"
                shift 2
                ;;
                
            # Request timeout configuration
            --timeout)
                if [[ -z "$2" ]]; then
                    echo -e "${RED}Error: --timeout requires a value${NC}" >&2
                    exit 1
                fi
                validate_timeout "$2" || exit 1
                TIMEOUT="$2"
                shift 2
                ;;
                
            # Maximum retry attempts for failed requests
            --max-retries)
                if [[ -z "$2" ]]; then
                    echo -e "${RED}Error: --max-retries requires a value${NC}" >&2
                    exit 1
                fi
                validate_positive_integer "$2" "Max retries" || exit 1
                # Warn about excessive retry counts
                if (( $2 > 10 )); then
                    echo -e "${YELLOW}Warning: High retry count ($2) may cause long delays${NC}" >&2
                fi
                MAX_RETRIES="$2"
                shift 2
                ;;
                
            # Custom output directory
            -o|--output)
                if [[ -z "$2" ]]; then
                    echo -e "${RED}Error: --output requires a value${NC}" >&2
                    exit 1
                fi
                OUTPUT_DIR="$2"
                shift 2
                ;;
                
            # Enable verbose logging mode
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
                
            # Enable dry-run mode (configuration check without execution)
            --dry-run)
                DRY_RUN=true
                shift
                ;;
                
            # Override default simple prompt
            --simple-prompt)
                if [[ -z "$2" ]]; then
                    echo -e "${RED}Error: --simple-prompt requires a value${NC}" >&2
                    exit 1
                fi
                SIMPLE_PROMPT="$2"
                shift 2
                ;;
                
            # Override default complex prompt
            --complex-prompt)
                if [[ -z "$2" ]]; then
                    echo -e "${RED}Error: --complex-prompt requires a value${NC}" >&2
                    exit 1
                fi
                COMPLEX_PROMPT="$2"
                shift 2
                ;;
                
            # Display help and exit
            -h|--help)
                show_help
                exit 0
                ;;
                
            # Handle unknown arguments
            *)
                echo -e "${RED}Unknown argument: $1${NC}" >&2
                echo "Use --help for usage information" >&2
                exit 1
                ;;
        esac
    done

    # Post-parsing validation
    
    # Validate engine choice
    if [[ "$ENGINE" != "llama" && "$ENGINE" != "vllm" && "$ENGINE" != "both" ]]; then
        echo -e "${RED}Error: Invalid engine '$ENGINE'. Choose 'llama', 'vllm', or 'both'.${NC}" >&2
        exit 1
    fi

    # Validate prompts are not empty (important for meaningful tests)
    if [[ -z "$SIMPLE_PROMPT" ]] || [[ -z "$COMPLEX_PROMPT" ]]; then
        echo -e "${RED}Error: Prompts cannot be empty${NC}" >&2
        exit 1
    fi
}

show_help() {
    echo -e "${GREEN}LLM Inference Performance Benchmark Script${NC}"
    echo "Compares response latency and throughput between llama.cpp and vLLM"
    echo ""
    echo -e "${YELLOW}Usage:${NC} ./bench.sh [OPTIONS]"
    echo ""
    echo -e "${YELLOW}Basic Options:${NC}"
    echo "  -e, --engine llama|vllm|both      Target engine(s) (default: both)"
    echo "  -n, --tokens 128,256,512          Comma-separated token counts (default: 256)"
    echo "  -t, --temperature 0.7             Sampling temperature, 0.0-2.0 (default: 0.7)"
    echo "  -r, --requests 5                  Requests per test (default: 5)"
    echo "  -m, --model MODEL_NAME            Model name (default: your-model-name)"
    echo ""
    echo -e "${YELLOW}Endpoint Configuration:${NC}"
    echo "  --llamacpp-endpoint URL           llama.cpp endpoint (default: http://127.0.0.1:8001)"
    echo "  --vllm-endpoint URL               vLLM endpoint (default: http://127.0.0.1:8000)"
    echo ""
    echo -e "${YELLOW}Advanced Options:${NC}"
    echo "  --timeout SECONDS                 Request timeout, 5-300s (default: 60)"
    echo "  --max-retries COUNT               Max retries per request (default: 3)"
    echo "  -o, --output DIR                  Output directory (default: auto-generated)"
    echo "  -v, --verbose                     Enable verbose logging"
    echo "  --dry-run                         Show configuration without running tests"
    echo ""
    echo -e "${YELLOW}Custom Prompts:${NC}"
    echo "  --simple-prompt \"TEXT\"            Override simple prompt"
    echo "  --complex-prompt \"TEXT\"           Override complex prompt"
    echo ""
    echo -e "${YELLOW}Other:${NC}"
    echo "  -h, --help                        Show this help message"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  ./bench.sh                                    # Run with defaults"
    echo "  ./bench.sh -e vllm -t 0.0 -r 10              # Test vLLM with deterministic output"
    echo "  ./bench.sh -n 128,256,512 --verbose          # Test multiple token counts with verbose output"
    echo "  ./bench.sh --dry-run                         # Show configuration without running"
}

# ─────────────────────────────────────────────────────────────
# ENHANCED LOGGING UTILITIES
# ─────────────────────────────────────────────────────────────
initialize_logging() {
    if [[ "$LOGGING_INITIALIZED" == false ]]; then
        if [[ "$DRY_RUN" == false ]]; then
            mkdir -p "$OUTPUT_DIR"
            # Create a configuration summary
            cat > "$OUTPUT_DIR/config.txt" << EOF
Benchmark Configuration - $(date)
=====================================
Engine: $ENGINE
Model: $MODEL_NAME
Temperature: $TEMPERATURE
Requests per test: $REQUESTS_PER_TEST
Token counts: ${TOKEN_LIST[*]}
Timeout: ${TIMEOUT}s
Max retries: $MAX_RETRIES
llama.cpp endpoint: $LLAMACPP_ENDPOINT
vLLM endpoint: $VLLM_ENDPOINT
Simple prompt: $SIMPLE_PROMPT
Complex prompt: $COMPLEX_PROMPT
EOF
        fi
        LOGGING_INITIALIZED=true
    fi
}

log() {
    local message="$1"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] $timestamp - $message"
    else
        initialize_logging
        echo "$timestamp - $message" | tee -a "$LOG_FILE"
    fi
    
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $message" >&2
    fi
}

log_error() {
    local message="$1"
    echo -e "${RED}ERROR: $message${NC}" >&2
    log "ERROR: $message"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}WARNING: $message${NC}" >&2
    log "WARNING: $message"
}

# ─────────────────────────────────────────────────────────────
# ENHANCED ENDPOINT CHECKER WITH RETRY LOGIC
# ─────────────────────────────────────────────────────────────
test_endpoint() {
    local endpoint="$1"
    local name="$2"

    log "Testing $name endpoint: $endpoint"

    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would test $name endpoint"
        return 0
    fi

    local retry_count=0
    local success=false

    while [[ $retry_count -lt $MAX_RETRIES && "$success" == false ]]; do
        if [[ $retry_count -gt 0 ]]; then
            log "Retry $retry_count/$MAX_RETRIES for $name"
            sleep $((retry_count * 2))  # Exponential backoff
        fi

        local code=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time "$TIMEOUT" \
            --connect-timeout 10 \
            -X POST "$endpoint/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d '{
                "model": "'"$MODEL_NAME"'",
                "messages": [{"role": "user", "content": "test"}],
                "max_tokens": 5,
                "temperature": 0.0
            }' 2>/dev/null || echo "000")

        if [[ "$code" == "200" ]]; then
            log "$name is responsive (HTTP $code)"
            success=true
        else
            log_warning "$name returned HTTP $code (attempt $((retry_count + 1)))"
            retry_count=$((retry_count + 1))
        fi
    done

    if [[ "$success" == false ]]; then
        log_error "$name failed after $MAX_RETRIES attempts"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────
# ENHANCED REQUEST FUNCTION WITH RETRY AND ERROR HANDLING
# ─────────────────────────────────────────────────────────────
single_request() {
    local endpoint="$1"
    local prompt="$2"
    local max_tokens="$3"

    if [[ "$DRY_RUN" == true ]]; then
        echo "1.234,42,34.12,true"
        return 0
    fi

    local retry_count=0
    local success=false
    local final_result=""

    while [[ $retry_count -lt $MAX_RETRIES && "$success" == false ]]; do
        local start_time=$(date +%s.%N)
        local temp_file="/tmp/benchresp$$_${retry_count}.json"

        # Escape the prompt properly for JSON
        local escaped_prompt=$(echo "$prompt" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')

        local code=$(curl -s -o "$temp_file" -w "%{http_code}" \
            --max-time "$TIMEOUT" \
            --connect-timeout 10 \
            -X POST "$endpoint/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d '{
                "model": "'"$MODEL_NAME"'",
                "messages": [
                    {"role": "system", "content": "You are helpful."},
                    {"role": "user", "content": "'"$escaped_prompt"'"}
                ],
                "max_tokens": '"$max_tokens"',
                "temperature": '"$TEMPERATURE"'
            }' 2>/dev/null || echo "000")

        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
        local tokens_generated=0

        if [[ "$code" == "200" && -f "$temp_file" ]]; then
            if jq empty "$temp_file" 2>/dev/null; then
                # Try to get tokens from usage field first, then fallback to word count
                tokens_generated=$(jq -r '.usage.completion_tokens // 0' "$temp_file" 2>/dev/null || echo "0")
                if [[ "$tokens_generated" == "0" || "$tokens_generated" == "null" ]]; then
                    tokens_generated=$(jq -r '.choices[0].message.content' "$temp_file" 2>/dev/null | wc -w || echo "0")
                fi
                
                # Validate we got a reasonable response
                local response_content=$(jq -r '.choices[0].message.content // ""' "$temp_file" 2>/dev/null || echo "")
                if [[ -n "$response_content" && ${#response_content} -gt 5 ]]; then
                    success=true
                    local tps=0
                    if [[ "$tokens_generated" -gt 0 && "$duration" != "0" ]]; then
                        tps=$(echo "scale=2; $tokens_generated / $duration" | bc -l 2>/dev/null || echo "0")
                    fi
                    final_result="$duration,$tokens_generated,$tps,true"
                fi
            fi
        fi

        rm -f "$temp_file"

        if [[ "$success" == false ]]; then
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $MAX_RETRIES ]]; then
                [[ "$VERBOSE" == true ]] && log_warning "Request failed (HTTP $code), retrying in $((retry_count * 2))s..."
                sleep $((retry_count * 2))
            fi
        fi
    done

    if [[ "$success" == false ]]; then
        final_result="0,0,0,false"
    fi

    echo "$final_result"
}

# ─────────────────────────────────────────────────────────────
# ENHANCED TEST BATCH WITH BETTER STATISTICS
# ─────────────────────────────────────────────────────────────
run_test_batch() {
    local endpoint="$1"
    local engine_name="$2"
    local prompt="$3"
    local prompt_type="$4"
    local max_tokens="$5"

    log "Running test on $engine_name [${prompt_type}, ${max_tokens} tokens]"

    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would run $REQUESTS_PER_TEST requests for $engine_name"
        initialize_logging
        echo "$engine_name,$prompt_type,$max_tokens,$REQUESTS_PER_TEST,$REQUESTS_PER_TEST,1.234,0.987,1.567,42,34.12,0.05" >> "$OUTPUT_DIR/results.csv"
        return 0
    fi

    local total_time=0 total_tokens=0 success_count=0 failed_count=0
    local min_time=9999 max_time=0
    local token_rates=()
    local response_times=()

    for i in $(seq 1 $REQUESTS_PER_TEST); do
        echo -n "  Request $i/$REQUESTS_PER_TEST... "
        result=$(single_request "$endpoint" "$prompt" "$max_tokens")
        IFS=',' read -r duration response_tokens tps success <<< "$result"

        if [[ "$success" == "true" ]]; then
            success_count=$((success_count + 1))
            total_time=$(echo "$total_time + $duration" | bc -l)
            total_tokens=$((total_tokens + response_tokens))
            token_rates+=("$tps")
            response_times+=("$duration")
            (( $(echo "$duration < $min_time" | bc -l) )) && min_time=$duration
            (( $(echo "$duration > $max_time" | bc -l) )) && max_time=$duration
            echo "✓ ${duration}s, ${response_tokens} tokens, ${tps} t/s"
        else
            failed_count=$((failed_count + 1))
            echo -e "${RED}✗ Failed${NC}"
        fi
    done

    if [[ $success_count -eq 0 ]]; then
        log_error "All requests failed for $engine_name [$prompt_type, $max_tokens tokens]"
        return 1
    fi

    # Calculate statistics
    local avg_time=$(echo "scale=5; $total_time / $success_count" | bc -l)
    local avg_tokens=$((total_tokens / success_count))
    local sum_tps=0
    for rate in "${token_rates[@]}"; do 
        sum_tps=$(echo "$sum_tps + $rate" | bc -l)
    done
    local avg_tps=$(echo "scale=5; $sum_tps / $success_count" | bc -l)
    
    # Calculate standard deviation for response times
    local sum_sq_diff=0
    for time in "${response_times[@]}"; do
        local diff=$(echo "$time - $avg_time" | bc -l)
        local sq_diff=$(echo "$diff * $diff" | bc -l)
        sum_sq_diff=$(echo "$sum_sq_diff + $sq_diff" | bc -l)
    done
    local std_dev=$(echo "scale=5; sqrt($sum_sq_diff / $success_count)" | bc -l)

    # Format results
    min_time=$(printf "%.5f" $min_time)
    max_time=$(printf "%.5f" $max_time)
    avg_time=$(printf "%.5f" $avg_time)
    avg_tps=$(printf "%.5f" $avg_tps)
    std_dev=$(printf "%.5f" $std_dev)

    log "Results: Success: $success_count/$REQUESTS_PER_TEST, Avg: ${avg_time}s (±${std_dev}s), Tokens/s: $avg_tps"

    initialize_logging
    echo "$engine_name,$prompt_type,$max_tokens,$success_count,$REQUESTS_PER_TEST,$avg_time,$min_time,$max_time,$avg_tokens,$avg_tps,$std_dev" >> "$OUTPUT_DIR/results.csv"
}

# ─────────────────────────────────────────────────────────────
# PRE-FLIGHT CHECKS
# ─────────────────────────────────────────────────────────────
check_dependencies() {
    local missing_deps=()
    for cmd in curl jq bc; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        echo -e "${YELLOW}Please install missing dependencies:${NC}"
        echo "  Ubuntu/Debian: sudo apt-get install curl jq bcbsdmainutils -y"
        exit 1
    fi
    
    log "Dependencies OK: curl, jq, bc"
}

show_configuration() {
    echo -e "\n${YELLOW}=== Configuration ===${NC}"
    echo "Engine(s): $ENGINE"
    echo "Model: $MODEL_NAME"
    echo "Temperature: $TEMPERATURE"
    echo "Requests per test: $REQUESTS_PER_TEST"
    echo "Token counts: ${TOKEN_LIST[*]}"
    echo "Timeout: ${TIMEOUT}s"
    echo "Max retries: $MAX_RETRIES"
    echo "Output directory: $OUTPUT_DIR"
    [[ "$ENGINE" == "llama" || "$ENGINE" == "both" ]] && echo "llama.cpp endpoint: $LLAMACPP_ENDPOINT"
    [[ "$ENGINE" == "vllm" || "$ENGINE" == "both" ]] && echo "vLLM endpoint: $VLLM_ENDPOINT"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# MAIN FUNCTION WITH ENHANCED ERROR HANDLING
# ─────────────────────────────────────────────────────────────
main() {
    # Set up error handling
    trap 'log_error "Script interrupted"; exit 130' INT
    trap 'log_error "Script terminated"; exit 143' TERM

    parse_args "$@"
    
    echo -e "${GREEN}=== LLM Inference Benchmark ===${NC}"
    
    show_configuration
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}DRY RUN MODE - No actual requests will be made${NC}"
    fi
    
    check_dependencies

    # Test endpoints
    local endpoint_failures=0
    if [[ "$ENGINE" == "llama" || "$ENGINE" == "both" ]]; then
        if ! test_endpoint "$LLAMACPP_ENDPOINT" "llama.cpp"; then
            endpoint_failures=$((endpoint_failures + 1))
        fi
    fi
    if [[ "$ENGINE" == "vllm" || "$ENGINE" == "both" ]]; then
        if ! test_endpoint "$VLLM_ENDPOINT" "vLLM"; then
            endpoint_failures=$((endpoint_failures + 1))
        fi
    fi

    if [[ $endpoint_failures -gt 0 && "$DRY_RUN" == false ]]; then
        log_error "One or more endpoints failed connectivity tests"
        exit 1
    fi

    # Initialize results file
    initialize_logging
    if [[ "$DRY_RUN" == false ]]; then
        echo "Engine,Prompt_Type,Max_Tokens,Successful_Requests,Total_Requests,Avg_Response_Time,Min_Response_Time,Max_Response_Time,Avg_Tokens,Avg_Tokens_Per_Second,Std_Dev_Response_Time" > "$OUTPUT_DIR/results.csv"
    fi

    # Run benchmarks
    local total_tests=0
    local failed_tests=0
    
    for tokens in "${TOKEN_LIST[@]}"; do
        if [[ "$ENGINE" == "llama" || "$ENGINE" == "both" ]]; then
            total_tests=$((total_tests + 2))
            if ! run_test_batch "$LLAMACPP_ENDPOINT" "llama.cpp" "$SIMPLE_PROMPT" "simple" "$tokens"; then
                failed_tests=$((failed_tests + 1))
            fi
            if ! run_test_batch "$LLAMACPP_ENDPOINT" "llama.cpp" "$COMPLEX_PROMPT" "complex" "$tokens"; then
                failed_tests=$((failed_tests + 1))
            fi
        fi
        if [[ "$ENGINE" == "vllm" || "$ENGINE" == "both" ]]; then
            total_tests=$((total_tests + 2))
            if ! run_test_batch "$VLLM_ENDPOINT" "vLLM" "$SIMPLE_PROMPT" "simple" "$tokens"; then
                failed_tests=$((failed_tests + 1))
            fi
            if ! run_test_batch "$VLLM_ENDPOINT" "vLLM" "$COMPLEX_PROMPT" "complex" "$tokens"; then
                failed_tests=$((failed_tests + 1))
            fi
        fi
    done

    # Final summary
    echo -e "\n${GREEN}=== Benchmark Complete ===${NC}"
    if [[ "$DRY_RUN" == false ]]; then
        echo -e "Results saved to: ${BLUE}$OUTPUT_DIR/results.csv${NC}"
        echo -e "Configuration: ${BLUE}$OUTPUT_DIR/config.txt${NC}"
        echo -e "Log file: ${BLUE}$LOG_FILE${NC}"
    fi
    
    local success_tests=$((total_tests - failed_tests))
    echo -e "Tests completed: ${GREEN}$success_tests${NC}/$total_tests"
    
    if [[ $failed_tests -gt 0 ]]; then
        echo -e "${YELLOW}Failed tests: $failed_tests${NC}"
    fi

    if [[ "$DRY_RUN" == false && -f "$OUTPUT_DIR/results.csv" ]]; then
        echo -e "\n${YELLOW}=== Results Summary ===${NC}"
        column -t -s, "$OUTPUT_DIR/results.csv" | head -20
        if [[ $(wc -l < "$OUTPUT_DIR/results.csv") -gt 21 ]]; then
            echo "... (truncated, see full results in CSV file)"
        fi
    fi
}

main "$@"