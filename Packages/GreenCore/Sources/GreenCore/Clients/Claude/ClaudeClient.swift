import Foundation

/// Claude Messages API client (raw HTTP; there is no official Swift SDK). Implements the identify,
/// alternatives and spec-research calls of spec §5.3, §5.4 (T2) and §7.
public struct ClaudeClient: Sendable {
    public struct Configuration: Sendable {
        /// `ANTHROPIC_API_KEY`. Calls throw `GreenCoreError.missingAPIKey` while it is nil or empty.
        public var apiKey: String?
        /// `ANTHROPIC_WORKSPACE_ID`, sent as `anthropic-workspace-id`. Only needed for a key that is not scoped
        /// to a workspace (the API answers 400 without it); workspace-scoped keys leave it nil.
        public var workspaceID: String?
        public var model: ClaudeModel
        public var baseURL: URL
        public var identifyTimeout: Double
        public var alternativesTimeout: Double
        public var researchTimeout: Double
        public var identifyEffort: ClaudeEffort
        public var alternativesEffort: ClaudeEffort
        public var researchEffort: ClaudeEffort
        /// Opt into server-side refusal fallbacks (`fallbacks: "default"`). Automatically dropped
        /// for the request if the API rejects the beta.
        public var serverSideFallbacks: Bool
        /// Max `web_search` / `web_fetch` uses per research call.
        public var researchSearchLimit: Int
        public var researchFetchLimit: Int
        /// Reference-table keys the identify prompt steers `food_group` / `device_type` / materials toward.
        public var vocabulary: ReferenceVocabulary
        public var retry: RetryPolicy

        public init(apiKey: String?, workspaceID: String? = nil, model: ClaudeModel = .sonnet,
                    baseURL: URL = URL(string: "https://api.anthropic.com")!,
                    identifyTimeout: Double = 30, alternativesTimeout: Double = 45, researchTimeout: Double = 45,
                    identifyEffort: ClaudeEffort = .low, alternativesEffort: ClaudeEffort = .low,
                    researchEffort: ClaudeEffort = .medium, serverSideFallbacks: Bool = true,
                    researchSearchLimit: Int = 4, researchFetchLimit: Int = 3,
                    vocabulary: ReferenceVocabulary = .default, retry: RetryPolicy = .default) {
            self.apiKey = apiKey
            self.workspaceID = workspaceID
            self.model = model
            self.baseURL = baseURL
            self.identifyTimeout = identifyTimeout
            self.alternativesTimeout = alternativesTimeout
            self.researchTimeout = researchTimeout
            self.identifyEffort = identifyEffort
            self.alternativesEffort = alternativesEffort
            self.researchEffort = researchEffort
            self.serverSideFallbacks = serverSideFallbacks
            self.researchSearchLimit = researchSearchLimit
            self.researchFetchLimit = researchFetchLimit
            self.vocabulary = vocabulary
            self.retry = retry
        }
    }

    public var configuration: Configuration
    let transport: any HTTPTransport

    public init(configuration: Configuration, transport: any HTTPTransport = URLSessionTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    public init(apiKey: String?, model: ClaudeModel = .sonnet, transport: any HTTPTransport = URLSessionTransport()) {
        self.init(configuration: Configuration(apiKey: apiKey, model: model), transport: transport)
    }

    static let apiVersion = "2023-06-01"
    static let fallbackBeta = "server-side-fallback-2026-07-01"
}

/// Keys of the bundled reference tables, so identify output lines up with the factor model (T3).
public struct ReferenceVocabulary: Sendable, Hashable {
    public var foodGroups: [String]
    public var deviceTypes: [String]
    public var materials: [String]

    public init(foodGroups: [String], deviceTypes: [String], materials: [String]) {
        self.foodGroups = foodGroups
        self.deviceTypes = deviceTypes
        self.materials = materials
    }

    public static let `default` = ReferenceVocabulary(
        foodGroups: ["beef", "lamb", "pork", "poultry", "fish", "shrimp", "eggs", "cheese", "milk", "plant_milk",
                     "tofu", "beans", "nuts", "rice", "wheat_bread", "pasta", "potatoes", "vegetables", "fruit",
                     "bananas", "chocolate", "coffee", "tea", "soft_drinks", "beer", "wine", "bottled_water"],
        deviceTypes: ["laptop", "desktop", "monitor", "television", "smartphone", "tablet", "game_console",
                      "router", "speaker", "headphones", "led_lamp", "phone_charger", "laptop_charger",
                      "ebike", "ebike_charger", "escooter", "power_bank", "power_strip", "refrigerator",
                      "dishwasher", "washer", "dryer", "microwave", "kettle", "coffee_maker", "ev_charger"],
        materials: ["cotton", "organic_cotton", "polyester", "recycled_polyester", "nylon", "wool", "linen",
                    "viscose", "elastane", "polyethylene", "pet", "hdpe", "polypropylene", "polystyrene", "pvc",
                    "aluminium", "steel", "glass", "paper", "paperboard", "wood", "ceramic", "silicone"])
}
