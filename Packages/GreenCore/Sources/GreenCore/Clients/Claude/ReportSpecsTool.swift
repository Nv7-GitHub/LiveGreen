import Foundation

/// The `report_specs` tool used by spec research (spec §5.4, T2): every value carries the URL it came
/// from and a verbatim quote containing a figure. Values whose source was never retrieved in the
/// conversation, or whose quote does not appear in the fetched page, are discarded.
enum ReportSpecsTool {
    static let name = "report_specs"

    static func definition(metrics: [MetricKey]) -> JSONValue {
        [
            "name": .string(name),
            "description": """
                Report researched specification values for the product. Each value must cite a page you retrieved \
                in this conversation, with a verbatim quote containing the figure. List metrics you could not \
                source in not_found instead of estimating them.
                """,
            "input_schema": SchemaParts.object([
                "values": SchemaParts.array(of: SchemaParts.object([
                    "metric": SchemaParts.enumeration(metrics.map(\.rawValue), "Metric key."),
                    "value": SchemaParts.number("Value converted to the metric's canonical unit."),
                    "low": SchemaParts.nullableNumber("Lower bound only if the source states a range; else null."),
                    "high": SchemaParts.nullableNumber("Upper bound only if the source states a range; else null."),
                    "source_url": SchemaParts.string("URL of the page the quote is from (one you searched or fetched here)."),
                    "source_title": SchemaParts.string("Title of that page or document."),
                    "quote": SchemaParts.string("Verbatim text from the page that contains the figure (under 300 characters)."),
                ], required: ["metric", "value", "low", "high", "source_url", "source_title", "quote"]),
                    "Cited values; at most one per metric."),
                "not_found": SchemaParts.array(of: SchemaParts.enumeration(metrics.map(\.rawValue), "Metric key."),
                                               "Requested metrics with no citable source."),
            ], required: ["values", "not_found"]),
        ]
    }

    static func parse(_ input: JSONValue, requested: Set<MetricKey>, sources: ResearchSourceIndex) throws -> ResearchedSpec {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload: Payload
        do {
            payload = try input.decode(Payload.self, decoder: decoder)
        } catch {
            throw GreenCoreError.invalidModelOutput("report_specs input: \(error)")
        }
        let values = payload.values.compactMap { item -> ResearchedValue? in
            guard let metric = MetricKey(rawValue: item.metric), requested.contains(metric), item.value.isFinite,
                  item.quote.contains(where: \.isNumber),
                  let url = URL(string: item.sourceUrl.trimmingCharacters(in: .whitespaces)),
                  sources.supports(quote: item.quote, from: url) else { return nil }
            let citation = Citation(url: url, title: item.sourceTitle.trimmedNonEmpty ?? url.host() ?? url.absoluteString,
                                    quotedText: item.quote.trimmingCharacters(in: .whitespacesAndNewlines))
            guard citation.isValid else { return nil }
            let hasRange = item.low.map(\.isFinite) == true && item.high.map(\.isFinite) == true
            return ResearchedValue(metric: metric, value: item.value, low: hasRange ? item.low : nil,
                                   high: hasRange ? item.high : nil, citation: citation)
        }
        return ResearchedSpec(values: values)
    }

    struct Payload: Decodable {
        var values: [ValuePayload]
        var notFound: [String]?
    }

    struct ValuePayload: Decodable {
        var metric: String
        var value: Double
        var low: Double?
        var high: Double?
        var sourceUrl: String
        var sourceTitle: String
        var quote: String
    }
}
