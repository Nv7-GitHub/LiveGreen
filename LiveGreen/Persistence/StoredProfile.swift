import Foundation
import SwiftData
import GreenCore

/// The single onboarding profile, stored as JSON.
@Model
final class StoredProfile {
    var payload: Data
    var updatedAt: Date

    init(profile: UserProfile) throws {
        payload = try JSONEncoder().encode(profile)
        updatedAt = Date()
    }

    func profile() throws -> UserProfile {
        try JSONDecoder().decode(UserProfile.self, from: payload)
    }
}
