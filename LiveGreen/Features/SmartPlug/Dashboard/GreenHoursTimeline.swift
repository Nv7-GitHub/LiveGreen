import SwiftUI
import GreenCore

/// Today's 24-h grid forecast as glass bars: taller is dirtier, planned green hours are tinted.
struct GreenHoursTimeline: View {
    let forecast: GridForecast
    let onHours: Set<Int>
    var currentHour = Calendar.current.component(.hour, from: Date())

    private var range: ClosedRange<Double> {
        let low = forecast.hourly.min() ?? 0
        let high = forecast.hourly.max() ?? 1
        return low...max(high, low + 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassEffectContainer(spacing: 2) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<24, id: \.self) { hour in
                        bar(hour)
                    }
                }
                .frame(height: 96)
            }
            HStack {
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text(HourFormatting.label(hour))
                    if hour != 18 { Spacer() }
                }
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func bar(_ hour: Int) -> some View {
        let intensity = forecast.intensity(atHour: hour)
        let fraction = (intensity - range.lowerBound) / (range.upperBound - range.lowerBound)
        let isOn = onHours.contains(hour)
        return Capsule()
            .fill(.clear)
            .frame(maxWidth: .infinity)
            .frame(height: 28 + 68 * fraction)
            .glassEffect(isOn ? Glass.regular.tint(Theme.leaf) : .regular, in: .capsule)
            .overlay(alignment: .top) {
                if hour == currentHour {
                    Circle().fill(.primary).frame(width: 4, height: 4).offset(y: -8)
                }
            }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            Label("Green hours (charging)", systemImage: "circle.fill").foregroundStyle(Theme.leaf)
            Label("Shorter bar = cleaner grid", systemImage: "chart.bar.fill").foregroundStyle(.secondary)
        }
        .font(.caption2)
        .labelStyle(.titleAndIcon)
    }

    private var accessibilitySummary: String {
        let hours = onHours.sorted().map { HourFormatting.label($0) }.joined(separator: ", ")
        return hours.isEmpty ? "No green hours planned" : "Charging during \(hours)"
    }
}

#Preview {
    GreenHoursTimeline(forecast: GridForecast(hourly: (0..<24).map { 200 + 80 * sin(Double($0) / 3.8) }, isFallback: true),
                       onHours: [1, 2, 3, 13])
        .padding()
}
