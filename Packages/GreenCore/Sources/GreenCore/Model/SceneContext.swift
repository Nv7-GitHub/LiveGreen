import Foundation

/// What kind of scene a photo shows (identify's `scene_context`), which decides whose items they are. Only the user's
/// own things belong in their totals and leaderboard footprint: not a stranger's car, a store's freezer of stock or
/// a post scrolled past on a phone.
public enum SceneContext: String, Codable, Sendable, Hashable, CaseIterable {
    /// The user's home, desk, meal or belongings.
    case own
    /// Products for sale: shelves, a display case or freezer, an aisle.
    case storeDisplay = "store_display"
    /// A public place: parked cars, buildings, other people's things.
    case street
    /// A capture of a phone or computer screen: a social post, a shopping app, a web page.
    case screenshot

    /// Scenes where most items are not the user's, so the app asks which ones are.
    public var asksWhichIsYours: Bool { self == .storeDisplay || self == .street }

    /// Accepts the raw values plus loose spellings ("Store display", "store-display").
    public init?(looseRawValue raw: String) {
        let key = raw.lowercased().filter(\.isLetter)
        guard let match = Self.allCases.first(where: { $0.rawValue.filter(\.isLetter) == key }) else { return nil }
        self = match
    }
}

/// Why an item is left out of the user's totals until they say it is theirs.
public enum Exclusion: String, Codable, Sendable, Hashable, CaseIterable {
    /// Someone else's, store stock or a fixture of the place (identify's `likely_owned: false`, or the default in a
    /// store or street scene).
    case notOwned
    /// Incidental: only partly visible behind or beside what the photo is of.
    case background
    /// In a screenshot: seen on screen, not bought.
    case onScreen
}

extension Component {
    /// Whether the item counts toward the user's leaderboard footprint: the user's own answer when they gave one,
    /// else unless the scan left it out (`exclusion`).
    public var isCounted: Bool { markedOwned ?? (exclusion == nil) }

    /// Whether its scan's results add the item up: a counted item, or one seen on screen, which is shown as what it
    /// would add if bought (it reaches the footprint only when the user marks it as theirs). Swaps are offered for
    /// these items only.
    public var isTotaled: Bool { markedOwned ?? (exclusion == nil || exclusion == .onScreen) }
}

extension IdentifiedComponent {
    /// The default exclusion for an item identify reported in `scene`: everything in a screenshot is seen on screen;
    /// otherwise identify's own call, and in a store or street scene an item counts only when identify said it is
    /// likely the user's.
    func exclusion(in scene: SceneContext?) -> Exclusion? {
        if scene == .screenshot { return .onScreen }
        if likelyOwned == false { return .notOwned }
        if background == true { return .background }
        if likelyOwned == nil, scene?.asksWhichIsYours == true { return .notOwned }
        return nil
    }
}

extension ScanResult {
    public var isScreenshot: Bool { sceneContext == .screenshot }

    /// Whether the results screen adds the item up (`Component.isTotaled`): in a screenshot, any item the user did not
    /// remove, framed as what it would add if bought.
    public func isTotaled(_ component: Component) -> Bool { component.isTotaled }

    /// The items the results headline, list shares and saved totals cover.
    public var totaledComponents: [Component] { components.filter(\.isTotaled) }

    /// The items listed apart as not counted.
    public var notCountedComponents: [Component] { components.filter { !$0.isTotaled } }

    /// The items that count toward the user's footprint and the leaderboard (`ScannedFootprint`).
    public var countedComponents: [Component] { components.filter(\.isCounted) }

    /// A store or street scan whose items the user has not sorted yet ("Which is yours?").
    public var asksWhichIsYours: Bool {
        (sceneContext?.asksWhichIsYours ?? false) && !components.isEmpty
            && components.allSatisfy { $0.markedOwned == nil }
    }

    /// Records the user's answer for one item ("Not mine", "It's mine"; nil goes back to the scan's guess) and
    /// recomputes the totals.
    public mutating func markOwned(_ owned: Bool?, componentID: UUID, engine: ImpactEngine) {
        guard let index = components.firstIndex(where: { $0.id == componentID }) else { return }
        components[index].markedOwned = owned
        updateTotals(engine: engine)
    }

    /// "Which is yours?": exactly the items in `owned` are the user's.
    public mutating func markOwned(only owned: Set<UUID>, engine: ImpactEngine) {
        for index in components.indices { components[index].markedOwned = owned.contains(components[index].id) }
        updateTotals(engine: engine)
    }
}
