import Foundation

/// Generates the greener-setup picture (spec §7: xAI Grok image edit, 60 s timeout).
public protocol ImageEditor: Sendable {
    /// - Parameters:
    ///   - image: Source JPEG.
    ///   - prompt: Edit instructions built from the chosen swaps.
    /// - Returns: Edited image bytes (JPEG or PNG).
    func editImage(_ image: Data, prompt: String) async throws -> Data
}
