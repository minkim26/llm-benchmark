#!/bin/bash

# Simplified LLM Performance Benchmark Script
# Compare llama.cpp vs vLLM inference performance

set -e

# Configuration - UPDATE THESE TO MATCH YOUR SETUP
LLAMACPP_ENDPOINT="http://127.0.0.1:8000"
VLLM_ENDPOINT="http://127.0.0.1:8001"
MODEL_NAME="your-model-name"
OUTPUT_DIR="./benchmarks/benchmarkresults$(date +%Y%m%d_%H%M%S)"

# Test parameters
REQUESTS_PER_TEST=5
MAX_TOKENS=256
TEMPERATURE=0.7

# Test prompts
SIMPLE_PROMPT="What is the capital of France?"
COMPLEX_PROMPT="Explain how machine learning works in simple terms with examples."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default engine selection
ENGINE="both"

# Argument parser
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --engine)
                ENGINE="$2"
                shift 2
                ;;
            --help|-h)
                echo -e "Usage: ./script2.sh [--engine llama|vllm|both]"
                echo ""
                echo "Options:"
                echo "  --engine    Specify which engine to benchmark: llama, vllm, or both (default: both)"
                echo "  --help, -h  Show this help message"
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown argument: $1${NC}"
                echo "Run with --help to see available options."
                exit 1
                ;;
        esac
    done

    if [[ "$ENGINE" != "both" && "$ENGINE" != "llama" && "$ENGINE" != "vllm" ]]; then
        echo -e "${RED}Error: Invalid engine specified. Use 'llama', 'vllm', or omit for both.${NC}"
        exit 1
    fi
}

# Create output directory
mkdir -p "$OUTPUT_DIR"
LOG_FILE="$OUTPUT_DIR/benchmark.log"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check if endpoint is accessible
test_endpoint() {
    local endpoint=$1
    local name=$2

    log "Testing $name endpoint: $endpoint"

    local response=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$endpoint/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "'$MODEL_NAME'",
            "messages": [{"role": "user", "content": "test"}],
            "max_tokens": 5
        }' 2>/dev/null || echo "000")

    if [[ $response == "200" ]]; then
        log "$name endpoint is working"
        return 0
    else
        log "ERROR: $name endpoint returned HTTP $response"
        return 1
    fi
}

