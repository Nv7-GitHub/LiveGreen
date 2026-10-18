import Foundation

/// API keys the app uses. Raw value is the Info.plist / xcconfig key.
nonisolated enum SecretKey: String, CaseIterable, Identifiable, Sendable {
    case anthropic = "ANTHROPIC_API_KEY"
    case anthropicWorkspace = "ANTHROPIC_WORKSPACE_ID"
    case xai = "XAI_API_KEY"
    case electricityMaps = "ELECTRICITYMAPS_API_KEY"
    case energyStar = "ENERGYSTAR_APP_TOKEN"
    case photon = "PHOTON_API_KEY"
    case photonProject = "PHOTON_PROJECT_ID"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic (Claude)"
        case .anthropicWorkspace: "Anthropic workspace ID (unscoped keys only)"
        case .xai: "xAI (Grok image)"
        case .electricityMaps: "Electricity Maps"
        case .energyStar: "ENERGY STAR app token"
        case .photon: "Photon API key (iMessage nudges)"
        case .photonProject: "Photon project ID"
        }
    }

    /// xAI is always needed (greener image), Anthropic for the analysis provider (Claude by default). The
    /// workspace ID is only needed for an Anthropic key that is not scoped to a workspace. ENERGY STAR
    /// works without a token (rate-limited); without Electricity Maps the grid uses free EIA data.
    func isRequired(for provider: AIProvider) -> Bool {
        self == .xai || self == provider.key
    }
}

/// Reads keys: a Keychain override set in Settings wins over the Info.plist value from Secrets.xcconfig.
nonisolated struct Secrets: Sendable {
    var bundle: Bundle = .main

    func value(for key: SecretKey) -> String? {
        if let override = Keychain.read(account: key.rawValue), !override.isEmpty { return override }
        return infoPlistValue(for: key)
    }

    func infoPlistValue(for key: SecretKey) -> String? {
        guard let raw = bundle.object(forInfoDictionaryKey: key.rawValue) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unexpanded "$(KEY)" means the build setting was never defined.
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }

    func hasOverride(for key: SecretKey) -> Bool {
        Keychain.read(account: key.rawValue)?.isEmpty == false
    }

    /// Stores (or with nil/empty, clears) the Keychain override.
    func setOverride(_ value: String?, for key: SecretKey) throws {
        if let value, !value.isEmpty {
            try Keychain.write(value, account: key.rawValue)
        } else {
            Keychain.delete(account: key.rawValue)
        }
    }

    /// Required keys with no value; shown as a Settings banner.
    func missingRequiredKeys(for provider: AIProvider) -> [SecretKey] {
        SecretKey.allCases.filter { $0.isRequired(for: provider) && value(for: $0) == nil }
    }
}
