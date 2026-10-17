import Foundation
import GreenCore

/// Returns `output` if set, otherwise echoes the source image.
public struct FakeImageEditor: ImageEditor {
    public var output: Data?
    public var latency: Duration

    public init(output: Data? = nil, latency: Duration = .zero) {
        self.output = output
        self.latency = latency
    }

    public func editImage(_ image: Data, prompt: String) async throws -> Data {
        try await simulateLatency(latency)
        return output ?? image
    }
}
