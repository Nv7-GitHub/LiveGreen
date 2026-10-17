/// Optional artificial delay so demo-mode progress UI is visible.
func simulateLatency(_ latency: Duration) async throws {
    if latency > .zero { try await Task.sleep(for: latency) }
}
