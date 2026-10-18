import Foundation

/// Photon Beta (2.0) messaging over `https://api.photon.codes/v1`, used for the iMessage nudges.
///
/// The project is on shared iMessage lines, which shape the flow:
/// 1. `assign(handle:firstName:)` maps the user's phone number onto one of the project's pooled lines and returns
///    that line's number (the agent).
/// 2. The user texts that number once. A shared line can't send a first message, only reply to a peer who has
///    messaged it since the assignment.
/// 3. `conversation(with:)` finds that inbound message, which names the direct space and the agent user, and
///    `sendText(_:in:)` sends into it.
public struct PhotonClient: Sendable {
    public struct Configuration: Sendable {
        /// A project API key (`pho_sk_…`) with project:read, project:write and platforms:write.
        public var apiKey: String?
        /// `pho_prj_…`
        public var projectID: String?
        public var baseURL: URL
        public var timeout: Double

        public init(apiKey: String?, projectID: String?, baseURL: URL = URL(string: "https://api.photon.codes")!,
                    timeout: Double = 20) {
            self.apiKey = apiKey
            self.projectID = projectID
            self.baseURL = baseURL
            self.timeout = timeout
        }
    }

    /// A direct iMessage chat between the user and their assigned line.
    public struct Conversation: Sendable, Hashable, Codable {
        public var spaceID: String
        /// The agent's (the shared line's) user id, which sends.
        public var agentUserID: String

        public init(spaceID: String, agentUserID: String) {
            self.spaceID = spaceID
            self.agentUserID = agentUserID
        }
    }

    public var configuration: Configuration
    let transport: any HTTPTransport

    public init(configuration: Configuration, transport: any HTTPTransport = URLSessionTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    public var isConfigured: Bool {
        configuration.apiKey?.trimmedNonEmpty != nil && configuration.projectID?.trimmedNonEmpty != nil
    }

    // MARK: - Calls

    /// Assigns the user's handle to a shared line and returns the line's phone number. The idempotency key is
    /// derived from the handle, so asking again for the same number returns the same assignment.
    public func assign(handle: String, firstName: String?) async throws -> String {
        var body: [String: JSONValue] = ["handle": .string(handle)]
        if let firstName = firstName?.trimmedNonEmpty { body["firstName"] = .string(String(firstName.prefix(100))) }
        let reply = try await call("POST", "platforms/imessage/assignments", body: .object(body),
                                   idempotencyKey: "livegreen-assign-\(Self.keySafe(handle))")
        guard let number = reply["assignedPhoneNumber"]?.string else {
            throw GreenCoreError.decoding("Photon assignment had no assignedPhoneNumber")
        }
        return number
    }

    /// An existing assignment for the handle, if the project has one (released ones excluded).
    public func existingAssignment(handle: String) async throws -> String? {
        let reply = try await call("GET", "platforms/imessage/assignments",
                                   query: [URLQueryItem(name: "pageSize", value: "100")])
        let match = (reply["assignments"]?.array ?? []).first { $0["handle"]?.string == handle }
        return match?["assignedPhoneNumber"]?.string
    }

    /// The chat the user started by texting their line, or nil while they have not texted it yet.
    public func conversation(with handle: String) async throws -> Conversation? {
        let reply = try await call("GET", "messages", query: [
            URLQueryItem(name: "platform", value: "imessage"),
            URLQueryItem(name: "direction", value: "received"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "pageSize", value: "100"),
        ])
        for message in reply["items"]?.array ?? [] where message["sentBy"]?["handle"]?.string == handle {
            guard let space = message["space"]?["id"]?.string else { continue }
            if let agent = message["receivedBy"]?["id"]?.string {
                return Conversation(spaceID: space, agentUserID: agent)
            }
            // No receivedBy: the agent is the space's other participant.
            let sender = message["sentBy"]?["id"]?.string
            if let agent = (message["space"]?["participantIds"]?.array ?? []).compactMap(\.string).first(where: { $0 != sender }) {
                return Conversation(spaceID: space, agentUserID: agent)
            }
        }
        return nil
    }

    /// Sends plain text into the conversation. Photon accepts it for asynchronous delivery (202); the returned id
    /// is the message's. `idempotencyKey` makes a retry of the same nudge send it once.
    @discardableResult
    public func sendText(_ text: String, in conversation: Conversation, idempotencyKey: String) async throws -> String? {
        let body: JSONValue = [
            "spaceId": .string(conversation.spaceID),
            "senderId": .string(conversation.agentUserID),
            "content": ["type": "text", "format": "plain", "text": .string(text)],
        ]
        let reply = try await call("POST", "messages", body: body, idempotencyKey: Self.keySafe(idempotencyKey))
        return reply["id"]?.string
    }

    // MARK: - Transport

    func call(_ method: String, _ path: String, query: [URLQueryItem] = [], body: JSONValue? = nil,
              idempotencyKey: String? = nil) async throws -> JSONValue {
        guard let apiKey = configuration.apiKey?.trimmedNonEmpty else { throw GreenCoreError.missingAPIKey("PHOTON_API_KEY") }
        guard let project = configuration.projectID?.trimmedNonEmpty else { throw GreenCoreError.missingAPIKey("PHOTON_PROJECT_ID") }
        var url = configuration.baseURL.appending(path: "v1/projects/\(project)/\(path)")
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = configuration.timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let idempotencyKey { request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await transport.send(request)
        guard response.isSuccess else {
            throw GreenCoreError.http(status: response.statusCode, body: Self.problemSummary(data))
        }
        guard !data.isEmpty else { return .null }
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw GreenCoreError.decoding("Photon response: \(error)")
        }
    }

    /// The problem document's title and detail, which say what Photon refused.
    static func problemSummary(_ data: Data) -> String {
        guard let problem = try? JSONDecoder().decode(JSONValue.self, from: data) else { return data.bodyPreview }
        let parts = [problem["code"]?.string, problem["title"]?.string, problem["detail"]?.string].compactMap { $0 }
        return parts.isEmpty ? data.bodyPreview : parts.joined(separator: ": ")
    }

    /// Idempotency keys are printable ASCII without spaces, at most 255 characters.
    static func keySafe(_ raw: String) -> String {
        String(raw.unicodeScalars.filter { (0x21...0x7e).contains($0.value) }.map(Character.init).prefix(255))
    }

    /// E.164 for a typed phone number: a 10-digit number is taken as US (+1). Nil when it can't be one.
    public static func e164(_ typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber)
        if trimmed.hasPrefix("+") { return (8...15).contains(digits.count) && digits.first != "0" ? "+" + digits : nil }
        if digits.count == 10 { return "+1" + digits }
        if digits.count == 11, digits.first == "1" { return "+" + digits }
        return nil
    }
}
