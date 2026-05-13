# LLM Tracker

A lightweight, native macOS menubar application designed to monitor running Large Language Model (LLM) and MLX servers. Keep track of which models are currently loaded into memory, which ports they are listening on, and effortlessly free up resources by terminating instances directly from your menubar.

<p align="center">
  <img src="LLM_Tracker_logo.png" width="256" alt="LLM Tracker Logo">
</p>

## Features

- **Native macOS UI:** Built entirely with SwiftUI and `MenuBarExtra` for a minimal memory footprint and seamless system integration.
- **Dynamic Model Detection:** Parses active processes and polls internal APIs (like Ollama's `/api/ps` and oMLX's `/api/status`) to accurately report which models are currently consuming RAM/VRAM.
- **Instant Process Termination:** Features a one-click stop button to forcefully terminate (`kill -9`) active servers and instantly free up memory.
- **Adaptive Menubar Icon:** Uses a template rendering approach to adapt automatically to macOS Dark Mode and Light Mode.

## Supported Servers

The tracker actively listens for the following local servers:
- [Ollama](https://ollama.com)
- [vLLM](https://github.com/vllm-project/vllm)
- [MLX-LM](https://github.com/ml-explore/mlx-examples/tree/main/llms)
- [oMLX](https://github.com/jundot/omlx) 
- `vmlx`, `vllm-mlx`, `mlx-audio`, `mlx-vlm`, `mflux`

## Installation & Build

LLM Tracker is built natively using Swift. No Xcode project or complex build system is required—everything is managed via a simple `Makefile`.

### Prerequisites
- macOS 13.0 (Ventura) or later
- Xcode Command Line Tools (provides `swiftc` and `make`)

### Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/LLM-tracker.git
   cd LLM-tracker
   ```

2. Compile and bundle the application:
   ```bash
   make
   ```

3. Run the application:
   ```bash
   make run
   ```

### (Optional) Install Permanently
Once built, simply drag the generated `LLMTracker.app` bundle into your `/Applications` folder to keep it installed permanently on your Mac.

## How It Works Under the Hood

- **Process Scanning:** The app periodically polls macOS using `ps -eo pid,ppid,command -ww` to find running processes matching known LLM server keywords.
- **Port Mapping:** It precisely maps these processes to active network listening ports using `lsof`.
- **API Polling & Parsing:** 
  - For **Ollama**, it polls `http://127.0.0.1:<port>/api/ps` to view VRAM allocation.
  - For **oMLX**, it polls the internal `http://127.0.0.1:<port>/api/status` endpoint to extract dynamically loaded models.
  - For standard **MLX-LM** implementations, it parses the `--model` flag directly from the lengthy launch command string.

## License

MIT License