# Single request test
single_request() {
    local endpoint=$1
    local prompt="$2"

    local start_time=$(date +%s.%N)
    local temp_file="/tmp/benchresponse$$.json"
    local response_code=$(curl -s -o "$temp_file" -w "%{http_code}" \
        -X POST "$endpoint/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "'$MODEL_NAME'",
            "messages": [
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": "'"${prompt//\"/\\\"}"'"}
            ],
            "max_tokens": '$MAX_TOKENS',
            "temperature": '$TEMPERATURE'
        }' 2>/dev/null)

    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")

    local tokens_generated=0
    local success="false"

    if [[ $response_code == "200" ]] && [[ -f "$temp_file" ]]; then
        if jq empty "$temp_file" 2>/dev/null; then
            local completion_tokens=$(jq -r '.usage.completion_tokens // 0' "$temp_file" 2>/dev/null || echo "0")
            local content=$(jq -r '.choices[0].message.content // ""' "$temp_file" 2>/dev/null || echo "")

            if [[ "$completion_tokens" != "0" && "$completion_tokens" != "null" ]]; then
                tokens_generated=$completion_tokens
            else
                tokens_generated=$(echo "$content" | wc -w)
            fi
            success="true"
        fi
    fi

    rm -f "$temp_file"

    local tokens_per_second="0"
    if [[ $tokens_generated -gt 0 ]] && [[ $(echo "$duration > 0" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
        tokens_per_second=$(echo "scale=2; $tokens_generated / $duration" | bc -l 2>/dev/null || echo "0")
    fi

    echo "$duration,$tokens_generated,$tokens_per_second,$success"
}

# Run multiple requests and calculate stats
run_test_batch() {
    local endpoint=$1
    local name=$2
    local prompt="$3"
    local prompt_type="$4"

    log "Running $name test with $prompt_type prompt ($REQUESTS_PER_TEST requests)"

    local total_time=0
    local total_tokens=0
    local successful_requests=0
    local min_time=999999
    local max_time=0
    local times=()
    local token_rates=()

    for i in $(seq 1 $REQUESTS_PER_TEST); do
        echo -n "  Request $i/$REQUESTS_PER_TEST... "
        local result=$(single_request "$endpoint" "$prompt")
        local duration=$(echo "$result" | cut -d, -f1)
        local tokens=$(echo "$result" | cut -d, -f2)
        local tps=$(echo "$result" | cut -d, -f3)
        local success=$(echo "$result" | cut -d, -f4)

        if [[ "$success" == "true" ]]; then
            successful_requests=$((successful_requests + 1))
            total_time=$(echo "$total_time + $duration" | bc -l)
            total_tokens=$((total_tokens + tokens))
            times+=("$duration")
            token_rates+=("$tps")

            if [[ $(echo "$duration < $min_time" | bc -l) -eq 1 ]]; then
                min_time=$duration
            fi
            if [[ $(echo "$duration > $max_time" | bc -l) -eq 1 ]]; then
                max_time=$duration
            fi

            echo "✓ ${duration}s, ${tokens} tokens, ${tps} t/s"
        else
            echo "✗ Failed"
        fi
    done

    local avg_time="0"
    local avg_tokens="0"
    local avg_tps="0"

    if [[ $successful_requests -gt 0 ]]; then
        avg_time=$(echo "scale=3; $total_time / $successful_requests" | bc -l)
        avg_tokens=$(echo "scale=0; $total_tokens / $successful_requests" | bc -l)

        local sum_tps=0
        for rate in "${token_rates[@]}"; do
            sum_tps=$(echo "$sum_tps + $rate" | bc -l)
        done
        avg_tps=$(echo "scale=2; $sum_tps / $successful_requests" | bc -l)
    fi

    echo ""
    echo "Results for $name ($prompt_type):"
    echo "  Successful requests: $successful_requests/$REQUESTS_PER_TEST"
    echo "  Average response time: ${avg_time}s"
    echo "  Min/Max response time: ${min_time}s / ${max_time}s"
    echo "  Average tokens generated: $avg_tokens"
    echo "  Average tokens/second: $avg_tps"
    echo ""

    echo "$name,$prompt_type,$successful_requests,$REQUESTS_PER_TEST,$avg_time,$min_time,$max_time,$avg_tokens,$avg_tps" >> "$OUTPUT_DIR/results.csv"
}

# Main execution
main() {
    parse_args "$@"

    echo -e "${GREEN}=== LLM Inference Engines Performance Benchmark ===${NC}"
    
    case "$ENGINE" in
    llama)
        echo -e "${BLUE}Benchmarking llama.cpp only${NC}"
        ;;
    vllm)
        echo -e "${BLUE}Benchmarking vLLM only${NC}"
        ;;
    both)
        echo -e "${BLUE}Benchmarking both llama.cpp and vLLM${NC}"
        ;;
    esac
    
    echo ""

    log "Starting benchmark in directory: $OUTPUT_DIR"

    for cmd in curl jq bc; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}Error: $cmd is required but not installed${NC}"
            exit 1
        fi
    done
    log "Dependencies check passed"

    if [[ "$ENGINE" == "llama" || "$ENGINE" == "both" ]]; then
        if ! test_endpoint "$LLAMACPP_ENDPOINT" "llama.cpp"; then
            echo -e "${RED}llama.cpp endpoint test failed${NC}"
            [[ "$ENGINE" == "llama" ]] && exit 1
        fi
    fi

    if [[ "$ENGINE" == "vllm" || "$ENGINE" == "both" ]]; then
        if ! test_endpoint "$VLLM_ENDPOINT" "vLLM"; then
            echo -e "${RED}vLLM endpoint test failed${NC}"
            [[ "$ENGINE" == "vllm" ]] && exit 1
        fi
    fi

    echo "Engine,Prompt_Type,Successful_Requests,Total_Requests,Avg_Response_Time,Min_Response_Time,Max_Response_Time,Avg_Tokens,Avg_Tokens_Per_Second" > "$OUTPUT_DIR/results.csv"

    echo -e "${YELLOW}=== Running Benchmarks ===${NC}"

    if [[ "$ENGINE" == "llama" || "$ENGINE" == "both" ]]; then
        run_test_batch "$LLAMACPP_ENDPOINT" "llama.cpp" "$SIMPLE_PROMPT" "simple"
        run_test_batch "$LLAMACPP_ENDPOINT" "llama.cpp" "$COMPLEX_PROMPT" "complex"
    fi

    if [[ "$ENGINE" == "vllm" || "$ENGINE" == "both" ]]; then
        run_test_batch "$VLLM_ENDPOINT" "vLLM" "$SIMPLE_PROMPT" "simple"
        run_test_batch "$VLLM_ENDPOINT" "vLLM" "$COMPLEX_PROMPT" "complex"
    fi

    echo -e "${GREEN}=== Benchmark Complete ===${NC}"
    echo -e "Results saved to: ${BLUE}$OUTPUT_DIR${NC}"
    echo -e "CSV results: ${BLUE}$OUTPUT_DIR/results.csv${NC}"
    echo -e "Log file: ${BLUE}$LOG_FILE${NC}"

    echo ""
    echo -e "${YELLOW}=== Quick Comparison ===${NC}"
    if [[ -f "$OUTPUT_DIR/results.csv" ]]; then
        echo "Results from CSV:"
        column -t -s, "$OUTPUT_DIR/results.csv"
    fi
}

main "$@"
