import SwiftUI
import GreenCore

/// Peer comparison and percentiles (spec §9): hero percentile, cohort curve, trend and simulated leaderboard.
struct CompareTab: View {
    @Environment(AppModel.self) private var model
    @State private var metric: MetricKey = .carbon

    var body: some View {
        let analysis = CompareAnalysis(scans: model.scans, profile: model.profile, reference: model.services.reference)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if analysis.cohort.baseline == nil {
                        unavailable("No baseline for your region",
                                    message: "Per-capita data isn't available for \(model.profile.region.countryCode). Update your location in Settings.",
                                    systemImage: "globe")
                    } else if analysis.footprint.itemCount == 0 {
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
        }
    }

    @ViewBuilder
    private func content(for analysis: CompareAnalysis) -> some View {
        if let distribution = analysis.cohort.distribution(for: metric),
           let value = analysis.userValue(for: metric),
           let greener = analysis.greenerThan(for: metric) {
            PercentileHeroCard(metric: metric, greenerThan: greener, userValue: value, peerMedian: distribution.median)
            CohortDistributionChart(metric: metric, distribution: distribution, userValue: value)
            PercentileTrendCard(points: analysis.trend[metric] ?? [])
            FriendsLeaderboard(metric: metric, friends: analysis.cohort.friends(), userValue: value, cohort: analysis.cohort)
            if let citation = analysis.cohort.baseline?.citation {
                Text("Baseline: \(citation.title). Compared only for the categories you've scanned, adjusted for your diet and household size.")
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
