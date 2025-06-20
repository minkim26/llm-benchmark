#!/bin/bash

# LLM Inference Performance Benchmark Script
# Compares response latency and throughput between llama.cpp and vLLM

set -e

# ─────────────────────────────────────────────────────────────
# USER CONFIGURATION
# ─────────────────────────────────────────────────────────────
LLAMACPP_ENDPOINT="http://127.0.0.1:8000"
VLLM_ENDPOINT="http://127.0.0.1:8001"
MODEL_NAME="your-model-name"

REQUESTS_PER_TEST=5
TEMPERATURE=0.7
TOKEN_LIST=(256)

SIMPLE_PROMPT="What is the capital of France?"
COMPLEX_PROMPT="Explain how machine learning works in simple terms with examples."

# ─────────────────────────────────────────────────────────────
# INITIALIZATION
# ─────────────────────────────────────────────────────────────
ENGINE="both"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="./logs/benchmarkresults$TIMESTAMP"
LOG_FILE="$OUTPUT_DIR/benchmark.log"
LOGGING_INITIALIZED=false

# Color codes
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# ─────────────────────────────────────────────────────────────
# ARGUMENT PARSER
# ─────────────────────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -e|--engine)
                ENGINE="$2"; shift 2 ;;
            -n|--tokens)
                IFS=',' read -ra TOKEN_LIST <<< "$2"; shift 2 ;;
            -t|--temperature)
                TEMPERATURE="$2"; shift 2 ;;
            -r|--requests)
                REQUESTS_PER_TEST="$2"; shift 2 ;;
            -h|--help)
                echo -e "Usage: ./bench.sh [OPTIONS]\n"
                echo "Options:"
                echo "  -e, --engine llama|vllm|both      Target engine(s) (default: both)"
                echo "  -n, --tokens 128,256              Comma-separated token counts (default: 256)"
                echo "  -t, --temperature 0.7             Sampling temperature (default: 0.7)"
                echo "  -r, --requests 5                  Requests per prompt (default: 5)"
                echo "  -h, --help                        Show this help message"
                exit 0 ;;
            *)
                echo -e "${RED}Unknown argument: $1${NC}"; exit 1 ;;
        esac
    done

    if [[ "$ENGINE" != "llama" && "$ENGINE" != "vllm" && "$ENGINE" != "both" ]]; then
        echo -e "${RED}Invalid engine: $ENGINE. Choose 'llama', 'vllm', or 'both'.${NC}"
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────
# LOGGING UTILITIES
# ─────────────────────────────────────────────────────────────
initialize_logging() {
    if [[ "$LOGGING_INITIALIZED" == false ]]; then
        mkdir -p "$OUTPUT_DIR"
        LOGGING_INITIALIZED=true
    fi
}

