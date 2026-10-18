import SwiftUI
import GreenCore

/// What the Leaderboard shows: everyone by overall GreenScore, or one metric's board.
enum BoardSelection: Hashable {
    case overall
    case metric(MetricKey)
}

/// The Leaderboard tab (spec §9): how you rank among friends overall (GreenScore) or on one metric, then your
/// percentile and cohort curve for that metric.
struct CompareTab: View {
    /// Read in `body` so converted numbers refresh when Settings switches units.
    @AppStorage(DisplayUnits.defaultsKey) private var unitSystem: UnitSystem = .imperial
    @Environment(AppModel.self) private var model
    @State private var selection = BoardSelection.overall
    @State private var analysis = CompareAnalysis.empty
    @State private var isLoaded = false
    private let plugs = PlugCenter.shared

    /// Yearly carbon the paired plugs' green-hours schedules avoid; it counts toward your carbon.
    private var plugSavingsKg: Double { plugs.plugs.compactMap(\.yearlySavingsKg).reduce(0, +) }

    /// Recompute whenever scans, plug schedules or the profile change.
    private var inputs: [AnyHashable] {
        [model.scans.map(\.id), model.scans.map(\.date), model.profile, plugSavingsKg]
    }

    var body: some View {
        let _ = unitSystem
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !isLoaded {
                        ProgressView().padding(.top, 40)
                    } else if analysis.cohort == nil {
                        unavailable("No baseline for your region", caption: "Uncharted territory",
                                    message: "Per-capita data isn't available for \(model.profile.region.countryCode). Update your location in Settings.")
                    } else if analysis.isEmpty {
                        unavailable("Nothing to compare yet", caption: "The garden is still growing",
                                    message: "Scan items to see how you compare with people like you.")
                    } else {
                        MetricChips(selection: $selection, analysis: analysis)
                        switch selection {
                        case .overall: overallContent(for: analysis)
                        case .metric(let metric): content(for: analysis, metric: metric)
                        }
                    }
                }
                // No implicit animation on `selection`: it animated every card, the chart and the glass chips on each
                // switch, so taps landed mid-animation and the new metric showed late.
                .padding()
            }
            .greeneryBackground(.leaderboard)
            .navigationTitle("Leaderboard")
            .settingsToolbarButton()
            .task(id: inputs) { await refresh() }
        }
    }

    private func refresh() async {
        let scans = model.scans
        let profile = model.profile
        let plugSavingsKg = plugSavingsKg
        analysis = await Task.detached(priority: .userInitiated) {
            CompareAnalysis(scans: scans, profile: profile, plugSavingsKg: plugSavingsKg)
        }.value
        isLoaded = true
    }

    @ViewBuilder
    private func overallContent(for analysis: CompareAnalysis) -> some View {
        if let user = analysis.userOverall {
            FriendsLeaderboard(overall: analysis.overall)
            OverallScoreCard(score: user.score, rank: user.rank, boardSize: analysis.overall.count,
                             plugSavingsKg: analysis.footprint.scheduledSavingsKg,
                             suggestsPlug: model.flags.plugFeaturesEnabled)
            Text("GreenScore weighs carbon, electricity, water and land equally against a typical person in your region, the same way LiveGreen ranks swaps, so a small footprint on one can't hide a big one on another. 50 is typical; higher is greener. Smart-plug schedules count toward carbon.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func content(for analysis: CompareAnalysis, metric: MetricKey) -> some View {
        if let distribution = analysis.distribution(for: metric),
           let comparison = analysis.comparisons[metric] {
            FriendsLeaderboard(metric: metric, entries: analysis.leaderboard(for: metric))
            PercentileHeroCard(metric: metric, greenerThan: comparison.greenerThan, userValue: comparison.userValue,
                               peerMedian: comparison.cohortMedian)
            CohortDistributionChart(metric: metric, distribution: distribution, userValue: comparison.userValue)
            if let source = CohortMetric.baselineSource(metric) ?? analysis.cohort?.baseline.citation.title {
                let plugs = metric == .carbon && analysis.footprint.scheduledSavingsKg > 0
                    ? ", and smart-plug schedules take off what they save" : ""
                Text("Your number is estimated from your answers (diet, getting around, home, household, clothing), and a scanned category counts when it's more than that estimate\(plugs). Baseline: \(source).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            unavailable("No \(CohortMetric.shortName(metric).lowercased()) data yet", caption: "Nothing measured here",
                        message: "None of your scanned items report this metric. Try another metric or scan more items.")
        }
    }

    private func unavailable(_ title: String, caption: String, message: String) -> some View {
        GreeneryEmptyState(art: .terrarium, title: title, caption: caption, message: message) {
            Button("Scan something", systemImage: "viewfinder") { model.selectedTab = .scan }
                .buttonStyle(.glassProminent)
        }
        .padding(.top, 24)
    }
}

/// Glass chips in one row: Overall with your GreenScore, then each leaderboard metric with its percentile; tapping
/// selects the board.
private struct MetricChips: View {
    @Binding var selection: BoardSelection
    let analysis: CompareAnalysis

    var body: some View {
        // No blending distance: at 8 pt a pressed chip's glass merged with its neighbours.
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 8) {
                chip(.overall, systemImage: "trophy", value: analysis.userOverall.map { "\($0.score.points)" } ?? "–",
                     name: "Overall", identifier: "overall", accessibilityValue: "GreenScore")
                ForEach(CohortMetric.all, id: \.self) { metric in
                    let percent = analysis.greenerThan(for: metric).map(SharePercent.format) ?? "–"
                    chip(.metric(metric), systemImage: metric.systemImage, value: percent,
                         name: CohortMetric.shortName(metric), identifier: metric.rawValue,
                         accessibilityValue: "greener than")
                }
            }
        }
    }

    private func chip(_ board: BoardSelection, systemImage: String, value: String, name: String, identifier: String,
                      accessibilityValue: String) -> some View {
        let isSelected = board == selection
        return Button { selection = board } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage).font(.subheadline)
                Text(value).font(.subheadline.weight(.bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                Text(name).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .foregroundStyle(isSelected ? .white : .primary)
            // Glass is drawn, not hit-tested: without a content shape only the icon and text took taps.
            .contentShape([.interaction, .accessibility], .rect(cornerRadius: 18))
            .glassEffect(.regular.tint(isSelected ? Theme.leaf : nil).interactive(), in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("leaderboard.metric.\(identifier)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(name), \(accessibilityValue) \(value)")
    }
}

#Preview {
    CompareTab().environment(AppModel.preview())
}
