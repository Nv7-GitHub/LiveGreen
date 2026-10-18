import SwiftUI
import GreenCore

/// A rounded, softly tinted stage for a question's illustration. The art only mirrors the answer, so it is
/// hidden from VoiceOver.
struct ArtPanel<Content: View>: View {
    var tint: Color
    var height: CGFloat = 120
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(LinearGradient(colors: [tint.opacity(0.30), tint.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                        in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.25)))
            .clipShape(.rect(cornerRadius: 18))
            .accessibilityHidden(true)
    }
}

/// One figure per person in the household, bouncing in as people are added.
struct HouseholdArt: View {
    let size: Int

    private static let palette: [Color] = [Theme.leaf, .teal, .orange, .purple, .pink, .blue, .mint, .indigo]

    var body: some View {
        let crowded = size > 6
        ArtPanel(tint: .teal, height: 84) {
            HStack(spacing: crowded ? -4 : 4) {
                ForEach(0..<size, id: \.self) { index in
                    Image(systemName: "person.fill")
                        .font(.system(size: crowded ? 26 : 34))
                        .foregroundStyle(Self.palette[index % Self.palette.count].gradient)
                        .transition(.scale(scale: 0.2, anchor: .bottom).combined(with: .opacity))
                }
            }
            .symbolEffect(.bounce, value: size)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: size)
    }
}

/// A week of plates (days across, breakfast to dinner down): meat meals land on dinners first and dairy on
/// breakfasts, each spread evenly through the week, so the plates fill as the counts change.
struct WeekOfMealsArt: View {
    let meatMeals: Int
    let dairyMeals: Int

    private static let days = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        ArtPanel(tint: .orange, height: 146) {
            Grid(horizontalSpacing: 6, verticalSpacing: 5) {
                GridRow {
                    ForEach(Self.days.indices, id: \.self) { day in
                        Text(Self.days[day])
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(0..<3, id: \.self) { meal in
                    GridRow {
                        ForEach(0..<7, id: \.self) { day in
                            // Spreading picks every third slot first: dinners for meat, breakfasts for dairy.
                            Plate(meat: Self.spread(meatMeals, at: day * 3 + meal),
                                  dairy: Self.spread(dairyMeals, at: day * 3 + (2 - meal)))
                        }
                    }
                }
            }
        }
    }

    /// Whether slot `index` of the week's 21 gets one of `count` meals, Bresenham-style so they spread evenly.
    static func spread(_ count: Int, at index: Int) -> Bool {
        let total = UserProfile.mealsPerWeek
        return (index + 1) * count / total > index * count / total
    }
}

private struct Plate: View {
    let meat: Bool
    let dairy: Bool

    var body: some View {
        ZStack {
            Circle().fill(.background.opacity(0.85))
            Circle().strokeBorder(.secondary.opacity(0.25), lineWidth: 1).padding(3)
            Text(meat ? "🍗" : dairy ? "🧀" : "🥗")
                .font(.system(size: 16))
                .id(meat ? 0 : dairy ? 1 : 2)
                .transition(.scale(scale: 0.3).combined(with: .opacity))
            if meat && dairy {
                Text("🧀")
                    .font(.system(size: 10))
                    .offset(x: 10, y: 10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 33, height: 33)
        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: [meat, dairy])
    }
}

/// The home on a patch of grass, drawn bigger as the floor area grows, with a badge per heating source.
struct HouseArt: View {
    let homeType: HomeType
    let areaM2: Double
    let heating: [HeatingSource]

    /// 30–86 pt, by the square root of the area (so it reads as length), saturating at 400 m².
    private var symbolSize: CGFloat { 30 + 56 * min(sqrt(areaM2 / 400), 1) }

