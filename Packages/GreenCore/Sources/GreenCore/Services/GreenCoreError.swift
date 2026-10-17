/// Errors shared by GreenCore clients and resolvers.
public enum GreenCoreError: Error, Sendable, Hashable {
    /// A required API key is not configured; the associated value names it (e.g. "ANTHROPIC_API_KEY").
    case missingAPIKey(String)
    /// Non-2xx HTTP response.
    case http(status: Int, body: String)
    /// A response could not be decoded.
    case decoding(String)
    /// The model did not return the forced tool call or returned invalid input.
    case invalidModelOutput(String)
    case timeout
    /// A device or record exists but is not supported (e.g. Shelly Gen1).
    case unsupported(String)
    case notFound
}
