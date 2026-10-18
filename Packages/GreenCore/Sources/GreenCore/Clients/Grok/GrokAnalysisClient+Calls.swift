import Foundation

extension GrokAnalysisClient: VisionIdentifier {
    /// Spec §5.3, with the same prompt and schema as `ClaudeClient.identify`.
    public func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse {
        try await identify(image: image, hints: hints, profile: profile, progress: { _ in })
    }

    /// Streams the answer and reports item names as they appear. Uses the fast identify model with a slim
    /// schema (one fallback carbon estimate per item) to keep a scan under ~15 s.
    public func identify(image: Data, hints: OCRHints, profile: UserProfile,
                         progress: @escaping @Sendable (IdentifyProgress) -> Void) async throws -> IdentifyResponse {
        var content: [JSONValue] = []
        if !image.isEmpty {
            content.append(["type": "input_image", "detail": "high",
                            "image_url": .string("data:\(ImageBlock.mediaType(of: image));base64,\(image.base64EncodedString())")])
        }
        content.append(["type": "input_text", "text": .string(ClaudeClient.identifyUserText(hints: hints, profile: profile, hasPhoto: !image.isEmpty))])
        if let feedback = ScanFeedback.promptSection(identifyFeedback) { content.append(["type": "input_text", "text": .string(feedback)]) }
        let reporter = ProgressThrottle(report: progress)
        return try await respond(model: configuration.identifyModel,
                                 instructions: ClaudeClient.identifySystemPrompt(vocabulary: configuration.vocabulary,
                                                                                 carbonEstimateOnly: true),
                                 content: content, schemaName: ReportComponentsTool.name,
                                 schema: ReportComponentsTool.carbonEstimateOnlySchema,
                                 timeout: configuration.identifyTimeout,
                                 progress: { reporter.update($0) }) { reply in
            try ReportComponentsTool.parse(reply.output)
        }
    }
}

extension GrokAnalysisClient: AlternativeSuggester {
    /// Spec §7, with the same prompt and schema as `ClaudeClient.suggestAlternatives`.
    public func suggestAlternatives(for components: [Component], profile: UserProfile) async throws -> [AlternativeSuggestion] {
        try await suggestAlternatives(for: components, profile: profile, retrying: [:])
    }

    /// The same call, with notes on swaps already turned down when it is a second try.
    public func suggestAlternatives(for components: [Component], profile: UserProfile,
                                    retrying notes: [UUID: String]) async throws -> [AlternativeSuggestion] {
        guard !components.isEmpty else { return [] }
        let text = try ClaudeClient.alternativesUserText(components: components, profile: profile, retrying: notes)
        return try await respond(instructions: ClaudeClient.alternativesSystemPrompt(vocabulary: configuration.vocabulary),
                                 content: [["type": "input_text", "text": .string(text)]],
                                 schemaName: SuggestAlternativesTool.name,
                                 schema: SuggestAlternativesTool.definition["input_schema"] ?? .null,
                                 timeout: configuration.alternativesTimeout) { reply in
            try SuggestAlternativesTool.parse(reply.output, components: components)
        }
    }
}

extension GrokAnalysisClient: SpecResearcher {
    /// Spec §5.4 T2 with the server-side `web_search` tool. A value is kept only when its source URL is one of
    /// the pages Grok's searches returned or cited; xAI does not return page text, so quotes cannot be
    /// checked verbatim the way Claude's `web_fetch` results allow.
    public func research(name: String, category: Category, identifiers: Identifiers,
                         metrics: [MetricKey]) async throws -> ResearchedSpec {
        let requested = metrics.filter(category.applies)
        guard !requested.isEmpty, identifiers.brand?.trimmedNonEmpty != nil || identifiers.model?.trimmedNonEmpty != nil else {
            return ResearchedSpec(values: [])
        }
        let text = ClaudeClient.researchUserText(name: name, category: category, identifiers: identifiers, metrics: requested)
        let requestedSet = Set(requested)
        return try await respond(instructions: ClaudeClient.researchSystemPrompt,
                                 content: [["type": "input_text", "text": .string(text)]],
                                 schemaName: ReportSpecsTool.name,
                                 schema: ReportSpecsTool.definition(metrics: requested)["input_schema"] ?? .null,
                                 tools: [["type": "web_search"]], timeout: configuration.researchTimeout) { reply in
            try ReportSpecsTool.parse(reply.output, requested: requestedSet,
                                      sources: ResearchSourceIndex(retrievedURLs: reply.sourceURLs))
        }
    }
}

/// Reports identify progress when something visible changes (a new item name, the scene title) or every
/// ~300 characters, so the UI is not flooded with one update per token.
final class ProgressThrottle: @unchecked Sendable {
    private let report: @Sendable (IdentifyProgress) -> Void
    private let lock = NSLock()
    private var last = IdentifyProgress()

    init(report: @escaping @Sendable (IdentifyProgress) -> Void) {
        self.report = report
    }

    func update(_ partialText: String) {
        let progress = IdentifyProgress.parsing(partialJSON: partialText)
        let shouldReport: Bool = lock.withLock {
            let changed = progress.itemNames != last.itemNames || progress.sceneTitle != last.sceneTitle
                || progress.receivedCharacters - last.receivedCharacters >= 300
            if changed { last = progress }
            return changed
        }
        if shouldReport { report(progress) }
    }
}
