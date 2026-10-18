import SwiftUI
import GreenCore

/// Meal nudges: the phone number they go to, the meal trends LiveGreen noticed, the texts scheduled for just before
/// those meals (each with when it would normally go out and a Send now button for demos) and the texts sent.
struct NudgesTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PhoneSetupCard()
                    trendsSection
                    upcomingSection
                    if !app.nudges.sent.isEmpty { sentSection }
                }
                .padding()
            }
            .greeneryBackground(.nudges)
            .navigationTitle("Nudges")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Look for trends", systemImage: "arrow.clockwise") { app.refreshNudges() }
                        .disabled(app.nudges.isRefreshing)
                        .accessibilityIdentifier("nudges.refresh")
                }
            }
            .task { app.refreshNudges() }
        }
    }

    // MARK: - Sections

    @ViewBuilder private var trendsSection: some View {
        let trends = app.nudges.trends
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("What we noticed", systemImage: "chart.line.uptrend.xyaxis")
            if trends.isEmpty {
                GreeneryEmptyState(art: .seedling,
                                   title: app.nudges.isRefreshing ? "Looking at your meals…" : "No heavy meals yet",
                                   caption: "Watching what's on your plate",
                                   message: "Scan what you eat. When a meal keeps coming out high in carbon, LiveGreen texts you a specific swap nearby right before you'd usually eat it.") {
                    EmptyView()
                }
                .accessibilityIdentifier("nudges.noTrends")
            } else {
                ForEach(trends) { trend in
                    GlassCard {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: trend.mealTime.systemImage)
                                .font(.title2)
                                .foregroundStyle(Theme.warning)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(trend.mealTime.title) is running heavy").font(.headline)
                                Text(trend.reason).font(.subheadline).foregroundStyle(.secondary)
                                Text("Usually around \(Self.clock(minute: trend.typicalMinute)) · \(trend.scanIDs.count) \(trend.scanIDs.count == 1 ? "scan" : "scans")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("nudges.trend.\(trend.mealTime.rawValue)")
                }
            }
        }
    }

    @ViewBuilder private var upcomingSection: some View {
        let upcoming = app.nudges.upcoming
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Scheduled texts", systemImage: "clock.badge")
                ForEach(upcoming) { nudge in NudgeCard(nudge: nudge) }
            }
        }
    }

    private var sentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Sent", systemImage: "checkmark.message")
            ForEach(app.nudges.sent) { nudge in
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("\(nudge.mealTime.title) nudge", systemImage: nudge.mealTime.systemImage)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if let sentAt = nudge.sentAt {
                                Text(sentAt.formatted(.relative(presentation: .named)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        MessageBubble(text: nudge.message)
                        Button("Send again", systemImage: "arrow.uturn.forward") {
                            Task { await app.nudges.send(nudge, photon: app.services.photon) }
                        }
                        .buttonStyle(.glass)
                        .font(.caption)
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func clock(minute: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// One scheduled text: when it would normally go out, the message, and Send now.
struct NudgeCard: View {
    let nudge: Nudge
    @Environment(AppModel.self) private var app

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label("\(nudge.mealTime.title) nudge", systemImage: nudge.mealTime.systemImage)
                        .font(.headline)
                    Spacer()
                    status
                }
                Label {
                    Text("Normally sends \(Self.when(nudge.scheduledFor)), \(MealTrend.leadMinutes) min before your usual \(nudge.mealTime.rawValue)")
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("nudge.scheduledFor")
                MessageBubble(text: nudge.message)
                if let error = nudge.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
                Button {
                    Task { await app.nudges.send(nudge, photon: app.services.photon) }
                } label: {
                    Label(nudge.status == .sending ? "Sending…" : "Send now", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(nudge.status == .sending)
                .accessibilityIdentifier("nudge.sendNow")
                Text("Demo: sends the text right away instead of waiting for \(nudge.mealTime.rawValue).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("nudge.card.\(nudge.mealTime.rawValue)")
    }

    @ViewBuilder private var status: some View {
        switch nudge.status {
        case .scheduled: pill("Scheduled", color: Theme.leaf)
        case .sending: pill("Sending", color: .secondary)
        case .sent: pill("Sent", color: Theme.leaf)
        case .failed: pill("Not sent", color: Theme.danger)
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: .capsule)
    }

    /// "today at 11:40 AM", "tomorrow at 11:40 AM", or the weekday.
    static func when(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "today at \(time)" }
        if calendar.isDateInTomorrow(date) { return "tomorrow at \(time)" }
        return date.formatted(.dateTime.weekday(.wide)) + " at \(time)"
    }
}

/// An iMessage-style bubble for previewing a text.
struct MessageBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(red: 0.2, green: 0.55, blue: 1.0), in: .rect(cornerRadius: 18))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 24)
            .textSelection(.enabled)
            .accessibilityIdentifier("nudge.message")
    }
}

/// The phone number nudges go to and turning them on: get a LiveGreen number, text it once, done.
struct PhoneSetupCard: View {
    @Environment(AppModel.self) private var app
    @State private var phone = ""
    @State private var working = false
    @State private var note: String?
    @State private var editing = false

    var body: some View {
        let center = app.nudges
        GlassCard(tint: center.isTextingOn ? Theme.leaf.opacity(0.12) : nil) {
            VStack(alignment: .leading, spacing: 12) {
                if let number = center.phone, let line = center.lineNumber, !editing {
                    if center.isTextingOn {
                        Label("Texting is on", systemImage: "checkmark.message.fill")
                            .font(.headline).foregroundStyle(Theme.leaf)
                        Text("Nudges go to \(PhoneFormat.pretty(number)) from \(PhoneFormat.pretty(line)) over iMessage.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Label("One more step", systemImage: "message.badge")
                            .font(.headline)
                        Text("Text START to \(PhoneFormat.pretty(line)) from \(PhoneFormat.pretty(number)). iMessage only lets your LiveGreen number write to you once you've messaged it.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            if let url = URL(string: "sms:\(line)&body=START") {
                                Link(destination: url) { Label("Open Messages", systemImage: "arrow.up.message") }
                                    .buttonStyle(.glass)
                            }
                            Button(working ? "Checking…" : "I've sent it", systemImage: "checkmark") { check() }
                                .buttonStyle(.glassProminent)
                                .disabled(working)
                                .accessibilityIdentifier("nudges.checkTexted")
                        }
                    }
                    Button("Change number") { editing = true; phone = "" }
                        .font(.caption)
                } else {
                    Label("Get nudges by text", systemImage: "message.badge")
                        .font(.headline)
                    Text("LiveGreen texts you a greener idea, with a place nearby, right before a meal that's been heavy on carbon.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    TextField("(617) 555-0123", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .padding(12)
                        .background(.background.opacity(0.6), in: .rect(cornerRadius: 12))
                        .accessibilityIdentifier("nudges.phone")
                    HStack {
                        Button(working ? "Setting up…" : "Get my LiveGreen number", systemImage: "phone.badge.plus") { register() }
                            .buttonStyle(.glassProminent)
                            .disabled(working || PhotonClient.e164(phone) == nil)
                        if editing { Button("Cancel") { editing = false }.buttonStyle(.glass) }
                    }
                }
                if let message = note ?? center.setupError {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("nudges.phoneCard")
    }

    private func register() {
        working = true
        note = nil
        Task {
            do {
                try await app.nudges.register(phone: phone, name: app.displayName, photon: app.services.photon)
                editing = false
            } catch {
                note = NudgeCenter.describe(error)
            }
            working = false
        }
    }

    private func check() {
        working = true
        note = nil
        Task {
            let on = await app.nudges.checkActivation(photon: app.services.photon)
            if !on, app.nudges.setupError == nil { note = "Haven't seen your text yet. It can take a few seconds; try again." }
            working = false
        }
    }
}

/// On a meal's results: the text LiveGreen scheduled because of it.
struct NudgeBanner: View {
    let nudge: Nudge
    @Environment(AppModel.self) private var app

    var body: some View {
        Button { app.selectedTab = .nudges } label: {
            HStack(spacing: 12) {
                Image(systemName: "message.badge.filled.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.leaf)
                VStack(alignment: .leading, spacing: 2) {
                    Text("We'll text you before \(nudge.mealTime.rawValue)").font(.subheadline.weight(.semibold))
                    Text("\(NudgeCard.when(nudge.scheduledFor).prefix(1).uppercased() + NudgeCard.when(nudge.scheduledFor).dropFirst())"
                         + (nudge.placeName.map { " · try \($0)" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .glassCard(cornerRadius: 20, tint: Theme.leaf.opacity(0.12), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("results.nudgeBanner")
    }
}
