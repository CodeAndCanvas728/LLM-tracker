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
        "vmlx", "vllm-mlx", "mlx-audio", "mlx-vlm", "mflux"
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
        
        let processOutput = runCommand("ps", args: ["-eo", "pid,ppid,command", "-ww"])
        let lines = processOutput.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.contains("PID") { continue }
            
            let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            if parts.count == 3 {
                let pidStr = String(parts[0])
                let ppidStr = String(parts[1])
                let cmd = String(parts[2])
                
                // Exclude grep or our own app just in case
                if cmd.contains("grep") || cmd.contains("LLMTracker") { continue }
                
                if serverKeywords.contains(where: { cmd.localizedCaseInsensitiveContains($0) }) {
                    if let pid = Int32(pidStr), let ppid = Int32(ppidStr) {
                        let name = determineServerName(from: cmd)
                        let owningApp = determineOwningApp(ppid: ppid)
                        let port = determinePort(for: pid)
                        
                        var loadedModels: [String] = []
                        if name.lowercased().contains("ollama") {
                            if let port = port {
                                loadedModels = await fetchOllamaModels(port: port)
                            }
                        } else if name == "OMLX" {
                            if let port = port {
                                let omlxModels = await fetchOMLXStatus(port: port)
                                if !omlxModels.isEmpty {
                                    loadedModels = omlxModels
                                } else if let extractedModel = extractModel(from: cmd) {
                                    loadedModels = [extractedModel]
                                } else {
                                    loadedModels = ["Dynamic / Auto-loaded"]
                                }
                            }
                        } else {
                            if let extractedModel = extractModel(from: cmd) {
                                loadedModels = [extractedModel]
                            } else {
                                loadedModels = ["Dynamic / Auto-loaded"]
                            }
                        }
                        
                        let instance = ServerInstance(pid: pid, name: name, port: port, loadedModels: loadedModels, owningApp: owningApp)
                        foundInstances.append(instance)
                    }
                }
            }
        }
        
        return foundInstances
    }
    
    private func determineServerName(from cmd: String) -> String {
        for keyword in serverKeywords {
            if cmd.localizedCaseInsensitiveContains(keyword) {
                if keyword == "ollama" { return "Ollama" }
                if keyword == "vllm" { return "vLLM" }
                if keyword == "mlx_lm" || keyword == "mlx-lm" { return "MLX-LM" }
                if keyword == "omlx" { return "OMLX" }
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
    
    private func determinePort(for pid: Int32) -> Int? {
        let output = runCommand("lsof", args: ["-iTCP", "-sTCP:LISTEN", "-P", "-n", "-a", "-p", "\(pid)"])
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("LISTEN") {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                // usually column 8 is the port binding e.g., *:11434 or localhost:8080 or 127.0.0.1:8000
                for part in parts {
                    if part.contains(":") {
                        let components = part.split(separator: ":")
                        if let portStr = components.last, let port = Int(portStr) {
                            return port
                        }
                    }
                }
            }
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
    
    private func fetchOllamaModels(port: Int) async -> [String] {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/ps") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(OllamaPSResponse.self, from: data)
            return response.models.map { $0.name }
        } catch {
            return []
        }
    }
    
    private func fetchOMLXStatus(port: Int) async -> [String] {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/status") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(OMLXStatusResponse.self, from: data)
            return response.loaded_models ?? []
        } catch {
            return []
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