    var body: some View {
        ArtPanel(tint: .yellow, height: 150) {
            VStack(spacing: 2) {
                Spacer(minLength: 0)
                house
                    .frame(height: 90, alignment: .bottom)
                Capsule()
                    .fill(Theme.leaf.opacity(0.45).gradient)
                    .frame(height: 8)
                    .padding(.horizontal, 28)
                Label(FloorAreaFormat.text(m2: areaM2), systemImage: "arrow.left.and.right")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: areaM2))
                    .padding(.bottom, 8)
            }
            .overlay(alignment: .topLeading) {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow.gradient)
                    .symbolEffect(.rotate, options: .speed(0.15))
                    .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    ForEach(heating.isEmpty ? [.none] : heating, id: \.self) { source in
                        Image(systemName: source.artSymbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(source.artColor.gradient)
                            .symbolEffect(.breathe)
                            .frame(width: 30, height: 30)
                            .background(.regularMaterial, in: .circle)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(10)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.65), value: areaM2)
        .animation(.snappy, value: heating)
        .animation(.snappy, value: homeType)
    }

    @ViewBuilder private var house: some View {
        let style = LinearGradient(colors: [.orange, .red.opacity(0.8)], startPoint: .top, endPoint: .bottom)
        switch homeType {
        case .townhouse:
            HStack(alignment: .bottom, spacing: -symbolSize * 0.12) {
                ForEach(0..<3, id: \.self) { _ in
                    Image(systemName: "house.fill").font(.system(size: symbolSize * 0.62))
                }
            }
            .foregroundStyle(style)
        default:
            Image(systemName: homeType.artSymbol)
                .font(.system(size: symbolSize))
                .foregroundStyle(homeType == .detachedHouse ? AnyShapeStyle(style) : AnyShapeStyle(Color.indigo.gradient))
                .contentTransition(.symbolEffect(.replace))
        }
    }
}

private extension HomeType {
    var artSymbol: String {
        switch self {
        case .apartment: "building.2.fill"
        case .townhouse, .detachedHouse: "house.fill"
        case .dorm: "building.fill"
        }
    }
}

private extension HeatingSource {
    var artSymbol: String {
        switch self {
        case .naturalGas: "flame.fill"
        case .electricResistance: "heater.vertical.fill"
        case .heatPump: "fan.fill"
        case .oil: "drop.fill"
        case .districtHeating: "thermometer.medium"
        case .none: "snowflake"
        }
    }

    var artColor: Color {
        switch self {
        case .naturalGas: .orange
        case .electricResistance: .yellow
        case .heatPump: .teal
        case .oil: .brown
        case .districtHeating: .red
        case .none: .cyan
        }
    }
}

/// A clothes rail that fills with one shirt per ~6 new items a year (so about one a month at the average).
struct ClothingRackArt: View {
    let perYear: Double

    private static let palette: [Color] = [.purple, .pink, .blue, .teal, .orange, Theme.leaf, .indigo, .red]
    private var count: Int { min(Int((perYear / 6).rounded(.up)), 18) }

    var body: some View {
        ArtPanel(tint: .purple, height: 104) {
            ZStack(alignment: .top) {
                // The rail and its two posts.
                HStack {
                    Capsule().frame(width: 4)
                    Spacer()
                    Capsule().frame(width: 4)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                Capsule()
                    .frame(height: 4)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                if count == 0 {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.3.trianglepath")
                            .font(.title)
                            .foregroundStyle(Theme.leaf.gradient)
                            .symbolEffect(.rotate, options: .speed(0.3))
                        Text("Wearing what you have")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 34)
                    .transition(.opacity)
                }
                // Shirts share the rail: each gets an equal slot (at most 42 pt) and overlaps its neighbour
                // when the rail is full, like a packed wardrobe.
                GeometryReader { geometry in
                    let slot = min(42, (geometry.size.width - 60) / CGFloat(max(count, 1)))
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(0..<count, id: \.self) { index in
                            VStack(spacing: -2) {
                                Image(systemName: "hanger")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "tshirt.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(Self.palette[index % Self.palette.count].gradient)
                            }
                            .frame(width: slot)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
            }
            .foregroundStyle(.secondary.opacity(0.6))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: count)
    }
}
