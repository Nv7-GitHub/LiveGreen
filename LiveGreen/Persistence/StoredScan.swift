import Foundation
import SwiftData
import GreenCore

/// A saved scan. The `ScanResult` is stored as JSON; images live in external storage.
@Model
final class StoredScan {
    @Attribute(.unique) var id: UUID
    var date: Date
    var title: String
    var payload: Data
    @Attribute(.externalStorage) var photo: Data?
    @Attribute(.externalStorage) var greenerImage: Data?

    init(result: ScanResult) throws {
        id = result.id
        date = result.date
        title = result.title
        payload = Data()
        try update(from: result)
    }

    func update(from result: ScanResult) throws {
        var stripped = result
        stripped.photo = nil
        stripped.greenerImage = nil
        date = result.date
        title = result.title
        payload = try JSONEncoder().encode(stripped)
        photo = result.photo
        greenerImage = result.greenerImage
    }

    func result() throws -> ScanResult {
        var result = try JSONDecoder().decode(ScanResult.self, from: payload)
        result.photo = photo
        result.greenerImage = greenerImage
        return result
    }
}
