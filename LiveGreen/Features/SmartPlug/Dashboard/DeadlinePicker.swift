import SwiftUI

/// "Charged by" hour picker for green-hours planning.
struct DeadlinePicker: View {
    @Binding var hour: Int

    var body: some View {
        Picker("Charged by", systemImage: "alarm", selection: $hour) {
            ForEach(0..<24, id: \.self) { hour in
                Text(HourFormatting.label(hour)).tag(hour)
            }
        }
    }
}

/// Local hour-of-day labels ("7 AM" or "07") in the user's locale.
enum HourFormatting {
    static func label(_ hour: Int, calendar: Calendar = .current) -> String {
        let date = calendar.date(bySettingHour: ((hour % 24) + 24) % 24, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}
