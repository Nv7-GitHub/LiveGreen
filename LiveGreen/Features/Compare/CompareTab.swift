import SwiftUI
import GreenCore

/// The Leaderboard tab (spec §9): how you rank among friends, then your percentile and cohort curve.
struct CompareTab: View {
    /// Read in `body` so converted numbers refresh when Settings switches units.
    @AppStorage(DisplayUnits.defaultsKey) private var unitSystem: UnitSystem = .imperial
    @Environment(AppModel.self) private var model
    @State private var metric: MetricKey = .carbon
    @State private var analysis = CompareAnalysis.empty
    @State private var isLoaded = false

    /// Recompute whenever scans or the profile change.
    private var inputs: [AnyHashable] { [model.scans.map(\.id), model.scans.map(\.date), model.profile] }

    var body: some View {
        let _ = unitSystem
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !isLoaded {
                        ProgressView().padding(.top, 40)
                    } else if analysis.cohort == nil {
                        unavailable("No baseline for your region",
                                    message: "Per-capita data isn't available for \(model.profile.region.countryCode). Update your location in Settings.",
                                    systemImage: "globe")
                    } else if analysis.isEmpty {
                        unavailable("Nothing to compare yet",
                                    message: "Scan items to see how you compare with people like you.",
                                    systemImage: "chart.bar.xaxis")
                    } else {
                        MetricChips(selection: $metric, analysis: analysis)
                        content(for: analysis)
                    }
                }
                // No implicit animation on `metric`: it animated every card, the chart and the glass chips on each
                // switch, so taps landed mid-animation and the new metric showed late.
                .padding()
            }
            .navigationTitle("Leaderboard")
            .settingsToolbarButton()
            .task(id: inputs) { await refresh() }
        }
    }

    private func refresh() async {
        let scans = model.scans
        let profile = model.profile
        analysis = await Task.detached(priority: .userInitiated) {
            CompareAnalysis(scans: scans, profile: profile)
        }.value
        isLoaded = true
    }

    @ViewBuilder
    private func content(for analysis: CompareAnalysis) -> some View {
        if let distribution = analysis.distribution(for: metric),
           let comparison = analysis.comparisons[metric] {
            FriendsLeaderboard(metric: metric, entries: analysis.leaderboard(for: metric))
            PercentileHeroCard(metric: metric, greenerThan: comparison.greenerThan, userValue: comparison.userValue,
                               peerMedian: comparison.cohortMedian)
            CohortDistributionChart(metric: metric, distribution: distribution, userValue: comparison.userValue)
            if let source = CohortMetric.baselineSource(metric) ?? analysis.cohort?.baseline.citation.title {
                Text("Your number is estimated from your answers (diet, getting around, home, household, clothing), and a scanned category counts when it's more than that estimate. Baseline: \(source).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            unavailable("No \(CohortMetric.shortName(metric).lowercased()) data yet",
                        message: "None of your scanned items report this metric. Try another metric or scan more items.",
                        systemImage: metric.systemImage)
        }
    }

    private func unavailable(_ title: String, message: String, systemImage: String) -> some View {
        GlassCard {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
            } actions: {
                Button("Scan something", systemImage: "viewfinder") { model.selectedTab = .scan }
                    .buttonStyle(.glassProminent)
            }
        }
    }
}

/// Glass chips for the leaderboard metrics in one row, each showing its percentile; tapping selects the metric.
private struct MetricChips: View {
    @Binding var selection: MetricKey
    let analysis: CompareAnalysis

    var body: some View {
        // No blending distance: at 8 pt a pressed chip's glass merged with its neighbours.
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(CohortMetric.all, id: \.self) { metric in
                    chip(for: metric)
                }
            }
        }
    }

    private func chip(for metric: MetricKey) -> some View {
        let isSelected = metric == selection
        let percent = analysis.greenerThan(for: metric).map(SharePercent.format) ?? "–"
        return Button { selection = metric } label: {
            VStack(spacing: 2) {
                Image(systemName: metric.systemImage).font(.subheadline)
                Text(percent).font(.subheadline.weight(.bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                Text(CohortMetric.shortName(metric)).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
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
        .accessibilityIdentifier("leaderboard.metric.\(metric.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(CohortMetric.shortName(metric)), greener than \(percent)")
    }
}

#Preview {
    CompareTab().environment(AppModel.preview())
}
