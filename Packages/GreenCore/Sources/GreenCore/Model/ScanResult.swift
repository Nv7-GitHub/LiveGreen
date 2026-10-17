import Foundation

/// How a scan was captured.
public enum ScanMode: String, Codable, Sendable, Hashable, CaseIterable {
    case photo
    case ar
    case barcode

    public var displayName: String {
        switch self {
        case .photo: "Photo"
        case .ar: "AR"
        case .barcode: "Barcode"
        }
    }
}

/// The outcome of one scan (spec §4).
public struct ScanResult: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var date: Date
    public var title: String
    public var mode: ScanMode
    /// JPEG of the captured frame.
    public var photo: Data?
    public var components: [Component]
    public var totals: [MetricKey: Measured]
    /// Generated greener-setup JPEG/PNG.
    public var greenerImage: Data?
    /// Chosen alternative per component (component id → alternative id).
    public var selectedAlternatives: [UUID: UUID]

    public init(id: UUID = UUID(), date: Date = Date(), title: String, mode: ScanMode = .photo, photo: Data? = nil,
                components: [Component] = [], totals: [MetricKey: Measured] = [:], greenerImage: Data? = nil,
                selectedAlternatives: [UUID: UUID] = [:]) {
        self.id = id
        self.date = date
        self.title = title
        self.mode = mode
        self.photo = photo
        self.components = components
        self.totals = totals
        self.greenerImage = greenerImage
        self.selectedAlternatives = selectedAlternatives
    }

    /// Monte Carlo seed derived from the scan id so results are reproducible (spec §5.6).
    public var seed: UInt64 {
        withUnsafeBytes(of: id.uuid) { raw in
            raw.loadUnaligned(fromByteOffset: 0, as: UInt64.self) ^ raw.loadUnaligned(fromByteOffset: 8, as: UInt64.self)
        }
    }

    public func component(withID id: UUID) -> Component? {
        components.first { $0.id == id }
    }
}
