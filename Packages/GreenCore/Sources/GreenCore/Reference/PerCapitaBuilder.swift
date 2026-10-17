import Foundation

/// Turns `per_capita.json` means into lognormal-median baselines (median = mean·exp(−σ²/2)).
struct PerCapitaBuilder {
    var countries: [String: PerCapitaBaseline] = [:]
    /// US state carbon multipliers (state ÷ US, clamped), from production-based EIA figures.
    var stateRatios: [String: Double] = [:]
    var cohort: CohortReference
    var info: [ReferenceRecordInfo] = []

    init(file: PerCapitaFile) throws {
        guard let sigmaValues = file.sigmas.resolved, let shareValues = file.categoryShares.resolved else {
            throw GreenCoreError.decoding("per_capita.json: missing sigmas or category shares")
        }
        let sigmas = Self.keyed(sigmaValues, MetricKey.init(rawValue:))
        let diet = Self.keyed(file.dietModifiers.resolved ?? [:], Diet.init(rawValue:))
        let exponent = file.householdSizeExponent.resolved ?? 1

        for country in file.countries {
            let means: [MetricKey: Double] = [
                .carbon: country.meanCarbonKg, .water: country.meanWaterL,
                .land: country.meanLandM2Year, .yearlyElectricity: country.meanElectricityKWh,
            ]
            let medians = means.reduce(into: [MetricKey: Double]()) { result, entry in
                let sigma = sigmas[entry.key] ?? 0
                result[entry.key] = entry.value * exp(-sigma * sigma / 2)
            }
            countries[country.region.uppercased()] = PerCapitaBaseline(
                region: country.region, medians: medians, sigmas: sigmas, dietModifiers: diet,
                householdSizeExponent: exponent, citation: country.citation)
            info.append(ReferenceRecordInfo(table: "per_capita", key: country.region, verified: country.verified,
                                            citation: country.citation))
        }

        let states = file.usStates
        for (state, tonnes) in states.tonnesPerCapita {
            stateRatios[state.uppercased()] = min(max(tonnes / states.usAverageTonnes, states.stateRatioMin), states.stateRatioMax)
        }
        info.append(ReferenceRecordInfo(table: "per_capita", key: "usStates", verified: states.verified, citation: states.citation))

        var shares: [MetricKey: [Category: Double]] = [:]
        for (metric, byCategory) in shareValues {
            guard let key = MetricKey(rawValue: metric) else { continue }
            shares[key] = Self.keyed(byCategory, Category.init(rawValue:))
        }
        cohort = CohortReference(
            categoryShares: shares,
            clothingModifiers: Self.keyed(file.clothingModifiers.resolved ?? [:], ClothingHabit.init(rawValue:)),
            commuteModifiers: Self.keyed(file.commuteModifiers.resolved ?? [:], CommuteMode.init(rawValue:)),
            homeTypeModifiers: Self.keyed(file.homeTypeModifiers.resolved ?? [:], HomeType.init(rawValue:)),
            heatingModifiers: Self.keyed(file.heatingModifiers.resolved ?? [:], HeatingSource.init(rawValue:)),
            citations: [file.categoryShares.citation, file.dietModifiers.citation, file.clothingModifiers.citation,
                        file.commuteModifiers.citation, file.householdSizeExponent.citation,
                        file.homeTypeModifiers.citation, file.heatingModifiers.citation, file.sigmas.citation])

        let cited: [(String, Bool, Source)] = [
            ("sigmas", file.sigmas.verified, file.sigmas.citation),
            ("dietModifiers", file.dietModifiers.verified, file.dietModifiers.citation),
            ("clothingModifiers", file.clothingModifiers.verified, file.clothingModifiers.citation),
            ("commuteModifiers", file.commuteModifiers.verified, file.commuteModifiers.citation),
            ("householdSizeExponent", file.householdSizeExponent.verified, file.householdSizeExponent.citation),
            ("homeTypeModifiers", file.homeTypeModifiers.verified, file.homeTypeModifiers.citation),
            ("heatingModifiers", file.heatingModifiers.verified, file.heatingModifiers.citation),
            ("categoryShares", file.categoryShares.verified, file.categoryShares.citation),
        ]
        info += cited.map { ReferenceRecordInfo(table: "per_capita", key: $0.0, verified: $0.1, citation: $0.2) }
    }

    private static func keyed<K: Hashable>(_ values: [String: Double], _ make: (String) -> K?) -> [K: Double] {
        values.reduce(into: [K: Double]()) { result, entry in
            if let key = make(entry.key) { result[key] = entry.value }
        }
    }
}
