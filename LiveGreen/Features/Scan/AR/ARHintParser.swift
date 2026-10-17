import Foundation
import GreenCore

/// Turns recognized text lines and barcode payloads into `OCRHints` (spec §5.2 extraction rules).
nonisolated enum ARHintParser {
    static func hints(textLines: [String], barcodes: [String]) -> OCRHints {
        OCRHints(gtins: gtins(from: barcodes + textLines),
                 modelNumbers: modelNumbers(in: textLines),
                 wattages: wattages(in: textLines),
                 fiberPercentages: fibers(in: textLines),
                 resinCodes: resinCodes(in: textLines),
                 textLines: textLines)
    }

    /// 8, 12, 13 or 14 digit codes, deduplicated in order.
    static func gtins(from payloads: [String]) -> [String] {
        let codes = payloads.flatMap { matches(of: /\b(\d{14}|\d{13}|\d{12}|\d{8})\b/, in: $0) }
        return unique(codes)
    }

    /// Tokens like `[A-Z0-9-]{5,}` on lines mentioning a model, containing both letters and digits.
    static func modelNumbers(in lines: [String]) -> [String] {
        let tokens = lines
            .filter { $0.range(of: #"\b(model|mod|m/n|type)\b"#, options: [.regularExpression, .caseInsensitive]) != nil }
            .flatMap { line in
                matches(of: /[A-Z0-9][A-Z0-9-]{4,}/, in: line.uppercased())
                    .filter { $0.contains(where: \.isLetter) && $0.contains(where: \.isNumber) }
                    .filter { !["MODEL", "MOD"].contains($0) }
            }
        return unique(tokens)
    }

    static func wattages(in lines: [String]) -> [Double] {
        let values = lines.flatMap { line in
            line.matches(of: /(\d+(?:[.,]\d+)?)\s?W\b/).compactMap { Double($0.1.replacingOccurrences(of: ",", with: ".")) }
        }
        var seen = Set<Double>()
        return values.filter { seen.insert($0).inserted }
    }

    /// "60% cotton", "40 % polyester".
    static func fibers(in lines: [String]) -> [MaterialShare] {
        lines.flatMap { line in
            line.matches(of: /(\d{1,3})\s?%\s?([A-Za-z]+)/).compactMap { match -> MaterialShare? in
                guard let percent = Double(match.1), percent <= 100 else { return nil }
                return MaterialShare(material: match.2.lowercased(), percent: percent)
            }
        }
    }

    /// Resin identification codes from resin abbreviations such as "PET", "HDPE" or "PP".
    static func resinCodes(in lines: [String]) -> [Int] {
        let names = ["PETE": 1, "PET": 1, "HDPE": 2, "PVC": 3, "LDPE": 4, "PP": 5, "PS": 6]
        var codes: [Int] = []
        for line in lines {
            for token in line.uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                if let code = names[String(token)] { codes.append(code) }
            }
        }
        return unique(codes)
    }

    private static func matches(of regex: Regex<(Substring, Substring)>, in text: String) -> [String] {
        text.matches(of: regex).map { String($0.1) }
    }

    private static func matches(of regex: Regex<Substring>, in text: String) -> [String] {
        text.matches(of: regex).map { String($0.0) }
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }
}
