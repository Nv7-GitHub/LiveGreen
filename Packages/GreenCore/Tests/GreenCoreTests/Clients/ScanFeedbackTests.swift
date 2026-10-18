import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

@Suite("Scan feedback")
struct ScanFeedbackTests {
    static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

    static func note(_ text: String, items: [String] = ["TV"], categories: [GreenCore.Category] = [.electronic],
                     daysAgo: Double = 0) -> ScanFeedback {
        ScanFeedback(scanID: UUID(), date: Date(timeIntervalSince1970: 1_800_000_000 - daysAgo * 86_400), note: text,
                     identifiedItems: items, categories: categories)
    }

    static let monitor = note("The TV you scanned was actually a large monitor", items: ["TV", "Soundbar"])

    // MARK: - Prompt section

    @Test func noNotesGiveNoSection() {
        #expect(ScanFeedback.promptSection([]) == nil)
        #expect(ScanFeedback.promptSection([Self.note("  \n ")]) == nil)
        #expect(ScanFeedback.promptSection([Self.monitor], limit: 0) == nil)
    }

    @Test func sectionPairsNotesWithWhatWasIdentifiedAndSaysHintsOnly() throws {
        let section = try #require(ScanFeedback.promptSection([Self.monitor]))
        #expect(section.hasPrefix("Recent user corrections (hints only)"))
        #expect(section.contains(#"- Identified: TV, Soundbar. User said: "The TV you scanned was actually a large monitor""#))
        #expect(section.contains("weak hints"))
        #expect(section.contains("only when this photo's visual evidence or labels are consistent with it"))
        #expect(section.contains("Never relabel every similar item by default"))
        #expect(section.contains("a legible brand, model or label always wins over a note"))
    }

    @Test func sectionCapsNotesAndCharacters() throws {
        let many = (0..<8).map { Self.note("Note number \($0)", daysAgo: Double($0)) }
        let five = try #require(ScanFeedback.promptSection(many))
        #expect(Self.noteLines(five).count == 5)
        #expect(five.contains("Note number 4") && !five.contains("Note number 5"))

        let long = (0..<5).map { Self.note(String(repeating: "word ", count: 120) + "\($0)") }
        let clipped = try #require(ScanFeedback.promptSection(long))
        let lines = Self.noteLines(clipped)
        #expect(!lines.isEmpty && lines.count < 5)
        #expect(lines.joined(separator: "\n").count <= 600)
        #expect(lines.allSatisfy { $0.hasSuffix("…\"") }, "one long note is clipped, not sent whole")
    }

    @Test func sectionKeepsQuotingAndLinesIntact() throws {
        let section = try #require(ScanFeedback.promptSection([Self.note("It said \"TV\"\nbut it's a monitor")]))
        #expect(section.contains(#"User said: "It said 'TV' but it's a monitor""#))
    }

    static func noteLines(_ section: String) -> [String] {
        section.split(separator: "\n").map(String.init).filter { $0.hasPrefix("- ") }
    }

    // MARK: - Choosing notes

    @Test func relevantPrefersNotesLikeThisFrameThenNewest() {
        let laptop = Self.note("That was a Dell laptop, not a monitor", items: ["Monitor"], daysAgo: 30)
        let soup = Self.note("The soup was lentil, not tomato", items: ["Tomato soup"], categories: [.food], daysAgo: 1)
        let shirt = Self.note("The shirt is linen", items: ["Shirt"], categories: [.clothing], daysAgo: 2)
        let dell = OCRHints(modelNumbers: ["E2225H"], textLines: ["DELL"])
        #expect(ScanFeedback.relevant([soup, laptop, shirt], to: dell).first == laptop)
        #expect(ScanFeedback.relevant([laptop, shirt, soup], to: .none) == [soup, shirt, laptop])
        #expect(ScanFeedback.relevant([laptop, shirt, soup], to: .none, limit: 2) == [soup, shirt])
    }

    @Test func relevantCountsRepeatedNotesOnce() {
        let newer = Self.note("the tv was a monitor", daysAgo: 1)
        let older = Self.note("The TV was a monitor ", daysAgo: 9)
        #expect(ScanFeedback.relevant([older, newer], to: .none) == [newer])
    }

