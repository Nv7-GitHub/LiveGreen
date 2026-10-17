import Foundation

/// xAI Grok image edit (spec §7): `POST https://api.x.ai/v1/images/edits` with the source photo as a
/// base64 data URI. Handles both `data[0].url` (downloaded) and `data[0].b64_json` responses.
public struct GrokImageClient: ImageEditor {
    public struct Configuration: Sendable {
        /// `XAI_API_KEY`. Calls throw `GreenCoreError.missingAPIKey` while it is nil or empty.
        public var apiKey: String?
        public var model: String
        public var baseURL: URL
        public var timeout: Double
        public var retry: RetryPolicy

        public init(apiKey: String?, model: String = "grok-imagine-image-2.0",
                    baseURL: URL = URL(string: "https://api.x.ai")!, timeout: Double = 60, retry: RetryPolicy = .default) {
            self.apiKey = apiKey
            self.model = model
            self.baseURL = baseURL
            self.timeout = timeout
            self.retry = retry
        }
    }

    public var configuration: Configuration
    let transport: any HTTPTransport

    public init(configuration: Configuration, transport: any HTTPTransport = URLSessionTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    public init(apiKey: String?, transport: any HTTPTransport = URLSessionTransport()) {
        self.init(configuration: Configuration(apiKey: apiKey), transport: transport)
    }

    public func editImage(_ image: Data, prompt: String) async throws -> Data {
        guard let apiKey = configuration.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw GreenCoreError.missingAPIKey("XAI_API_KEY")
        }
        let request = try editRequest(image: image, prompt: prompt, apiKey: apiKey)
        return try await withDeadline(seconds: configuration.timeout) {
            let (data, response) = try await configuration.retry.send(request, via: transport)
            guard response.isSuccess else { throw GreenCoreError.http(status: response.statusCode, body: data.bodyPreview) }
            return try await imageData(from: data)
        }
    }

    func editRequest(image: Data, prompt: String, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: configuration.baseURL.appending(path: "v1/images/edits"))
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body = EditBody(model: configuration.model, prompt: prompt, image: .init(
            url: "data:\(ImageBlock.mediaType(of: image));base64,\(image.base64EncodedString())", type: "image_url"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        request.httpBody = try encoder.encode(body)
        return request
    }

    /// Decodes `b64_json` directly, or downloads `url`.
    func imageData(from data: Data) async throws -> Data {
        let payload: EditResponse
        do {
            payload = try JSONDecoder().decode(EditResponse.self, from: data)
        } catch {
            throw GreenCoreError.decoding("Grok image response: \(error)")
        }
        guard let first = payload.data.first else { throw GreenCoreError.invalidModelOutput("Grok returned no image") }
        if let base64 = first.b64Json, let image = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) {
            return image
        }
        guard let raw = first.url, let url = URL(string: raw) else {
            throw GreenCoreError.invalidModelOutput("Grok image has neither url nor b64_json")
        }
        var download = URLRequest(url: url)
        download.timeoutInterval = configuration.timeout
        let (image, response) = try await transport.send(download)
        guard response.isSuccess, !image.isEmpty else { throw GreenCoreError.http(status: response.statusCode, body: image.bodyPreview) }
        return image
    }

    struct EditBody: Encodable {
        struct Image: Encodable {
            var url: String
            var type: String
        }
        var model: String
        var prompt: String
        var image: Image
    }

    struct EditResponse: Decodable {
        struct Item: Decodable {
            var url: String?
            var b64Json: String?

            enum CodingKeys: String, CodingKey {
                case url
                case b64Json = "b64_json"
            }
        }
        var data: [Item]
    }
}
