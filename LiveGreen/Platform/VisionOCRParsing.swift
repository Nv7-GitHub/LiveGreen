import Foundation
import GreenCore

/// Pure text/barcode parsing for the on-device pre-pass (spec §5.2). No Vision dependency, so it is
/// unit-testable on any host.
nonisolated enum OCRTextParser {
    /// Builds hints from barcode payloads (already validated by the detector) and recognized text lines.
    static func hints(barcodePayloads: [String], textLines: [String]) -> OCRHints {
        let lines = textLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return OCRHints(
            gtins: unique(gtins(fromBarcodes: barcodePayloads) + gtins(fromText: lines)),
            modelNumbers: modelNumbers(in: lines),
            wattages: wattages(in: lines),
            fiberPercentages: fiberPercentages(in: lines),
            resinCodes: resinCodes(in: lines),
            textLines: lines)
    }

    // MARK: - GTINs

    static let gtinLengths: Set<Int> = [8, 12, 13, 14]

    /// Numeric retail barcode payloads (EAN-8, UPC-A/E, EAN-13, ITF-14). QR and other payloads are dropped.
    static func gtins(fromBarcodes payloads: [String]) -> [String] {
        payloads.compactMap { payload in
            let trimmed = payload.trimmingCharacters(in: .whitespaces)
            guard (8...14).contains(trimmed.count), trimmed.allSatisfy(\.isASCIIDigit) else { return nil }
            return trimmed
        }
    }

    /// Digit runs printed under a barcode, kept only when the GS1 check digit is valid.
    static func gtins(fromText lines: [String]) -> [String] {
        let regex = #/\b(\d[\d ]{6,18}\d)\b/#
        return lines.flatMap { line in
            line.matches(of: regex).compactMap { match -> String? in
                let digits = String(match.output.1).filter(\.isASCIIDigit)
                return gtinLengths.contains(digits.count) && hasValidCheckDigit(digits) ? digits : nil
            }
        }
    }

    /// GS1 mod-10 check: weights 3,1,3,… from the digit left of the check digit.
    static func hasValidCheckDigit(_ code: String) -> Bool {
        let digits = code.compactMap(\.wholeNumberValue)
        guard digits.count == code.count, let check = digits.last else { return false }
        let sum = digits.dropLast().reversed().enumerated().reduce(0) { total, pair in
            total + pair.element * (pair.offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10 == check
    }

    // MARK: - Model numbers

    /// `[A-Z0-9-]{5,}` tokens that follow a "Model"/"MOD"/"M/N" label on the same line, or on the next
    /// line when the label stands alone. Tokens must contain a digit.
    static func modelNumbers(in lines: [String]) -> [String] {
        let labelled = #/(?i)\b(?:model|mod|m\/n|type)\b\.?\s*(?:no\.?|number|#)?\s*[:#.]?\s*([A-Za-z0-9][A-Za-z0-9-]{4,})/#
        let bareLabel = #/(?i)^\s*(?:model|mod|m\/n)\s*(?:no\.?|number|#)?\s*[:#.]?\s*$/#
        var found: [String] = []
        for (index, line) in lines.enumerated() {
            for match in line.matches(of: labelled) {
                found.append(String(match.output.1))
            }
            if line.wholeMatch(of: bareLabel) != nil, index + 1 < lines.count,
               let token = lines[index + 1].firstMatch(of: #/([A-Za-z0-9][A-Za-z0-9-]{4,})/#) {
                found.append(String(token.output.1))
            }
        }
        return unique(found.map { $0.uppercased() }.filter(isModelToken))
    }

    static func isModelToken(_ token: String) -> Bool {
        token.count >= 5 && token.contains(where: \.isASCIIDigit)
            && token.allSatisfy { $0.isASCIIDigit || ("A"..."Z").contains($0) || $0 == "-" }
            && !["NUMBER"].contains(token)
    }

    // MARK: - Wattage

    /// `\d+\s?W` (and kW) values; "Wh", "W/m" and similar are excluded by the word boundary.
    static func wattages(in lines: [String]) -> [Double] {
        let regex = #/\b(\d+(?:[.,]\d+)?)\s?(k?)W\b/#
        let values = lines.flatMap { line in
            line.matches(of: regex).compactMap { match -> Double? in
                guard let number = Double(match.output.1.replacingOccurrences(of: ",", with: ".")) else { return nil }
                let watts = match.output.2.isEmpty ? number : number * 1000
                return (0.1...50_000).contains(watts) ? watts : nil
            }
        }
        return unique(values)
    }

    // MARK: - Fiber content

    /// Canonical fiber names keyed by the spellings that appear on care labels.
    static let fiberSynonyms: [String: String] = [
        "cotton": "cotton", "baumwolle": "cotton", "coton": "cotton", "algodon": "cotton",
        "polyester": "polyester", "poliester": "polyester",
        "wool": "wool", "laine": "wool", "merino": "wool",
        "nylon": "nylon", "polyamide": "nylon", "polyamid": "nylon",
        "linen": "linen", "flax": "linen", "lin": "linen",
        "elastane": "elastane", "spandex": "elastane", "lycra": "elastane", "elasthan": "elastane",
        "viscose": "viscose", "rayon": "viscose",
        "acrylic": "acrylic", "silk": "silk", "lyocell": "lyocell", "tencel": "lyocell",
        "modal": "modal", "cashmere": "cashmere", "hemp": "hemp",
    ]

    /// "60% cotton", "COTTON 60 %" and "60 % CO" style pairs. Shares are de-duplicated by material.
    static func fiberPercentages(in lines: [String]) -> [MaterialShare] {
        let percentFirst = #/(\d{1,3}(?:[.,]\d)?)\s?%\s*([A-Za-zÀ-ÿ]+)/#
        let nameFirst = #/([A-Za-zÀ-ÿ]+)\s*[:\-]?\s*(\d{1,3}(?:[.,]\d)?)\s?%/#
        func pairs(_ line: String, percentLeads: Bool) -> [MaterialShare] {
            let raw: [(Substring, Substring)] = percentLeads
                ? line.matches(of: percentFirst).map { ($0.output.2, $0.output.1) }
                : line.matches(of: nameFirst).map { ($0.output.1, $0.output.2) }
            return raw.compactMap { name, percentText in
                guard let material = fiberSynonyms[name.lowercased()],
                      let percent = Double(percentText.replacingOccurrences(of: ",", with: ".")),
                      percent > 0, percent <= 100 else { return nil }
                return MaterialShare(material: material, percent: percent)
            }
        }
        var shares: [MaterialShare] = []
        for line in lines {
            // A line reads either "60% cotton 40% polyester" or "cotton 60% polyester 40%"; pick the
            // style from its first character and fall back to the other when it finds nothing.
            let percentLeads = line.first?.isNumber ?? false
            let found = pairs(line, percentLeads: percentLeads)
            for share in found.isEmpty ? pairs(line, percentLeads: !percentLeads) : found
            where !shares.contains(where: { $0.material == share.material }) {
                shares.append(share)
            }
        }
        return shares
    }

    // MARK: - Resin codes

    static let resinAbbreviations: [String: Int] = [
        "PET": 1, "PETE": 1, "HDPE": 2, "PEHD": 2, "PVC": 3, "LDPE": 4, "PELD": 4, "PP": 5, "PS": 6,
    ]

    /// Resin identification codes 1–7 from the ♳–♹ symbols, "#2 HDPE"/"HDPE 2" pairs, or
    /// stand-alone upper-case abbreviations.
    static func resinCodes(in lines: [String]) -> [Int] {
        var codes: [Int] = []
        let numbered = #/(?:#|\b)([1-7])\s*[-\/]?\s*(PETE|PET|HDPE|PEHD|PVC|LDPE|PELD|PP|PS|OTHER)\b|\b(PETE|PET|HDPE|PEHD|PVC|LDPE|PELD|PP|PS)(?:\s*[-\/#]\s*|\s+)([1-7])\b/#
        let bare = #/\b(PETE|PET|HDPE|PEHD|PVC|LDPE|PELD|PP|PS)\b/#
        for line in lines {
            for scalar in line.unicodeScalars where (0x2673...0x2679).contains(scalar.value) {
                codes.append(Int(scalar.value) - 0x2672)
            }
            var matchedNumbered = false
            for match in line.matches(of: numbered) {
                if let digit = match.output.1 ?? match.output.4, let code = Int(digit) {
                    codes.append(code)
                    matchedNumbered = true
                }
            }
            if !matchedNumbered {
                codes += line.matches(of: bare).compactMap { resinAbbreviations[String($0.output.1)] }
            }
        }
        return unique(codes)
    }

    // MARK: - Helpers

    static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }
}

private extension Character {
    nonisolated var isASCIIDigit: Bool { isASCII && isNumber }
}
