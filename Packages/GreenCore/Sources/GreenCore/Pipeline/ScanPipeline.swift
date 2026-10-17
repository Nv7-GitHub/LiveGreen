import Foundation

/// The scan pipeline of spec §5: identify → evidence ladder (cache first, then one phase per tier) →
/// impact engine → questions (usage questions, plus detail questions for T4 items). Pure GreenCore so it runs the same in the app, demo mode and tests.
public struct ScanPipeline: Sendable {
    public var vision: any VisionIdentifier
    public var alternatives: any AlternativeSuggester
    /// Used when identify fails but the frame had a barcode (spec §11).
    public var products: any ProductDatabase
    public var ladder: EvidenceLadder
    public var engine: ImpactEngine
    public var profile: UserProfile

    /// The ladder phases and the progress step each one reports.
    static let phases: [(step: PipelineStep, tiers: ClosedRange<Tier>)] = [
        (.lookingUpRecords, .exactRecord ... .exactRecord),
        (.researchingSpecs, .researchedSpec ... .researchedSpec),
        (.computing, .factorModel ... .estimate),
    ]

    public init(vision: any VisionIdentifier, alternatives: any AlternativeSuggester, products: any ProductDatabase,
                ladder: EvidenceLadder, engine: ImpactEngine, profile: UserProfile) {
        self.vision = vision
        self.alternatives = alternatives
        self.products = products
        self.ladder = ladder
        self.engine = engine
        self.profile = profile
    }

    /// Runs one scan. `emit` receives every progress event except `.completed`, which the caller sends.
    public func run(id: UUID = UUID(), date: Date = Date(), image: Data, hints: OCRHints, mode: ScanMode,
                    emit: @escaping @Sendable (PipelineEvent) -> Void = { _ in }) async throws -> ScanResult {
        emit(.stepStarted(.readingLabels))
        // The capture views run the on-device Vision pre-pass and hand over `hints`.
        emit(.stepFinished(.readingLabels))

        emit(.stepStarted(.identifying))
        let (response, records) = try await identify(image: image, hints: hints, emit: emit)
        // A barcode scan has no frame; the record's front-of-pack photo stands in for one.
        async let productPhoto: Data? = image.isEmpty ? productPhoto(records) : nil
        let identified = prepared(response.components, hints: hints)
        // Component ids derive from the scan id, so a scan's seeded Monte Carlo ranges are reproducible.
        var components = identified.enumerated().map { $1.makeComponent(id: Self.componentID(scan: id, index: $0)) }
        let deferrable = Dictionary(uniqueKeysWithValues: zip(components.map(\.id), identified.map(\.deferrableLoad)))
        emit(.componentsIdentified(components))
        emit(.stepFinished(.identifying))

        // A cache hit skips the ladder, so the same identifier always gives the same numbers.
        var cachedIDs = Set<UUID>()
        for index in components.indices {
            if let hit = await ladder.cached(components[index]) {
                components[index] = hit
                cachedIDs.insert(hit.id)
            }
        }
        for phase in Self.phases {
            emit(.stepStarted(phase.step))
            components = await resolveAll(components, tiers: phase.tiers, skipping: cachedIDs, emit: emit)
            emit(.stepFinished(phase.step))
        }
        for component in components where !cachedIDs.contains(component.id) { await ladder.remember(component) }

        components = components.map { completed($0, deferrable: deferrable[$0.id] ?? nil) }
        let pending = QuestionGate.pendingQuestions(for: components)
        if !pending.isEmpty { emit(.questionsNeeded(pending)) }
        // Items still on a T4 estimate get a few plain detail questions before the results (`refining`).
        let details = await specQuestions(for: components)
        if !details.isEmpty { emit(.specQuestionsNeeded(details)) }

        var result = ScanResult(id: id, date: date, title: response.sceneTitle ?? components.first?.name ?? "Scan",
                                mode: mode, photo: image.isEmpty ? await productPhoto : image, components: components)
        result.updateTotals(engine: engine)
        return result
    }

    /// Asks for greener alternatives and resolves them through the same ladder and engine as the
    /// originals (spec §7), then keeps only swaps without a big trade-off on any metric, best GreenScore
    /// first; deferrable loads also get the local smart-plug alternative.
    public func suggestAlternatives(for result: ScanResult) async throws -> ScanResult {
        let suggestions = try await alternatives.suggestAlternatives(for: result.components, profile: profile)
        var updated = result
        for suggestion in suggestions {
            guard let index = updated.components.firstIndex(where: { $0.id == suggestion.componentID }) else { continue }
            var resolved: [Alternative] = []
            for alternative in suggestion.alternatives where alternative.kind == .product {
                resolved.append(await resolve(alternative))
            }
            updated.components[index].alternatives = GreenScore.ranked(resolved, replacing: updated.components[index],
                                                                        engine: engine)
        }
        for index in updated.components.indices where updated.components[index].plugCandidate != nil {
            let component = updated.components[index]
            if !component.alternatives.contains(where: { $0.kind == .smartPlugScheduling }) {
                updated.components[index].alternatives.append(.smartPlugScheduling(for: component))
            }
        }
        return updated
    }

