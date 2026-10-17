import Foundation

/// Runs `operation`, throwing `GreenCoreError.timeout` if it has not finished within `seconds`
/// (spec §11: identify 30 s, research 45 s, image 60 s). The deadline covers retries too.
func withDeadline<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw GreenCoreError.timeout
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw GreenCoreError.timeout }
        return result
    }
}
