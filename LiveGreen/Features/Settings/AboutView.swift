import SwiftUI
import GreenCore

/// Data sources, evidence tiers and the simulated-network disclosure (spec §5.4, §9).
struct AboutView: View {
    private struct DataSource: Identifiable {
        let name: String
        let detail: String
        let url: String
        var id: String { name }
    }

    private let sources: [DataSource] = [
        DataSource(name: "Open Food Facts", detail: "Product records, Agribalyse CO₂e and packaging by barcode",
                   url: "https://world.openfoodfacts.org"),
        DataSource(name: "ENERGY STAR", detail: "Certified on-mode, standby and annual energy by model",
                   url: "https://data.energystar.gov"),
        DataSource(name: "ASUS Product Carbon Footprints", detail: "Published lifecycle CO₂e for ASUS devices",
                   url: "https://esg.asus.com"),
        DataSource(name: "Poore & Nemecek (2018)", detail: "Food carbon, water, land and eutrophication factors",
                   url: "https://ourworldindata.org/environmental-impacts-of-food"),
        DataSource(name: "EPA eGRID", detail: "US grid carbon intensity by subregion",
                   url: "https://www.epa.gov/egrid"),
        DataSource(name: "Electricity Maps", detail: "Live and historical grid carbon intensity",
                   url: "https://www.electricitymaps.com"),
        DataSource(name: "Our World in Data", detail: "Per-capita baselines for the peer cohort",
                   url: "https://ourworldindata.org"),
        DataSource(name: "Claude by Anthropic", detail: "Item identification, cited spec research and swap ideas",
                   url: "https://www.anthropic.com"),
        DataSource(name: "xAI Grok Imagine", detail: "Greener-setup image edits",
                   url: "https://x.ai"),
    ]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("LiveGreen", systemImage: "leaf.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.leaf)
                    Text("Point your phone at a thing, see what it costs the planet, and find a greener swap.")
                        .foregroundStyle(.secondary)
                    Text("Version \(Bundle.main.versionString) · HackHarvard 2026")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Simulated network").font(.headline)
                        Text("The friends on the Compare leaderboard are a simulated network: eight people sampled with a fixed seed from your modeled peer cohort. They are not real accounts.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "person.3.sequence").foregroundStyle(Theme.warning)
                }
            }

            Section("How sure is each number?") {
                ForEach(Tier.allCases, id: \.self) { tier in
                    HStack(spacing: 12) {
                        TierBadge(tier: tier)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tier.displayName).font(.subheadline.weight(.medium))
                            Text(Self.explanation(for: tier)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Data sources") {
                ForEach(sources) { source in
                    if let url = URL(string: source.url) {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                Text(source.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func explanation(for tier: Tier) -> String {
        switch tier {
        case .exactRecord: "Matched to a database record by barcode or model number."
        case .researchedSpec: "Read from a cited spec sheet or report found on the web."
        case .factorModel: "Computed from reference factors and the item's size or materials."
        case .estimate: "A bounded estimate with a deliberately wide range."
        }
    }
}

private extension Bundle {
    var versionString: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    NavigationStack { AboutView() }
}
