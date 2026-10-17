import SwiftUI
import GreenCore

/// Peer comparison and percentiles (spec §9): hero percentile, cohort curve, trend and simulated leaderboard.
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
                .padding()
                .animation(.smooth, value: metric)
            }
            .navigationTitle("Compare")
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
            PercentileHeroCard(metric: metric, greenerThan: comparison.greenerThan, userValue: comparison.userValue,
                               peerMedian: comparison.cohortMedian)
            CohortDistributionChart(metric: metric, distribution: distribution, userValue: comparison.userValue)
            PercentileTrendCard(points: analysis.trend[metric] ?? [])
            FriendsLeaderboard(metric: metric, entries: analysis.leaderboard(for: metric),
                               avatarSymbols: analysis.avatarSymbols(for: metric))
            if let citation = analysis.cohort?.baseline.citation {
                Text("Baseline: \(citation.title). Compared only for the categories you've scanned, adjusted for your diet, clothing habits and household size.")
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

/// Glass chips for the four cohort metrics, each showing its percentile; tapping selects the metric.
private struct MetricChips: View {
    @Binding var selection: MetricKey
    let analysis: CompareAnalysis

    var body: some View {
        GlassEffectContainer(spacing: 8) {
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
                Text(percent).font(.subheadline.weight(.bold).monospacedDigit())
                Text(CohortMetric.shortName(metric)).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? .white : .primary)
            .glassEffect(.regular.tint(isSelected ? Theme.leaf : nil).interactive(), in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(CohortMetric.shortName(metric)), greener than \(percent)")
    }
}

#Preview {
    CompareTab().environment(AppModel.preview())
}
