import Foundation

struct ServerInstance: Identifiable, Equatable {
    var id: Int32 { pid }
    let pid: Int32
    let name: String
    let port: Int?
    let loadedModels: [String]
    let owningApp: String?
}

struct OllamaPSResponse: Codable {
    let models: [OllamaModel]
}

struct OllamaModel: Codable {
    let name: String
    let model: String
    let size: Int64
}

struct OpenAIModelsResponse: Codable {
    let data: [OpenAIModel]
}

struct OpenAIModel: Codable {
    let id: String
}

struct OMLXStatusResponse: Codable {
    let loaded_models: [String]?
}
