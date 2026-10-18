import Foundation

extension ClaudeClient {
    /// The streamed identify with the user's notes on earlier scans sent as a separate "hints only" text block
    /// after the usual hints (`ScanFeedback.promptSection`). Without notes it is the plain identify call.
    public func identify(image: Data, hints: OCRHints, profile: UserProfile, feedback: [ScanFeedback],
                         progress: @escaping @Sendable (IdentifyProgress) -> Void) async throws -> IdentifyResponse {
        var client = self
        client.identifyFeedback = feedback
        return try await client.identify(image: image, hints: hints, profile: profile, progress: progress)
    }
}
