import Foundation

/// Tidies the words a suggester puts on a swap (S11 of the image QA), so a card reads as one plain item and one
/// sentence about it: no sizes or example lists in the name, no model or prompt talk in the rationale, no restating
/// of a profile the user may never have filled in, and no claim about a metric that the card's own chart contradicts.
public enum SwapText {
    // MARK: - Names

    /// The swap's name as a card title. Sizes and specs are dropped (they are in its quantities), and so are asides
    /// that only give examples or repeat the name: "Refurbished business laptop (e.g. ThinkPad T14), 14 in" becomes
    /// "Refurbished business laptop", "Buy a used city bike (second-hand)" becomes "Buy a used city bike".
    public static func name(_ raw: String) -> String {
        let original = collapsed(raw)
        var name = original
        for aside in asides(in: name).reversed() where dropsAside(aside.content, from: name) {
            name.removeSubrange(aside.range)
        }
        name = collapsed(name)
        if let match = trailingSpec.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
           let range = Range(match.range, in: name) {
            name.removeSubrange(range)
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—"))
        return capitalizedFirst(name.isEmpty ? original : name)
    }

    /// ", 14 in", ", 14-15 in", ", 22 fl oz", ", 500 ml" at the end of a name.
    static let trailingSpec = try! NSRegularExpression(
        pattern: #",\s*\d+(?:[.,]\d+)?(?:\s*[-–]\s*\d+(?:[.,]\d+)?)?\s*(?:-?inch(?:es)?|in\.?|"|”|cm|mm|fl\.?\s?oz|oz|ml|l|g|kg|lbs?|w|wh|kwh|gb|tb)\s*$"#,
        options: [.caseInsensitive])

    /// Size or serving notes inside an aside: "(one serving)", "(500 ml)", "(14-inch)".
    static let sizeNote = try! NSRegularExpression(
        pattern: #"^(?:(?:one|single|per|1)\s+serving|\d+(?:[.,]\d+)?\s*(?:-?inch(?:es)?|in|"|cm|mm|fl\.?\s?oz|oz|ml|l|g|kg|lbs?|w|pack|ct|count)\b.*)$"#,
        options: [.caseInsensitive])

    static let examplePrefixes = ["e.g", "eg ", "eg,", "i.e", "ie ", "such as", "for example", "for instance", "like "]
    static let conditionWords: Set<String> = ["second-hand", "secondhand", "second hand", "used", "pre-owned",
                                              "preowned", "refurbished", "renewed", "thrifted"]

    /// Whether an aside adds nothing a card title needs: examples, a size or serving, or a condition the rest of the
    /// name already states.
    static func dropsAside(_ content: String, from name: String) -> Bool {
        let text = content.trimmingCharacters(in: .whitespaces).lowercased()
        if text.isEmpty || examplePrefixes.contains(where: text.hasPrefix) { return true }
        if sizeNote.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { return true }
        if conditionWords.contains(text) {
            let rest = name.replacingOccurrences(of: "(\(content))", with: "")
            return Alternative.Condition(name: rest) != .new
        }
        return false
    }

    /// Top-level bracketed asides, with the space before each, so removing one leaves no double space.
    static func asides(in name: String) -> [(range: Range<String.Index>, content: String)] {
        var found: [(Range<String.Index>, String)] = []
        var start: String.Index?
        var depth = 0
        for index in name.indices {
            switch name[index] {
            case "(":
                if depth == 0 { start = index }
                depth += 1
            case ")" where depth > 0:
                depth -= 1
                guard depth == 0, let open = start else { continue }
                var lower = open
                while lower > name.startIndex, name[name.index(before: lower)] == " " { lower = name.index(before: lower) }
                found.append((lower..<name.index(after: index), String(name[name.index(after: open)..<index])))
            default:
                continue
            }
        }
        return found
    }

    // MARK: - Rationales

    /// The rationale without clauses that talk about modeling, the app, the instructions or the user's profile (the
    /// profile may be defaults the user never set: "The user commutes by transit…"), each kept clause a sentence.
    /// Empty when nothing is left; the pipeline then writes one from the comparison (`summary`).
    public static func rationale(_ raw: String) -> String {
        sentences(clauses(of: raw).filter { !leaksPromptOrProfile($0) })
    }

    /// Phrases that only appear when the model talks about its task, the app or the profile rather than the swap.
    static let leakPhrases = [
        "model precisely", "not recommended to model", "hard to model", "modeled", "modelled", "modeling", "modelling",
        "factor table", "factor model", "reference key", "food_group", "device_type", "fallback", "livegreen",
        "suggest_alternatives", "json", "schema", "the user", "user's", "user’s", "users'", "user profile",
        "the profile", "your profile", "their profile", "profile says", "onboarding", "you commute", "your commute",
        "you drive about", "you live in", "your household", "household of", "your diet",
    ]

    static func leaksPromptOrProfile(_ clause: String) -> Bool {
        let text = clause.lowercased()
        return leakPhrases.contains { text.contains($0) }
    }

    /// The rationale without sentences whose claim about a metric the swap's own comparison contradicts ("similar
    /// water and carbon" above charts saying 26% and 85% better), and when nothing is left, a plain line from what the
    /// card shows getting better. Claims the comparison cannot check (a metric it has no value for) are kept.
    public static func rationale(_ text: String, checkedAgainst original: Component, alternative: Alternative,
                                 engine: ImpactEngine = SwapMath.engine) -> String {
        let kept = clauses(of: text).filter { clause in
            claims(in: clause).allSatisfy { holds($0, original: original, alternative: alternative, engine: engine) }
        }
        let checked = sentences(kept)
        return checked.isEmpty ? summary(original, alternative, engine: engine) : checked
    }

    /// "Better on carbon, water and land use for the same job.", from the first three metrics the comparison shows
    /// getting better; empty when none does.
    public static func summary(_ original: Component, _ alternative: Alternative,
                               engine: ImpactEngine = SwapMath.engine) -> String {
        let better = SwapMath.chartPriority.filter { metric in
            guard let values = GreenScore.comparison(metric, original: original, alternative: alternative, engine: engine),
                  let change = SwapMath.change(metric, current: values.current, alternative: values.swap) else { return false }
            return change.isBetter
        }
        guard !better.isEmpty else { return "" }
        return "Better on \(list(better.prefix(3).map(phrase))) for the same job."
    }

    static func phrase(_ metric: MetricKey) -> String {
        switch metric {
        case .carbon: "carbon"
        case .water: "water"
        case .land: "land use"
        case .powerOn: "power draw"
        case .standbyPower: "standby power"
        case .yearlyElectricity: "electricity"
        case .lifespan: "lifespan"
        case .repairability: "repairability"
        case .plasticMass: "plastic"
        case .recyclablePercent: "recyclability"
        case .decompositionTime: "decomposition time"
        case .waterPollution: "water pollution"
        }
    }

    static func list(_ words: [String]) -> String {
        switch words.count {
        case 0: ""
        case 1: words[0]
        default: words.dropLast().joined(separator: ", ") + " and " + words[words.count - 1]
        }
    }

    // MARK: - Metric claims

    /// What a sentence says about one metric.
    struct Claim: Hashable {
        enum Direction: Hashable { case better, similar, worse }
        var metric: MetricKey
        var direction: Direction
    }

    static let metricWords: [String: MetricKey] = [
        "carbon": .carbon, "co2": .carbon, "emissions": .carbon, "emission": .carbon, "emit": .carbon,
        "emits": .carbon, "greenhouse": .carbon, "methane": .carbon, "water": .water, "land": .land,
        "farmland": .land, "plastic": .plasticMass, "plastics": .plasticMass, "electricity": .yearlyElectricity,
        "energy": .yearlyElectricity, "power": .yearlyElectricity, "kwh": .yearlyElectricity,
        "pollution": .waterPollution, "runoff": .waterPollution, "eutrophication": .waterPollution,
    ]

    static let directionWords: [String: Claim.Direction] = [
        "less": .better, "lower": .better, "fewer": .better, "cut": .better, "cuts": .better, "cutting": .better,
        "reduce": .better, "reduces": .better, "reduced": .better, "reducing": .better, "save": .better,
        "saves": .better, "saving": .better, "avoid": .better, "avoids": .better, "avoiding": .better,
        "smaller": .better, "fraction": .better, "no": .better, "without": .better, "free": .better,
        "similar": .similar, "same": .similar, "comparable": .similar, "equal": .similar, "unchanged": .similar,
        "equivalent": .similar,
        "more": .worse, "higher": .worse, "greater": .worse, "increase": .worse, "increases": .worse,
        "extra": .worse, "adds": .worse,
    ]

    /// Words that make a nearby comparative describe something else: "more recycled plastic", "more efficient power".
    static let qualifiers: Set<String> = ["recycled", "efficient", "durable", "reusable", "renewable", "clean",
                                          "cleaner", "local", "seasonal", "organic", "efficiently"]

    /// Words that end the reach of a direction word: "less plastic, but more water".
    static let boundaries: Set<String> = [",", "but", "while", "though", "although", "whereas", "yet", "than", "because"]

    /// Each metric a sentence names with the nearest direction word: up to four words before it ("far less land",
    /// "similar water and carbon"), else up to three after ("water use is lower").
    static func claims(in sentence: String) -> Set<Claim> {
        let tokens = tokenize(sentence)
        var found = Set<Claim>()
        for (index, token) in tokens.enumerated() {
            // "energy-efficient", "water-efficient": a quality of the item, not an amount.
            guard var metric = metricWords[token],
                  index + 1 >= tokens.count || !qualifiers.contains(tokens[index + 1]) else { continue }
            if metric == .water, index + 1 < tokens.count, tokens[index + 1] == "pollution" { metric = .waterPollution }
            if let direction = direction(near: index, in: tokens) {
                found.insert(Claim(metric: metric, direction: direction))
            }
        }
        return found
    }

    static func direction(near index: Int, in tokens: [String]) -> Claim.Direction? {
        var position = index - 1
        while position >= max(0, index - 4) {
            let token = tokens[position]
            if boundaries.contains(token) || qualifiers.contains(token) { break }
            if let direction = directionWords[token] { return direction }
            position -= 1
        }
        position = index + 1
        while position <= min(tokens.count - 1, index + 3) {
            let token = tokens[position]
            if boundaries.contains(token) || metricWords[token] != nil { break }
            if let direction = directionWords[token], token != "no", token != "without" { return direction }
            position += 1
        }
        return nil
    }

    /// Whether the comparison agrees: "similar" within 25%, "better" and "worse" in the direction the chart shows.
    static func holds(_ claim: Claim, original: Component, alternative: Alternative, engine: ImpactEngine) -> Bool {
        let candidates: [MetricKey] = claim.metric == .yearlyElectricity ? [.yearlyElectricity, .powerOn] : [claim.metric]
        guard let values = candidates.lazy.compactMap({
            GreenScore.comparison($0, original: original, alternative: alternative, engine: engine)
        }).first, values.current.value > 0 else { return true }
        let improvement = (values.current.value - values.swap.value) / values.current.value
        switch claim.direction {
        case .similar: return abs(improvement) <= 0.25
        case .better: return improvement > 0.02
        case .worse: return improvement < -0.02
        }
    }

    static func tokenize(_ sentence: String) -> [String] {
        var tokens: [String] = []
        var word = ""
        for character in sentence.lowercased() {
            if character.isLetter || character.isNumber || character == "₂" {
                word.append(character == "₂" ? "2" : character)
            } else {
                if !word.isEmpty { tokens.append(word) }
                word = ""
                if character == "," || character == ";" { tokens.append(",") }
            }
        }
        if !word.isEmpty { tokens.append(word) }
        return tokens
    }

    // MARK: - Sentences

    /// Abbreviations whose full stop does not end a sentence.
    static let abbreviations: Set<String> = ["e.g", "i.e", "eg", "ie", "vs", "etc", "approx", "incl"]

    /// The text cut into clauses at sentence ends and semicolons, keeping "e.g." and decimals whole.
    static func clauses(of text: String) -> [String] {
        var clauses: [String] = []
        var current = ""
        let characters = Array(collapsed(text))
        for (index, character) in characters.enumerated() {
            current.append(character)
            guard ".!?;".contains(character) else { continue }
            let atEnd = index + 1 >= characters.count || characters[index + 1] == " "
            guard atEnd else { continue }
            if character == ".", let last = current.dropLast().split(separator: " ").last,
               abbreviations.contains(last.lowercased()) || last.count == 1 { continue }
            clauses.append(current)
            current = ""
        }
        clauses.append(current)
        return clauses.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ;")) }.filter { !$0.isEmpty }
    }

    /// Clauses as sentences: each starts with a capital and ends with a full stop (or its own ! or ?).
    static func sentences(_ clauses: [String]) -> String {
        clauses.map { clause in
            let text = capitalizedFirst(clause.trimmingCharacters(in: CharacterSet(charactersIn: " ;,")))
            return text.last.map { ".!?".contains($0) } == true ? text : text + "."
        }.joined(separator: " ")
    }

    static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first, first.isLowercase else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
