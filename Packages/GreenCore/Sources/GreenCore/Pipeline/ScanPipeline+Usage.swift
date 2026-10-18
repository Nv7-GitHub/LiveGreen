import Foundation

/// How often consumables are had (spec §5.6): typical weeks in place of identify's guesses, containers linked to the
/// food they held, and usage answers that reach the items they are about.
extension ScanPipeline {
    // MARK: Containers

    /// Links each packaging item to the food it held (`Component.parentID`): a food its box mostly lies on
    /// (`containerOverlap` of the smaller box, as `countingContainersOnce` judges a duplicate cup), the one it overlaps
    /// most when several do, the smaller food on a tie. Identify counts a food's own cup as part of the food and a
    /// duplicate is dropped before this, so what is left is packaging the food did not count (a straw beside a drink
    /// that named none, a box under a burger). It is still thrown away once per serving.
    static func linkingContainers(_ components: [Component]) -> [Component] {
        let foods = components.filter { $0.category == .food }
        guard !foods.isEmpty else { return components }
        return components.map { component in
            guard component.category == .packaging else { return component }
            var best: (food: Component, overlap: Double)?
            for food in foods {
                let overlap = overlap(component.boundingBox, food.boundingBox)
                guard overlap >= containerOverlap else { continue }
                if let current = best, overlap < current.overlap
                    || (overlap == current.overlap && food.boundingBox.area >= current.food.boundingBox.area) { continue }
                best = (food, overlap)
            }
            var linked = component
            linked.parentID = best?.food.id
            return linked
        }
    }

    // MARK: Typical weeks

    /// Gives every consumable its rate a week in place of identify's guess, which changed from run to run: the user's
    /// answer for its kind from an earlier scan (`rememberedUsage`), else the typical week for its food group or kind
    /// (`UsageDefaults`). Packaging linked to a food is used as often as the food is eaten (`followingFoods`). With
    /// `keepingAnswers`, rates the user gave on this scan stay, and only typical or remembered ones are worked out again
    /// (after a detail answer changed what an item is).
    func withDefaultUsage(_ components: [Component], keepingAnswers: Bool = false) -> [Component] {
        let reference = engine.reference
        let rated = components.map { component -> Component in
            if component.category == .packaging, component.parentID != nil { return component }
            if keepingAnswers, component.usage?.source != .typical, component.usage?.source != .remembered { return component }
            guard let typical = UsageDefaults.typicalPerWeek(for: component, reference: reference) else { return component }
            let remembered = UsageDefaults.kindKey(for: component, reference: reference).flatMap { rememberedUsage[$0] }
            return UsageDefaults.setting(remembered ?? typical, source: remembered == nil ? .typical : .remembered, on: component)
        }
        return followingFoods(rated)
    }

