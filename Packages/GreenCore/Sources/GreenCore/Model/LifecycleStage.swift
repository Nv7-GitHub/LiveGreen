/// Lifecycle stages shown in the flow view (spec §6).
public enum LifecycleStage: String, Codable, Sendable, Hashable, CaseIterable, CodingKeyRepresentable {
    case materials
    case manufacturing
    case transport
    case use
    case endOfLife

    public var displayName: String {
        switch self {
        case .materials: "Materials"
        case .manufacturing: "Manufacturing"
        case .transport: "Transport"
        case .use: "Use"
        case .endOfLife: "End of life"
        }
    }
}
