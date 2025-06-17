# 🧪 llm-benchmark

A simple, configurable Bash script to benchmark and compare inference performance between [llama.cpp](https://github.com/ggerganov/llama.cpp) and [vLLM](https://github.com/vllm-project/vllm) using the OpenAI-compatible `/v1/chat/completions` API.

Supports measuring:

- ✅ Response latency (avg / min / max)
- 🚀 Tokens per second (TPS)
- 📈 Success rate
- 🔁 Per-model performance comparison
- 📂 CSV + log export

---

## 📦 Features

- Benchmark **llama.cpp**, **vLLM**, or **both**.
- Compare simple vs complex prompts.
- Logs results to `results.csv` and `benchmark.log`.
- Validates endpoints and gracefully handles missing token counts.

---

## 🧱 Requirements

Ensure these are installed:

### 🧰 Dependencies

- `bash`
- `curl`
- `jq`
- `bc`
- `bsdmainutils`

Install them (Debian/Ubuntu example):

```bash
sudo apt update
sudo apt install curl jq bc bsdmainutils -y
```

---

## 🚀 How to Use

### 1. Clone the Repository

```bash
git clone https://github.com/minkim26/llm-benchmark.git
cd llm-benchmark
```

### 2. Configure the Script

At the top of `bench.sh`, set:

```bash
LLAMACPP_ENDPOINT="http://localhost:8000"
VLLM_ENDPOINT="http://localhost:8001"
MODEL_NAME="your-model-name"
```

Make sure both endpoints expose the `/v1/chat/completions` API.

---

### 3. Run Benchmarks

#### 🔁 Benchmark Both llama.cpp and vLLM

```bash
./bench.sh
```

#### 🐑 Benchmark Only llama.cpp

```bash
./bench.sh --engine llama
```

#### ⚡ Benchmark Only vLLM

```bash
./bench.sh --engine vllm
```

#### ⚙️ Customize Tokens and Temperature

```bash
./bench.sh --tokens 128,256 --temperature 0.9 --requests 10
```

#### 📖 Show Help / Usage Options

```bash
./bench.sh --help
```

---

## 📤 Output

Benchmarks are saved to:

```bash
./logs/benchmarkresultsYYYYMMDD_HHMMSS/
```

Includes:

- `results.csv`
- `benchmark.log`

CSV headers:

```
Engine,Prompt_Type,Successful_Requests,Total_Requests,Avg_Response_Time,Min_Response_Time,Max_Response_Time,Avg_Tokens,Avg_Tokens_Per_Second
```

---

## ⚙️ Running llama.cpp API Server

```bash
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp

# Build the server
make -j

# Run the server (example)
./server -m ./models/ggml-model-q4_0.bin --port 8000 --host 0.0.0.0 --threads 8
```

> Replace model path and format with your specific GGML/GGUF model.

---

## ⚙️ Running vLLM API Server

```bash
pip install vllm

python3 -m vllm.entrypoints.openai.api_server \
  --model TheBloke/Llama-2-7b-chat-hf \
  --port 8001 \
  --host 0.0.0.0
```

> You can use any HuggingFace-supported transformer model.

---

## 💬 Prompts Used

### Simple Prompt

```
What is the capital of France?
```

### Complex Prompt

```
Explain how machine learning works in simple terms with examples.
```

---

## 🛠️ Customization Options

You can easily customize:

- Prompt content or type
- Number of test runs per prompt
- Inference parameters (temperature, max tokens, etc.)
- Output locations

Modify the corresponding values in `bench.sh`.

---

## 🧾 License

MIT License — free to use, modify, and distribute.

---

## 🙋‍♂️ Questions or Issues?

Feel free to open an [Issue](https://github.com/minkim26/llm-benchmark/issues) or send a pull request!

Maintained by **Minsu Kim**.
