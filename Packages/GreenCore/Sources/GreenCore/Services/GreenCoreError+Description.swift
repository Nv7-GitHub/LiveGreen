import Foundation

extension GreenCoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let key): "No \(key) is set. Add it in Settings, or turn on Demo mode."
        case .http(let status, _) where status == 401 || status == 403: "The service rejected the API key (HTTP \(status))."
        case .http(let status, _): "The service returned an error (HTTP \(status))."
        case .decoding(let detail): "Unexpected response: \(detail)"
        case .invalidModelOutput(let detail): "The AI's answer couldn't be used: \(detail)"
        case .timeout: "The request took too long."
        case .unsupported(let reason): reason
        case .notFound: "Nothing was found."
        }
    }
}