    /// Packaging linked to a food takes the food's rate: one container per serving, or per pack for a per-pack food,
    /// with the food's source.
    func followingFoods(_ components: [Component]) -> [Component] {
        let foods = Dictionary(components.filter { $0.category == .food }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return components.map { component in
            guard component.category == .packaging, let id = component.parentID, let food = foods[id],
                  case .unitsPerYear(let units) = engine.annualBasis(for: food) else { return component }
            return UsageDefaults.setting(units / ImpactEngine.weeksPerYear, source: food.usage?.source ?? .typical, on: component)
        }
    }

    /// Adds LiveGreen's frequency question to consumables still on a typical week that identify asked nothing about
    /// how often, so the assumption behind their year can be answered from the results (`QuestionGate` shows it for
    /// the top two by yearly carbon). Containers linked to a food are answered through the food.
    static func askingFrequency(_ components: [Component]) -> [Component] {
        components.map { component in
            guard component.usage?.source == .typical, component.parentID == nil else { return component }
            let field: UsageField
            let question: String
            switch component.category {
            case .food: (field, question) = (.servingsPerWeek, "How often do you have this?")
            case .packaging: (field, question) = (.usesPerWeek, "How often do you use one?")
            case .personalCare, .household where component.quantities.consumable == true:
                (field, question) = (.usesPerWeek, "How often do you use it?")
            case .electronic, .clothing, .household, .vehicle: return component
            }
            let asksRate = component.questions.contains { $0.options.contains { $0.field.map(QuestionGate.rateFields.contains) == true } }
            guard !asksRate else { return component }
            let rates: [(String, Double)] = [("Twice a month", 0.5), ("Weekly", 1), ("3 times a week", 3), ("Daily", 7)]
            var updated = component
            updated.questions.append(ComponentQuestion(
                id: QuestionGate.frequencyQuestionID, question: question,
                whyItMatters: "Its yearly numbers use a typical week until you say. Your answer also covers items like it, here and on later scans.",
                affectedMetrics: ImpactEngine.annualMetrics.filter { component.metrics[$0] != nil },
                options: rates.map { AnswerOption(label: $0.0, field: field, value: $0.1) }))
            return updated
        }
    }

    // MARK: Answers

    /// Re-runs the engine after question answers or usage edits (spec §5.5), locally with no network call. Each answer
    /// reaches the items it is about (`reach`): a container's food, and the scan's other items of the same kind; linked
    /// containers then follow their foods. Answered rates are marked as the user's.
    public func applying(_ answers: [(componentID: UUID, option: AnswerOption)], to result: ScanResult) -> ScanResult {
        var updated = result
        for answer in answers {
            for target in Self.reach(of: answer.option, on: answer.componentID, in: updated.components, reference: engine.reference) {
                guard let index = updated.components.firstIndex(where: { $0.id == target.id }) else { continue }
                updated.components[index] = answering(target.option, on: updated.components[index])
            }
        }
        updated.components = followingFoods(updated.components)
        updated.updateTotals(engine: engine)
        return updated
    }

    private func answering(_ option: AnswerOption, on component: Component) -> Component {
        var updated = engine.applyingAnswer(option, to: component, profile: profile)
        if option.field != nil, option.value != nil { updated.usage?.source = .answered }
        if var candidate = updated.plugCandidate, let kWh = updated.metrics[.yearlyElectricity] {
            candidate.dailyKWh = kWh.value / ImpactEngine.daysPerYear
            candidate.estimatedSavings = plugSavings(for: candidate)
            updated.plugCandidate = candidate
        }
        return updated
    }

    /// The answers one usage answer stands for. A container's uses are its food's servings (one cup per drink), so an
    /// answer for a linked cup is an answer for its drink. A food's or unlinked container's rate also goes to the
    /// scan's other items of its kind (`UsageDefaults.kindKey`): questions ask about "drinks like these", and later
    /// scans read them alike anyway. Hours, charges and other fields reach only their own item.
    static func reach(of option: AnswerOption, on id: UUID, in components: [Component],
                      reference: any ReferenceProviding) -> [(id: UUID, option: AnswerOption)] {
        guard let field = option.field, let value = option.value, var root = components.first(where: { $0.id == id })
        else { return [(id, option)] }
        var rootOption = option
        if root.category == .packaging, field == .usesPerWeek, let parentID = root.parentID,
           let food = components.first(where: { $0.id == parentID && $0.category == .food }) {
            root = food
            rootOption = AnswerOption(label: option.label, field: FoodServing.isPerPack(food) ? .packsPerWeek : .servingsPerWeek,
                                      value: value)
        }
        var reached = [(id: root.id, option: rootOption)]
        let shared: AnswerOption
        switch (root.category, rootOption.field) {
        case (.food, .servingsPerWeek?), (.packaging, .usesPerWeek?), (.personalCare, .usesPerWeek?):
            shared = rootOption
        case (.food, .packsPerWeek?):
            // Same-kind foods may be per serving; each converts back to its own packs (`applyingAnswer`).
            shared = AnswerOption(label: option.label, field: .servingsPerWeek, value: value * FoodServing.servingsPerPack(root))
        default:
            return reached
        }
        guard let key = UsageDefaults.kindKey(for: root, reference: reference) else { return reached }
        for other in components where other.id != root.id && other.category == root.category
            && UsageDefaults.kindKey(for: other, reference: reference) == key {
            reached.append((other.id, shared))
        }
        return reached
    }

    /// The other items a usage change on `component` also changes (`reach` and the containers that follow those
    /// foods), so the detail sheet can say so before the user moves a slider.
    public static func usageLinkedItems(of component: Component, in components: [Component],
                                        reference: any ReferenceProviding) -> [Component] {
        let field: UsageField
        switch component.category {
        case .food: field = .servingsPerWeek
        case .packaging, .personalCare, .household where component.quantities.consumable == true: field = .usesPerWeek
        case .electronic, .clothing, .household, .vehicle: return []
        }
        let probe = AnswerOption(label: "", field: field, value: 1)
        let reached = Set(reach(of: probe, on: component.id, in: components, reference: reference).map(\.id))
        return components.filter { other in
            other.id != component.id && (reached.contains(other.id) || other.parentID.map(reached.contains) == true)
        }
    }
}
