# 🧪 llm-benchmark

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/minkim26/llm-benchmark)](https://github.com/minkim26/llm-benchmark/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macOS%20%7C%20WSL-lightgrey)](https://github.com/minkim26/llm-benchmark)

A comprehensive, configurable Bash script to benchmark and compare inference performance between [llama.cpp](https://github.com/ggerganov/llama.cpp) and [vLLM](https://github.com/vllm-project/vllm) using the OpenAI-compatible `/v1/chat/completions` API.

## ✨ Key Metrics Supported

- ✅ **Response Latency**: Average, minimum, and maximum response times
- 🚀 **Throughput**: Tokens per second (TPS) with statistical analysis
- 📈 **Reliability**: Success rates and failure analysis
- 🔁 **Comparative Analysis**: Side-by-side engine performance
- 📊 **Statistical Insights**: Standard deviation and confidence intervals
- 📂 **Comprehensive Export**: CSV data + detailed logs

---

## 🎯 Why Use This Tool?

- **Production-Ready**: Robust error handling with automatic retries
- **Flexible Testing**: Multiple token counts, custom prompts, and temperature settings
- **Statistical Analysis**: Real performance insights, not just averages
- **Easy Integration**: CSV output perfect for further analysis or CI/CD pipelines
- **Battle-Tested**: Used in production environments for LLM performance optimization

---

## 📦 Features

### Core Functionality
- 🔄 **Multi-Engine Support**: Test llama.cpp, vLLM, or both simultaneously
- 📝 **Dual Prompt Testing**: Compare performance on simple vs complex prompts
- 🎛️ **Highly Configurable**: Command-line arguments for all parameters
- 📊 **Rich Statistics**: Beyond averages - get min/max/stddev for real insights
- 🛡️ **Robust Error Handling**: Automatic retries, timeout management, validation
- 📁 **Organized Output**: Timestamped directories with CSV and detailed logs

### Advanced Features
- 🔍 **Endpoint Validation**: Pre-flight checks ensure servers are responsive
- 📈 **Performance Tracking**: Track improvements across different configurations
- 🎚️ **Temperature Control**: Test deterministic vs creative outputs
- ⏱️ **Timeout Management**: Configurable timeouts with exponential backoff
- 📋 **Dry Run Mode**: Validate configuration without making requests
- 🔊 **Verbose Logging**: Detailed execution logs for debugging

---

## 🧱 Requirements

### System Requirements
- **Operating System**: Linux, macOS, or Windows with WSL
- **Bash**: Version 4.0 or higher
- **Hardware**: Sufficient to run your LLM servers

### 🧰 Dependencies

| Tool | Purpose | Installation |
|------|---------|-------------|
| `bash` | Script execution | Usually pre-installed |
| `curl` | HTTP requests | `apt install curl` |
| `jq` | JSON parsing | `apt install jq` |
| `bc` | Mathematical calculations | `apt install bc` |
| `bsdmainutils` | Formatting text / output | `apt install bsdmainutils` |

#### Installation Commands

**Debian/Ubuntu:**
```bash
sudo apt update && sudo apt install curl jq bsdmainutils -y
```

**CentOS/RHEL/Fedora:**
```bash
sudo yum install curl jq bc bsdmainutils -y
# or for newer versions:
sudo dnf install curl jq bc bsdmainutils -y
```

**macOS:**
```bash
brew install curl jq bc bsdmainutils
```

---

## 🚀 Quick Start

### 1. Clone the Repository
```bash
git clone https://github.com/minkim26/llm-benchmark.git
cd llm-benchmark
chmod +x bench.sh
```

### 2. Configure Your Endpoints
Edit the script or use command-line arguments:

**Option A: Edit Script (Persistent)**
```bash
# At the top of bench.sh, modify:
LLAMACPP_ENDPOINT="http://localhost:8001"  # Your llama.cpp server
VLLM_ENDPOINT="http://localhost:8000"      # Your vLLM server
MODEL_NAME="your-model-name"               # Must match both servers
```

**Option B: Command Line (Flexible)**
```bash
./bench.sh --llamacpp-endpoint http://server1:8001 --vllm-endpoint http://server2:8000
```

### 3. Run Your First Benchmark
```bash
# Quick test with defaults
./bench.sh

# Or check configuration first
./bench.sh --dry-run
```

---

## 📖 Usage Examples

### Basic Usage
```bash
# Benchmark both engines with defaults
./bench.sh

# Test only vLLM with verbose output
./bench.sh --engine vllm --verbose

# Test only llama.cpp
./bench.sh --engine llama
```

### Advanced Configuration
```bash
# Comprehensive benchmark with multiple token counts
./bench.sh --tokens 128,256,512,1024 --requests 10 --temperature 0.0 --verbose

# Stress test with high request count
./bench.sh --requests 50 --timeout 120 --max-retries 5

# Custom prompts for your specific use case
./bench.sh --simple-prompt "Translate 'Hello' to French" \
           --complex-prompt "Write a Python function to sort a list"
```

### Production Testing
```bash
# Deterministic testing for consistent results
./bench.sh --temperature 0.0 --requests 20 --engine both

# Performance regression testing
./bench.sh --tokens 256,512 --requests 15 --output ./results/v1.2-test
```

### All Available Options
```bash
./bench.sh --help  # See complete option list
```

---

## 📊 Understanding Your Results

### Output Structure
```
./logs/benchmarkresults20241220_143022/
├── results.csv          # Main benchmark data
├── config.txt          # Test configuration summary
└── benchmark.log       # Detailed execution log
```

### CSV Format
```csv
Engine,Prompt_Type,Max_Tokens,Successful_Requests,Total_Requests,Avg_Response_Time,Min_Response_Time,Max_Response_Time,Avg_Tokens,Avg_Tokens_Per_Second,Std_Dev_Response_Time
llama.cpp,simple,256,5,5,1.234,0.987,1.567,42,34.12,0.051
vLLM,simple,256,5,5,0.856,0.743,1.023,45,52.57,0.089
```

### Key Metrics Explained

| Metric | Description | What Good Looks Like |
|--------|-------------|---------------------|
| `Avg_Response_Time` | Average time per request (seconds) | Lower is better |
| `Avg_Tokens_Per_Second` | Throughput metric | Higher is better |
| `Std_Dev_Response_Time` | Response consistency | Lower = more consistent |
| `Successful_Requests` | Reliability indicator | Should equal Total_Requests |

### Sample Output
```
=== LLM Inference Benchmark ===

=== Configuration ===
Engine(s): both
Model: deepseek-r1
Temperature: 0.7
Requests per test: 5

Running test on llama.cpp [simple, 256 tokens]
  Request 1/5... ✓ 1.234s, 42 tokens, 34.12 t/s
  Request 2/5... ✓ 1.156s, 38 tokens, 32.87 t/s

=== Benchmark Complete ===
Results saved to: ./logs/benchmarkresults20241220_143022/
Tests completed: 4/4

=== Results Summary ===
Engine      Prompt_Type  Avg_Response_Time  Avg_Tokens_Per_Second
llama.cpp   simple       1.195              33.45
vLLM        simple       0.834              54.12
```

---

## ⚙️ Setting Up LLM Servers

### llama.cpp Server Setup

```bash
# Clone and build llama.cpp
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
make -j$(nproc)

# Download a model (example)
wget https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf

# Start the server
./server \
  -m llama-2-7b-chat.Q4_K_M.gguf \
  --port 8001 \
  --host 0.0.0.0 \
  --ctx-size 4096 \
  --threads $(nproc)
```

### vLLM Server Setup

```bash
# Install vLLM
pip install vllm

# Start the server
python -m vllm.entrypoints.openai.api_server \
  --model meta-llama/Llama-2-7b-chat-hf \
  --port 8000 \
  --host 0.0.0.0 \
  --max-model-len 4096
```

**Important**: Both servers must:
- Use the same model (or equivalent models)
- Expose the `/v1/chat/completions` endpoint
- Be accessible from where you run the benchmark

---

## 🎛️ Configuration Options

### Command Line Arguments

| Option | Default | Description |
|--------|---------|-------------|
| `--engine` | `both` | Target: `llama`, `vllm`, or `both` |
| `--tokens` | `256` | Comma-separated token counts |
| `--temperature` | `0.7` | Sampling temperature (0.0-2.0) |
| `--requests` | `5` | Requests per test scenario |
| `--model` | `your-model-name` | Model name (must match servers) |
| `--timeout` | `60` | Request timeout (5-300 seconds) |
| `--max-retries` | `3` | Maximum retry attempts |
| `--verbose` | `false` | Enable detailed logging |
| `--dry-run` | `false` | Show config without running |

### Default Test Prompts

**Simple Prompt:**
```
What is the capital of France?
```

**Complex Prompt:**
```
Explain how machine learning works in simple terms with examples.
```

**Custom Prompts:**
```bash
./bench.sh --simple-prompt "Your simple test" \
           --complex-prompt "Your complex test"
```

---

## 🔧 Troubleshooting

### Common Issues and Solutions

#### 🚫 Connection Refused
```
ERROR: vLLM failed after 3 attempts
```
**Solutions:**
- Verify server is running: `curl http://localhost:8000/v1/models`
- Check firewall settings
- Confirm endpoint URLs are correct

#### 📦 Missing Dependencies
```
ERROR: Missing required dependencies: jq
```
**Solution:**
```bash
sudo apt install jq  # or appropriate package manager
```

#### 🏷️ Model Mismatch
```
ERROR: Model 'deepseek-r1' not found
```
**Solutions:**
- Check model name: `curl http://localhost:8000/v1/models`
- Update `--model` parameter to match server
- Ensure both servers use the same model

#### ⏱️ Timeout Issues
```
WARNING: Request failed, retrying...
```
**Solutions:**
- Increase timeout: `--timeout 120`
- Check server performance and resources
- Reduce `--tokens` count for faster responses

### Debug Mode
```bash
# Enable verbose logging
./bench.sh --verbose

# Test configuration without requests
./bench.sh --dry-run

# Test single engine first
./bench.sh --engine vllm --requests 1
```

---

## 🔄 Version History

### v2.0.0 (2025-06-20)
- ✨ **Enhanced Statistical Analysis**: Added standard deviation, min/max tracking
- 🛡️ **Improved Error Handling**: Exponential backoff, better retry logic
- 📊 **Rich Output Format**: CSV with comprehensive metrics
- 🎛️ **Advanced Configuration**: More command-line options
- 📁 **Better Organization**: Timestamped output directories
- 🔍 **Pre-flight Checks**: Endpoint validation before testing

### v1.0.0 (2025-06-12)
- 🎉 **Initial Release**: Basic benchmarking functionality
- 🔄 **Multi-Engine Support**: llama.cpp and vLLM comparison
- 📝 **Dual Prompts**: Simple and complex prompt testing
- 📊 **CSV Export**: Basic metrics export

---

## 🤝 Contributing

We welcome contributions! Here's how to get started:

### 🐛 Reporting Issues
1. Check [existing issues](https://github.com/minkim26/llm-benchmark/issues)
2. Create a new issue with:
   - Detailed description
   - Steps to reproduce
   - System information
   - Sample output/logs

### 🔧 Contributing Code
1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes
4. Test thoroughly
5. Commit: `git commit -m 'Add amazing feature'`
6. Push: `git push origin feature/amazing-feature`
7. Open a Pull Request

### 📋 Development Guidelines
- Follow existing code style
- Add comments for complex logic
- Update documentation for new features
- Include tests for new functionality

---

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

**TL;DR**: Free to use, modify, and distribute. Just keep the copyright notice.

---

## 🙋‍♂️ Support & Community

- **🐛 Bug Reports**: [GitHub Issues](https://github.com/minkim26/llm-benchmark/issues)
- **💡 Feature Requests**: [GitHub Discussions](https://github.com/minkim26/llm-benchmark/discussions)
- **📚 Documentation**: This README + inline code comments
- **👨‍💻 Maintainer**: [Minsu Kim](https://github.com/minkim26)

---

## 🏆 Acknowledgments

- **[llama.cpp](https://github.com/ggerganov/llama.cpp)**: High-performance LLM inference
- **[vLLM](https://github.com/vllm-project/vllm)**: Fast and efficient LLM serving

---

## 📊 Project Stats

![GitHub stars](https://img.shields.io/github/stars/minkim26/llm-benchmark?style=social)
![GitHub forks](https://img.shields.io/github/forks/minkim26/llm-benchmark?style=social)
![GitHub issues](https://img.shields.io/github/issues/minkim26/llm-benchmark)
![GitHub pull requests](https://img.shields.io/github/issues-pr/minkim26/llm-benchmark)

---

*Made with ❤️ for the LLM community*