log() {
    initialize_logging
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# ─────────────────────────────────────────────────────────────
# ENDPOINT CHECKER
# ─────────────────────────────────────────────────────────────
test_endpoint() {
    local endpoint="$1"
    local name="$2"

    log "Testing $name endpoint: $endpoint"

    local code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$endpoint/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model": "'"$MODEL_NAME"'", "messages": [{"role": "user", "content": "test"}], "max_tokens": 5}' || echo "000")

    if [[ "$code" == "200" ]]; then
        log "$name is responsive"
    else
        log "ERROR: $name failed with code: $code"
    fi
}

# ─────────────────────────────────────────────────────────────
# RUN A SINGLE REQUEST
# ─────────────────────────────────────────────────────────────
single_request() {
    local endpoint="$1"
    local prompt="$2"
    local max_tokens="$3"

    local start_time=$(date +%s.%N)
    local temp_file="/tmp/benchresp$$.json"

    local code=$(curl -s -o "$temp_file" -w "%{http_code}" \
        -X POST "$endpoint/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "'"$MODEL_NAME"'",
            "messages": [
                {"role": "system", "content": "You are helpful."},
                {"role": "user", "content": "'"${prompt//\"/\\\"}"'"}
            ],
            "max_tokens": '"$max_tokens"',
            "temperature": '"$TEMPERATURE"'
        }' || echo "000")

    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    local success="false"
    local tokens_generated=0

    if [[ "$code" == "200" && -f "$temp_file" ]]; then
        if jq empty "$temp_file" 2>/dev/null; then
            tokens_generated=$(jq -r '.usage.completion_tokens // 0' "$temp_file")
            tokens_generated=${tokens_generated:-$(jq -r '.choices[0].message.content' "$temp_file" | wc -w)}
            success="true"
        fi
    fi

    rm -f "$temp_file"
    local tps=0
    [[ "$tokens_generated" -gt 0 ]] && tps=$(echo "scale=2; $tokens_generated / $duration" | bc)

    echo "$duration,$tokens_generated,$tps,$success"
}

# ─────────────────────────────────────────────────────────────
# RUN A TEST BATCH FOR A GIVEN PROMPT AND TOKEN LENGTH
# ─────────────────────────────────────────────────────────────
run_test_batch() {
    local endpoint="$1"
    local engine_name="$2"
    local prompt="$3"
    local prompt_type="$4"
    local max_tokens="$5"

    log "Running test on $engine_name [${prompt_type}, ${max_tokens} tokens]"

    local total_time=0 total_tokens=0 success_count=0
    local min_time=9999 max_time=0
    local token_rates=()

    for i in $(seq 1 $REQUESTS_PER_TEST); do
        echo -n "  Request $i... "
        result=$(single_request "$endpoint" "$prompt" "$max_tokens")
        IFS=',' read -r duration tokens tps success <<< "$result"

        if [[ "$success" == "true" ]]; then
            success_count=$((success_count + 1))
            total_time=$(echo "$total_time + $duration" | bc)
            total_tokens=$((total_tokens + tokens))
            token_rates+=("$tps")
            (( $(echo "$duration < $min_time" | bc) )) && min_time=$duration
            (( $(echo "$duration > $max_time" | bc) )) && max_time=$duration
            echo "✓ ${duration}s, ${tokens} tokens, ${tps} t/s"
        else
            echo -e "${RED}✗ Failed: ${NC}$1"; 
            echo -e "${RED}Please check the following endpoint configuration: ${NC}$1"; 
            exit 0
        fi
    done

    avg_time=$(echo "scale=5; $total_time / $success_count" | bc -l)
    avg_tokens=$((total_tokens / success_count))
    sum_tps=0; for rate in "${token_rates[@]}"; do sum_tps=$(echo "$sum_tps + $rate" | bc); done
    avg_tps=$(echo "scale=5; $sum_tps / $success_count" | bc -l)

    initialize_logging
    echo "$engine_name,$prompt_type,$max_tokens,$success_count,$REQUESTS_PER_TEST,$avg_time,$min_time,$max_time,$avg_tokens,$avg_tps" >> "$OUTPUT_DIR/results.csv"
}

# ─────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    echo -e "${GREEN}=== Starting Benchmark ===${NC}"
    for cmd in curl jq bc; do
        command -v $cmd >/dev/null || { echo -e "${RED}Missing dependency: $cmd${NC}"; exit 1; }
    done
    log "Dependencies OK"

    [[ "$ENGINE" == "llama" || "$ENGINE" == "both" ]] && test_endpoint "$LLAMACPP_ENDPOINT" "llama.cpp"
    [[ "$ENGINE" == "vllm"  || "$ENGINE" == "both" ]] && test_endpoint "$VLLM_ENDPOINT" "vLLM"

    initialize_logging
    echo "Engine,Prompt_Type,Max_Tokens,Successful_Requests,Total_Requests,Avg_Response_Time,Min_Response_Time,Max_Response_Time,Avg_Tokens,Avg_Tokens_Per_Second" > "$OUTPUT_DIR/results.csv"

    for tokens in "${TOKEN_LIST[@]}"; do
        [[ "$ENGINE" == "llama" || "$ENGINE" == "both" ]] && {
            run_test_batch "$LLAMACPP_ENDPOINT" "llama.cpp" "$SIMPLE_PROMPT" "simple" "$tokens"
            run_test_batch "$LLAMACPP_ENDPOINT" "llama.cpp" "$COMPLEX_PROMPT" "complex" "$tokens"
        }
        [[ "$ENGINE" == "vllm" || "$ENGINE" == "both" ]] && {
            run_test_batch "$VLLM_ENDPOINT" "vLLM" "$SIMPLE_PROMPT" "simple" "$tokens"
            run_test_batch "$VLLM_ENDPOINT" "vLLM" "$COMPLEX_PROMPT" "complex" "$tokens"
        }
    done

    echo -e "\n${GREEN}Benchmark complete. CSV saved to: ${BLUE}$OUTPUT_DIR/results.csv${NC}"
    echo -e "${YELLOW}=== Summary ===${NC}"
    column -t -s, "$OUTPUT_DIR/results.csv"
}

main "$@"