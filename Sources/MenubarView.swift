import SwiftUI

struct MenubarView: View {
    @ObservedObject var monitor: ServerMonitor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LLM Tracker")
                    .font(.headline)
                Spacer()
                if monitor.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(action: {
                    monitor.refresh()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 10)
            
            Divider()
            
            if monitor.instances.isEmpty {
                Text("No LLM servers detected.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(monitor.instances) { instance in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(instance.name)
                                    .font(.subheadline)
                                    .bold()
                                Spacer()
                                Text("Port: \(instance.port.map { String($0) } ?? "Unknown")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Button(action: {
                                    monitor.quitInstance(pid: instance.pid)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .help("Stop Instance")
                            }
                            
                            if let owner = instance.owningApp {
                                Text("Owner: \(owner)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if !instance.loadedModels.isEmpty {
                                Text("Models:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                                ForEach(instance.loadedModels, id: \.self) { model in
                                    Text("• \(model)")
                                        .font(.caption)
                                        .padding(.leading, 8)
                                }
                            } else {
                                Text("No models loaded.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        
                        Divider()
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: 600)
            }
            
            HStack {
                Spacer()
                Button("Quit LLM Tracker") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
                .padding(.bottom, 10)
                Spacer()
            }
        }
        .frame(width: 300)
    }
}