    @Test func noteOnAScanRecordsItsItems() async {
        let scan = await SampleScans.resolved(.meal)
        let feedback = ScanFeedback(note: "No fries", on: scan)
        #expect(feedback.scanID == scan.id)
        #expect(feedback.identifiedItems == scan.components.map(\.name))
        #expect(Set(feedback.categories) == Set(scan.components.map(\.category)))
        #expect(feedback.categories.count == Set(feedback.categories).count)
    }

    // MARK: - Identify

    @Test func claudeIdentifySendsNotesAsASeparateBlock() async throws {
        let transport = MockTransport([.fixture("claude/identify_tool_use.json"), .fixture("claude/identify_tool_use.json")])
        let client = ClaudeClient(configuration: .init(apiKey: "sk-test", retry: .instant()), transport: transport)
        _ = try await client.identify(image: Self.jpeg, hints: .none, profile: .default, feedback: [Self.monitor],
                                      progress: { _ in })
        _ = try await client.identify(image: Self.jpeg, hints: .none, profile: .default)

        let content = try #require(transport.requests.first?.jsonBody?["messages"]?.array?.first?["content"]?.array)
        #expect(content.count == 3)
        let text = try #require(content[2]["text"]?.string)
        #expect(text == ScanFeedback.promptSection([Self.monitor]))
        let plain = try #require(transport.requests.last?.jsonBody?["messages"]?.array?.first?["content"]?.array)
        #expect(plain.count == 2, "the client itself keeps no notes between calls")
    }

    @Test func grokIdentifySendsNotesAsASeparatePart() async throws {
        let transport = MockTransport([GrokAnalysisClientTests.reply(GrokAnalysisClientTests.identifyJSON)])
        let client = GrokAnalysisClient(configuration: .init(apiKey: "xai-key", retry: .instant()), transport: transport)
        _ = try await client.identify(image: Self.jpeg, hints: .none, profile: .default, feedback: [Self.monitor],
                                      progress: { _ in })
        let parts = try #require(transport.requests.first?.jsonBody?["input"]?.array?.first?["content"]?.array)
        #expect(parts.last?["type"]?.string == "input_text")
        #expect(parts.last?["text"]?.string == ScanFeedback.promptSection([Self.monitor]))
    }

    @Test func pipelinePassesTheMostRelevantNotesToIdentify() async throws {
        let vision = RecordingIdentifier()
        var pipeline = Self.pipeline(vision: vision)
        pipeline.feedback = (0..<8).map { Self.note("Note \($0)", daysAgo: Double($0)) }
        _ = try await pipeline.run(image: Self.jpeg, hints: .none, mode: .photo)
        let sent = try #require(vision.received.values.first)
        #expect(sent.map(\.note) == (0..<5).map { "Note \($0)" })

        _ = try await Self.pipeline(vision: vision).run(image: Self.jpeg, hints: .none, mode: .photo)
        #expect(vision.received.values.last == [], "no notes by default")
    }

    @Test func identifiersWithoutNotesSupportIgnoreThem() async throws {
        let response = try await FakeVisionIdentifier().identify(image: Self.jpeg, hints: .none, profile: .default,
                                                                 feedback: [Self.monitor], progress: { _ in })
        #expect(response == DemoScene.deskSetup.identifyResponse)
    }

    static func pipeline(vision: any VisionIdentifier) -> ScanPipeline {
        let store = ReferenceStore.bundled
        return ScanPipeline(vision: vision, alternatives: FakeAlternativeSuggester(), products: FakeProductDatabase(),
                            ladder: EvidenceLadder(resolvers: [FactorModelResolver(store: store), EstimateResolver()]),
                            engine: ImpactEngine(reference: store), profile: .default)
    }
}

/// Records the notes each identify call received, then answers with the desk scene.
private struct RecordingIdentifier: VisionIdentifier {
    let received = Recorder<[ScanFeedback]>()

    func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse {
        try await identify(image: image, hints: hints, profile: profile, feedback: [], progress: { _ in })
    }

    func identify(image: Data, hints: OCRHints, profile: UserProfile, feedback: [ScanFeedback],
                  progress: @escaping @Sendable (IdentifyProgress) -> Void) async throws -> IdentifyResponse {
        received.append(feedback)
        return try await FakeVisionIdentifier().identify(image: image, hints: hints, profile: profile)
    }
}
