import Foundation
import AppKit

@MainActor
class ServerMonitor: ObservableObject {
    @Published var instances: [ServerInstance] = []
    @Published var isRefreshing: Bool = false
    
    private var timer: Timer?
    
    let serverKeywords = [
        "ollama", "vllm", "mlx_lm", "mlx-lm", "omlx", 
        "mlx-openai-server", "mlx-omni-server", 
        "vmlx", "vllm-mlx", "mlx-audio", "mlx-vlm", "mflux",
        "swift-mlx", "mlx-swift", "mlx-swift-lm", "swiftlm"
    ]
    
    init() {
        startMonitoring()
    }
    
    func startMonitoring() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        Task {
            let newInstances = await fetchInstances()
            self.instances = newInstances
            self.isRefreshing = false
        }
    }
    
    func quitInstance(pid: Int32) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/kill")
        task.arguments = ["-9", "\(pid)"] // Force kill to immediately free up memory
        do {
            try task.run()
            task.waitUntilExit()
            
            // Give the OS a moment to clean up the process and ports, then refresh
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.refresh()
            }
        } catch {
            print("Failed to kill process \(pid)")
        }
    }
    
    private func fetchInstances() async -> [ServerInstance] {
        var foundInstances: [ServerInstance] = []
        
        // 1. Fetch all running processes using ps
        let processOutput = runCommand("ps", args: ["-eo", "pid,ppid,command", "-ww"])
        let psLines = processOutput.components(separatedBy: .newlines)
        
        struct ProcessInfo {
            let pid: Int32
            let ppid: Int32
            let command: String
        }
        var processMap: [Int32: ProcessInfo] = [:]
        
        for line in psLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.contains("PID") { continue }
            
            let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            if parts.count == 3 {
                let pidStr = String(parts[0])
                let ppidStr = String(parts[1])
                let cmd = String(parts[2])
                
                // Exclude grep or our own app just in case
                if cmd.contains("grep") || cmd.contains("LLMTracker") { continue }
                
                if let pid = Int32(pidStr), let ppid = Int32(ppidStr) {
                    processMap[pid] = ProcessInfo(pid: pid, ppid: ppid, command: cmd)
                }
            }
        }
        
        // 2. Fetch all listening TCP ports using lsof in a single command execution
        let lsofOutput = runCommand("lsof", args: ["-iTCP", "-sTCP:LISTEN", "-P", "-n"])
        let lsofLines = lsofOutput.components(separatedBy: .newlines)
        
        var pidToPortMap: [Int32: Int] = [:]
        for line in lsofLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.contains("COMMAND") { continue }
            
            if let parsed = parseLsofLine(trimmed) {
                // If a process listens on multiple ports, prefer standard LLM/MLX ports or keep the first one
                if pidToPortMap[parsed.pid] == nil {
                    pidToPortMap[parsed.pid] = parsed.port
                } else {
                    let existingPort = pidToPortMap[parsed.pid]!
                    let candidatePorts = [11434, 8000, 8080, 8081, 1234, 5001, 4242, 8082, 5413]
                    if candidatePorts.contains(parsed.port) && !candidatePorts.contains(existingPort) {
                        pidToPortMap[parsed.pid] = parsed.port
                    }
                }
            }
        }
        
        // 3. Define candidate filters for Swift apps and python sidecars
        let candidateKeywords = [
            "python", "node", "swift", "mlx", "omlx", "llama", "ollama", "vllm", 
            "mflux", "server", "llm", "model", "inference", "sidecar", "uvicorn", 
            "gunicorn", "fastapi", "app.py"
        ]
        let candidatePorts = [11434, 8000, 8080, 8081, 1234, 5001, 4242, 8082, 5413]
        
        // 4. Identify servers
        for (_, proc) in processMap {
            let cmd = proc.command
            let pid = proc.pid
            let ppid = proc.ppid
            
            // Check explicit keyword match
            let isExplicitServer = serverKeywords.contains(where: { cmd.localizedCaseInsensitiveContains($0) })
            
            // Check if it's listening on a TCP port and is a potential candidate
            let port = pidToPortMap[pid]
            var isCandidate = false
            if let port = port {
                let containsKeyword = candidateKeywords.contains(where: { cmd.localizedCaseInsensitiveContains($0) })
                let isLLMPort = candidatePorts.contains(port)
                isCandidate = containsKeyword || isLLMPort
            }
            
            if isExplicitServer || isCandidate {
                let owningApp = determineOwningApp(ppid: ppid)
                var name = determineServerName(from: cmd)
                var loadedModels: [String] = []
                var detected = false
                
                if let port = port {
                    // Try to probe the port to see what kind of server it is and what models are loaded.
                    // Keep timeouts very low (0.5s) to avoid UI blocking.
                    
                    // Probe OMLX status endpoint
                    if let omlxModels = await fetchOMLXModels(port: port) {
                        name = "OMLX"
                        loadedModels = omlxModels.isEmpty ? ["Dynamic / Auto-loaded"] : omlxModels
                        detected = true
                    }
                    
                    // Probe Ollama status endpoints
                    if !detected, let ollamaModels = await fetchOllamaModels(port: port) {
                        name = "Ollama"
                        loadedModels = ollamaModels.isEmpty ? ["Dynamic / Auto-loaded"] : ollamaModels
                        detected = true
                    }
                    
                    // Probe general OpenAI compatible (/v1/models) endpoint (vLLM, mlx-openai-server, llama.cpp, etc.)
                    if !detected, let openAIModels = await fetchOpenAIModels(port: port) {
                        if name == "Unknown Server" {
                            if cmd.localizedCaseInsensitiveContains("vllm") {
                                name = "vLLM"
                            } else if cmd.localizedCaseInsensitiveContains("swift-mlx") || cmd.localizedCaseInsensitiveContains("mlx-swift") || cmd.localizedCaseInsensitiveContains("swiftlm") {
                                name = "Swift-MLX"
                            } else if cmd.localizedCaseInsensitiveContains("mlx") {
                                if cmd.localizedCaseInsensitiveContains("swift") {
                                    name = "Swift-MLX"
                                } else {
                                    name = "MLX-LM"
                                }
                            } else if cmd.localizedCaseInsensitiveContains("omlx") {
                                name = "OMLX"
                            } else if cmd.localizedCaseInsensitiveContains("mflux") {
                                name = "MFlux"
                            } else {
                                name = "MLX/OpenAI Server"
                            }
                        }
                        loadedModels = openAIModels.isEmpty ? ["Dynamic / Auto-loaded"] : openAIModels
                        detected = true
                    }
                }
                
                // If it's a known explicit server but no active network probe succeeded, fallback to command line extraction
                if !detected && isExplicitServer {
                    if name == "Unknown Server" {
                        name = determineServerName(from: cmd)
                    }
                    if let extractedModel = extractModel(from: cmd) {
                        loadedModels = [extractedModel]
                    } else {
                        loadedModels = ["Dynamic / Auto-loaded"]
                    }
                    detected = true
                }
                
                if detected {
                    let instance = ServerInstance(
                        pid: pid,
                        name: name,
                        port: port,
                        loadedModels: loadedModels,
                        owningApp: owningApp
                    )
                    foundInstances.append(instance)
                }
            }
        }
        
        return foundInstances
    }
    
    private func parseLsofLine(_ line: String) -> (pid: Int32, port: Int)? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 9 else { return nil }
        
        let pidStr = String(parts[1])
        guard let pid = Int32(pidStr) else { return nil }
        
        for part in parts {
            if part.contains(":") {
                let components = part.split(separator: ":")
                if let portStrWithListen = components.last {
                    let portStr = portStrWithListen.replacingOccurrences(of: "(LISTEN)", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if let port = Int(portStr) {
                        return (pid, port)
                    }
                }
            }
        }
        return nil
    }
    
    private func determineServerName(from cmd: String) -> String {
        for keyword in serverKeywords {
            if cmd.localizedCaseInsensitiveContains(keyword) {
                if keyword == "ollama" { return "Ollama" }
                if keyword == "vllm" { return "vLLM" }
                if keyword == "mlx_lm" || keyword == "mlx-lm" { return "MLX-LM" }
                if keyword == "omlx" { return "OMLX" }
                if keyword == "swift-mlx" || keyword == "mlx-swift" || keyword == "mlx-swift-lm" || keyword == "swiftlm" { return "Swift-MLX" }
                return keyword
            }
        }
        return "Unknown Server"
    }
    
    private func determineOwningApp(ppid: Int32) -> String? {
        let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == ppid })
        if let name = app?.localizedName {
            return name
        }
        // Fallback: check ps again for the parent
        let output = runCommand("ps", args: ["-p", "\(ppid)", "-o", "comm="])
        let cmd = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cmd.isEmpty && cmd != "comm=" {
            return (cmd as NSString).lastPathComponent
        }
        return nil
    }
    
    private func extractModel(from cmd: String) -> String? {
        let parts = cmd.components(separatedBy: .whitespaces)
        for (index, part) in parts.enumerated() {
            if part == "--model" || part == "-m" {
                if index + 1 < parts.count {
                    return parts[index + 1]
                }
            }
        }
        return nil
    }
    
    private func fetchOllamaModels(port: Int) async -> [String]? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/ps") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard json?["models"] != nil else {
                // Try /api/tags as fallback
                if let fallbackUrl = URL(string: "http://127.0.0.1:\(port)/api/tags") {
                    var fallbackReq = URLRequest(url: fallbackUrl)
                    fallbackReq.timeoutInterval = 0.5
                    if let (fallbackData, fallbackResponse) = try? await URLSession.shared.data(for: fallbackReq),
                       let fallbackHttp = fallbackResponse as? HTTPURLResponse, fallbackHttp.statusCode == 200,
                       let fallbackJson = try? JSONSerialization.jsonObject(with: fallbackData) as? [String: Any],
                       fallbackJson["models"] != nil,
                       let decoded = try? JSONDecoder().decode(OllamaPSResponse.self, from: fallbackData) {
                        return decoded.models.map { $0.name }
                    }
                }
                return nil
            }
            let decoded = try JSONDecoder().decode(OllamaPSResponse.self, from: data)
            return decoded.models.map { $0.name }
        } catch {
            return nil
        }
    }
    
    private func fetchOMLXModels(port: Int) async -> [String]? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/status") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard json?["loaded_models"] != nil else { return nil }
            
            let decoded = try JSONDecoder().decode(OMLXStatusResponse.self, from: data)
            return decoded.loaded_models ?? []
        } catch {
            return nil
        }
    }
    
    private func fetchOpenAIModels(port: Int) async -> [String]? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/models") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard json?["data"] != nil else { return nil }
            
            let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            return decoded.data.map { $0.id }
        } catch {
            return nil
        }
    }
    
    private func runCommand(_ command: String, args: [String]) -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        task.arguments = args
        if command == "ps" {
            task.executableURL = URL(fileURLWithPath: "/bin/ps")
        } else if command == "lsof" {
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        } else {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = [command] + args
        }
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