    /// Re-runs the engine after question answers (spec §5.5), locally with no network call.
    public func applying(_ answers: [(componentID: UUID, option: AnswerOption)], to result: ScanResult) -> ScanResult {
        var updated = result
        for answer in answers {
            guard let index = updated.components.firstIndex(where: { $0.id == answer.componentID }) else { continue }
            var component = engine.applyingAnswer(answer.option, to: updated.components[index], profile: profile)
            if var candidate = component.plugCandidate, let kWh = component.metrics[.yearlyElectricity] {
                candidate.dailyKWh = kWh.value / ImpactEngine.daysPerYear
                candidate.estimatedSavings = plugSavings(for: candidate)
                component.plugCandidate = candidate
            }
            updated.components[index] = component
        }
        updated.updateTotals(engine: engine)
        return updated
    }

    // MARK: - Steps

    /// Below this an inferred load saves too little to recommend a plug (e.g. a charger's idle draw).
    static let minimumPlugKWhPerYear = 15.0

    static func componentID(scan: UUID, index: Int) -> UUID {
        var raw = scan.uuid
        raw.8 ^= 0x80
        raw.15 ^= UInt8(truncatingIfNeeded: index + 1)
        raw.14 ^= UInt8(truncatingIfNeeded: (index + 1) >> 8)
        return UUID(uuid: raw)
    }

    /// Identify with one retry (spec §11). If both attempts fail and the frame had barcodes, the items are
    /// built from their Open Food Facts records instead. Also returns the records found for the barcodes.
    func identify(image: Data, hints: OCRHints, emit: @escaping @Sendable (PipelineEvent) -> Void)
        async throws -> (IdentifyResponse, [ProductRecord]) {
        var hints = hints
        var records: [ProductRecord] = []
        if image.isEmpty, !hints.gtins.isEmpty {
            records = (try? await barcodeRecords(hints.gtins)) ?? []
            // A barcode scan without a frame goes straight to the product records when they carry footprint
            // data. Name-only records still go through identify, which knows what the item is made of.
            if !records.isEmpty, records.allSatisfy(\.hasFootprintData) {
                return (Self.response(from: records), records)
            }
            hints.textLines = records.map(Self.hintLine) + hints.textLines
        }
        do {
            return (try await identifyWithRetry(image: image, hints: hints) { emit(.identifyProgress($0)) }, records)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if records.isEmpty, !hints.gtins.isEmpty { records = (try? await barcodeRecords(hints.gtins)) ?? [] }
            guard !records.isEmpty else { throw error }
            emit(.warning("Identification failed; using barcode records only."))
            return (Self.response(from: records), records)
        }
    }

    /// Product-database facts for the identify prompt when there is no photo.
    static func hintLine(_ record: ProductRecord) -> String {
        "Product database record for \(record.gtin): \(record.name)" + (record.brand.map { " by \($0)" } ?? "")
    }

    static func response(from records: [ProductRecord]) -> IdentifyResponse {
        IdentifyResponse(components: records.map(component(from:)),
                         sceneTitle: records.count == 1 ? records[0].name : "Scanned products")
    }

    static func component(from record: ProductRecord) -> IdentifiedComponent {
        IdentifiedComponent(
            name: record.name, category: record.category, boundingBox: .full,
            identifiers: Identifiers(gtin: record.gtin, brand: record.brand),
            quantities: Quantities(massKg: record.netMassKg, servingKg: record.servingKg, foodGroup: record.foodGroup))
    }

    private func productPhoto(_ records: [ProductRecord]) async -> Data? {
        for record in records where record.imageURL != nil {
            if let data = await products.productImage(for: record) { return data }
        }
        return nil
    }

    private func identifyWithRetry(image: Data, hints: OCRHints,
                                   progress: @escaping @Sendable (IdentifyProgress) -> Void) async throws -> IdentifyResponse {
        do {
            return try await vision.identify(image: image, hints: hints, profile: profile, progress: progress)
        } catch is CancellationError {
            throw CancellationError()
        } catch GreenCoreError.missingAPIKey(let key) {
            throw GreenCoreError.missingAPIKey(key)
        } catch {
            return try await vision.identify(image: image, hints: hints, profile: profile, progress: progress)
        }
    }

    private func barcodeRecords(_ gtins: [String]) async throws -> [ProductRecord] {
        var records: [ProductRecord] = []
        for gtin in gtins {
            if let record = try await products.product(gtin: gtin) { records.append(record) }
        }
        return records
    }

    private func resolveAll(_ components: [Component], tiers: ClosedRange<Tier>, skipping: Set<UUID>,
                            emit: @escaping @Sendable (PipelineEvent) -> Void) async -> [Component] {
        let ladder = ladder
        let profile = profile
        return await withTaskGroup(of: (Int, Component).self) { group in
            for (index, component) in components.enumerated() where !skipping.contains(component.id) {
                group.addTask {
                    let resolved = await ladder.resolve(component, profile: profile, tiers: tiers) { progress in
                        switch progress {
                        case let .resolved(metric, tier):
                            emit(.metricResolved(componentID: component.id, metric: metric, tier: tier))
                        case let .resolverFailed(name, error):
                            // Errors downgrade to the next tier; only unexpected ones are worth a note.
                            if let message = Self.warning(resolver: name, component: component.name, error: error) {
                                emit(.warning(message))
                            }
                        }
                    }
                    return (index, resolved)
                }
            }
            var output = components
            for await (index, resolved) in group { output[index] = resolved }
            return output
        }
    }

