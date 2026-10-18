import Foundation

extension ClaudeClient: SpecResearcher {
    /// Spec §5.4 T2: researches spec-sheet values with the `web_search` / `web_fetch` server tools.
    /// Returns only values with a retrieved source URL and a verbatim quote; everything else is dropped.
    public func research(name: String, category: Category, identifiers: Identifiers,
                         metrics: [MetricKey]) async throws -> ResearchedSpec {
        let requested = metrics.filter(category.applies)
        guard !requested.isEmpty, identifiers.brand?.trimmedNonEmpty != nil || identifiers.model?.trimmedNonEmpty != nil else {
            return ResearchedSpec(values: [])
        }
        let spec = ToolCallSpec(system: Self.researchSystemPrompt,
                                tools: [ReportSpecsTool.definition(metrics: requested)] + researchServerTools,
                                toolName: ReportSpecsTool.name, maxTokens: 16_000,
                                effort: configuration.researchEffort, timeout: configuration.researchTimeout)
        let text = Self.researchUserText(name: name, category: category, identifiers: identifiers, metrics: requested)
        let requestedSet = Set(requested)
        return try await runTool(spec, userContent: [["type": "text", "text": .string(text)]]) { input, transcript in
            try ReportSpecsTool.parse(input, requested: requestedSet, sources: ResearchSourceIndex(transcript: transcript))
        }
    }

    var researchServerTools: [JSONValue] {
        [
            ["type": "web_search_20260209", "name": "web_search", "max_uses": .number(Double(configuration.researchSearchLimit))],
            ["type": "web_fetch_20260209", "name": "web_fetch", "max_uses": .number(Double(configuration.researchFetchLimit)),
             "max_content_tokens": 20_000],
        ]
    }

    static let researchSystemPrompt = """
        You are LiveGreen's spec researcher. Given one product, find published figures for the requested \
        metrics, then call the `report_specs` tool exactly once.

        How to research
        - Use web_search to find primary sources for the exact model: the manufacturer's spec sheet, datasheet \
        or user manual, the EU EPREL energy label, the ENERGY STAR record, or a manufacturer Product Carbon \
        Footprint (PCF) / environmental report. Independent lab measurements (e.g. measured power draw in a \
        reputable review) are acceptable when no primary source exists.
        - Use web_fetch to read the page you will cite, so the quote can be checked against it.
        - Be quick: a few targeted searches, and stop once the requested metrics are sourced or clearly unavailable.

        What to report
        - Report a value only if the page states it for this model (or a variant the page explicitly says shares \
        the figure). Never estimate, average across models or infer from similar products. A missing value is \
        far better than an uncited one; list it in not_found.
        - When only a model line is given (no model number), the product was recognized from its appearance. Use \
        the maker's published figures for that line (spec page, environmental or carbon footprint report), for the \
        size and generation the line describes, else its current one, and its base configuration. If the cited \
        page lists several configurations of that line, report the base one as value with low and high spanning \
        the listed ones. Never use figures for a different line.
        - Every value needs source_url (a page you retrieved in this conversation), source_title, and quote: the \
        exact sentence or table cell text from that page containing the figure, copied verbatim.
        - Convert the figure to the metric's canonical unit and basis below. Give low/high only when the source \
        itself states a range (e.g. typical vs maximum power, or a model line's configurations); otherwise null.
        - Carbon: only from a PCF for this model (or this model line, as above). LiveGreen adds use-phase \
        electricity itself, so report the footprint excluding the use phase when the PCF gives a lifecycle \
        breakdown; if it gives no breakdown, do not report carbon.

        Metric units and basis:
        \(PromptParts.metricDefinitions)
        """

    static func researchUserText(name: String, category: Category, identifiers: Identifiers, metrics: [MetricKey]) -> String {
        var lines = ["Product: \(name)", "Category: \(category.rawValue)"]
        if let brand = identifiers.brand?.trimmedNonEmpty { lines.append("Brand: \(brand)") }
        if let model = identifiers.model?.trimmedNonEmpty { lines.append("Model: \(model)") }
        if let line = identifiers.modelLine?.trimmedNonEmpty {
            lines.append("Model line: \(line)")
            if identifiers.model?.trimmedNonEmpty == nil {
                let confidence = identifiers.confidence.map { ", \($0.rawValue) confidence" } ?? ""
                let cues = identifiers.appearanceCues?.trimmedNonEmpty.map { "; cues: \($0)" } ?? ""
                lines.append("No model number is known (recognized from its appearance\(confidence)\(cues)).")
            }
        }
        if let gtin = identifiers.gtin?.trimmedNonEmpty { lines.append("GTIN: \(gtin)") }
        if let text = identifiers.ocrText?.trimmedNonEmpty { lines.append("Label text: \(text)") }
        lines.append("Requested metrics:")
        lines += metrics.map { "- \($0.rawValue) (\($0.unit.symbol)): \(PromptParts.basis(of: $0))" }
        lines.append("Research, then call `report_specs`.")
        return lines.joined(separator: "\n")
    }
}
