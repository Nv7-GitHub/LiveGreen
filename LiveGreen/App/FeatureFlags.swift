import Foundation
import GreenCore

/// User-adjustable switches, persisted in UserDefaults and overridable by launch arguments:
/// `-ScanMode ar|photo|barcode`, `-DemoMode YES`, `-PlugFeatures NO`, `-AIProvider grok|claude`,
/// `-ModelChoice sonnet|opus`, `-MockPlug YES`.
nonisolated struct FeatureFlags: Codable, Hashable, Sendable {
    var scanMode: ScanMode = .photo
    var demoMode = false
    var plugFeaturesEnabled = true
    var aiProvider: AIProvider = .grok
    var modelChoice: ClaudeModel = .opus
    var useMockPlug = false

    static let defaultsKey = "LiveGreen.featureFlags"

    init() {}

    /// Missing keys keep their defaults, so flags saved by an older build still load.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = FeatureFlags()
        scanMode = try container.decodeIfPresent(ScanMode.self, forKey: .scanMode) ?? defaults.scanMode
        demoMode = try container.decodeIfPresent(Bool.self, forKey: .demoMode) ?? defaults.demoMode
        plugFeaturesEnabled = try container.decodeIfPresent(Bool.self, forKey: .plugFeaturesEnabled) ?? defaults.plugFeaturesEnabled
        aiProvider = try container.decodeIfPresent(AIProvider.self, forKey: .aiProvider) ?? defaults.aiProvider
        modelChoice = try container.decodeIfPresent(ClaudeModel.self, forKey: .modelChoice) ?? defaults.modelChoice
        useMockPlug = try container.decodeIfPresent(Bool.self, forKey: .useMockPlug) ?? defaults.useMockPlug
    }

    static func load(defaults: UserDefaults = .standard,
                     arguments: LaunchArguments = LaunchArguments()) -> FeatureFlags {
        var flags = defaults.data(forKey: defaultsKey)
            .flatMap { try? JSONDecoder().decode(FeatureFlags.self, from: $0) } ?? FeatureFlags()
        arguments.apply(to: &flags)
        return flags
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

/// Parses `-Name value` launch arguments (Xcode scheme or UI tests).
nonisolated struct LaunchArguments: Sendable {
    let arguments: [String]

    init(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.arguments = arguments
    }

    func string(_ name: String) -> String? {
        guard let index = arguments.firstIndex(of: "-\(name)"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    func bool(_ name: String) -> Bool? {
        string(name).map { ["yes", "true", "1"].contains($0.lowercased()) }
    }

    /// Start without showing onboarding (UI tests, demos).
    var skipOnboarding: Bool { bool("SkipOnboarding") ?? false }
    /// Use a throwaway in-memory SwiftData store.
    var inMemoryStore: Bool { bool("InMemoryStore") ?? false }

    func apply(to flags: inout FeatureFlags) {
        if let mode = string("ScanMode").flatMap({ ScanMode(rawValue: $0.lowercased()) }) { flags.scanMode = mode }
        if let demo = bool("DemoMode") { flags.demoMode = demo }
        if let plug = bool("PlugFeatures") { flags.plugFeaturesEnabled = plug }
        if let mock = bool("MockPlug") { flags.useMockPlug = mock }
        if let provider = string("AIProvider").flatMap({ AIProvider(rawValue: $0.lowercased()) }) { flags.aiProvider = provider }
        if let model = string("ModelChoice")?.lowercased() {
            flags.modelChoice = ClaudeModel(rawValue: model)
                ?? ClaudeModel.allCases.first { "\($0)" == model } ?? flags.modelChoice
        }
    }
}