    static func warning(resolver: String, component: String, error: any Error) -> String? {
        switch error {
        case GreenCoreError.missingAPIKey, GreenCoreError.notFound, is CancellationError: nil
        case GreenCoreError.timeout: "\(resolver) timed out for \(component)."
        default: "\(resolver) unavailable for \(component)."
        }
    }

    // MARK: - Engine

    /// Derived values the ladder does not produce: yearly electricity from power × hours, the use phase of
    /// researched or estimated electronics carbon, and the smart-plug candidate for deferrable loads.
    func completed(_ component: Component, deferrable: DeferrableLoadType?) -> Component {
        var result = component
        if result.metrics[.yearlyElectricity] == nil, result.category.applicableMetrics.contains(.yearlyElectricity),
           let kWh = engine.derivedYearlyElectricity(for: result) {
            result.metrics[.yearlyElectricity] = kWh
        }
        result = addingUsePhase(to: result)
        if result.plugCandidate == nil, let candidate = plugCandidate(for: result, deferrable: deferrable) {
            result.plugCandidate = candidate
        }
        return result
    }

    private func plugCandidate(for component: Component, deferrable: DeferrableLoadType?) -> PlugCandidate? {
        let device = engine.store?.deviceProfile(deviceType: component.quantities.deviceType ?? component.name)
        // An explicit deferrable load from identify (a power bank, a phone charger) always qualifies; loads
        // inferred from device defaults must use enough electricity for scheduling to matter.
        guard let load = deferrable ?? device?.deferrableLoad, let kWh = component.metrics[.yearlyElectricity]?.value,
              kWh > 0, deferrable != nil || kWh >= Self.minimumPlugKWhPerYear else { return nil }
        let watts = component.quantities.ratedPowerW ?? device?.chargerWatts ?? component.metrics[.powerOn]?.value ?? 100
        var candidate = PlugCandidate(loadType: load, chargerWatts: watts, dailyKWh: kWh / ImpactEngine.daysPerYear)
        candidate.estimatedSavings = plugSavings(for: candidate)
        return candidate
    }

    /// Scan-time estimate from the bundled regional 24-h shape, so it is deterministic and offline; the Plugs
    /// tab refines it with live grid history.
    func plugSavings(for candidate: PlugCandidate) -> Measured? {
        guard let record = engine.gridIntensity(for: profile) else { return nil }
        return GreenHoursPlanner.estimatedSavings(for: candidate, forecast: .fallback(record))
    }

    /// Records and cited research first, as for originals. An alternative without its own identifiers would get
    /// the same generic factor-model numbers as the item it replaces (a refurbished laptop is still a "laptop"),
    /// so the suggester's bounded per-metric estimates come next and the factor model fills what is left.
    private func resolveAlternative(_ component: Component) async -> Component {
        if let hit = await ladder.cached(component) { return hit }
        var result = await ladder.resolve(component, profile: profile, tiers: .exactRecord ... .researchedSpec)
        if component.identifiers.cacheKey == nil {
            result = await ladder.resolve(result, profile: profile, tiers: .estimate ... .estimate)
        }
        result = await ladder.resolve(result, profile: profile, tiers: .factorModel ... .estimate)
        await ladder.remember(result)
        return result
    }

    private func resolve(_ alternative: Alternative) async -> Alternative {
        let asComponent = Component(id: alternative.id, name: alternative.name, category: alternative.category,
                                    identifiers: alternative.identifiers, quantities: alternative.quantities,
                                    usage: alternative.usage, fallbackEstimates: alternative.fallbackEstimates)
        let resolved = completed(await resolveAlternative(asComponent), deferrable: nil)
        var filled = alternative
        filled.metrics = resolved.metrics
        return filled
    }
}

extension Alternative {
    public static let smartPlugName = "Shelly smart plug + green-hours scheduling"

    /// The locally added plug alternative (spec §7): the same device, so every metric matches; its saving
    /// comes from the component's plug candidate because scheduling changes when it charges, not what it is.
    /// The id is derived from the component id so a re-run keeps the user's pick.
    public static func smartPlugScheduling(for component: Component) -> Alternative {
        let load = component.plugCandidate?.loadType.displayName.lowercased() ?? "charger"
        var raw = component.id.uuid
        raw.14 ^= 0x5A
        raw.15 ^= 0xA5
        return Alternative(id: UUID(uuid: raw), kind: .smartPlugScheduling, name: smartPlugName,
                           category: component.category, identifiers: component.identifiers,
                           quantities: component.quantities, usage: component.usage,
                           rationale: "Keep your \(load), but let a plug switch it on only during the cleanest grid hours.",
                           practicality: Practicality(cost: .lower, effort: .easy), metrics: component.metrics)
    }
}
