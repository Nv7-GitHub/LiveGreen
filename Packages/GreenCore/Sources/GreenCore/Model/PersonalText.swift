import Foundation

/// Finds personal details in text read from a photo (spec §6): phone numbers, email addresses, street addresses and
/// labelled fields such as "Name:" on a notebook's sticker, so the results photo can blur them before anyone watching
/// reads them. It leans towards blurring: hiding a stray line of small print costs nothing.
public enum PersonalText {
    /// Indices of `lines` (top to bottom, in reading order) that hold personal details.
    public static func sensitiveLines(_ lines: [String]) -> Set<Int> {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue
                                                | NSTextCheckingResult.CheckingType.address.rawValue)
        var sensitive = Set<Int>()
        var addresses = Set<Int>()
        for (index, line) in lines.enumerated() {
            let matches = detector?.matches(in: line, range: NSRange(line.startIndex..., in: line)) ?? []
            if isAddress(line) || matches.contains(where: { $0.resultType == .address }) {
                addresses.insert(index)
                sensitive.insert(index)
            }
            if hasEmail(line) || matches.contains(where: { isPhone($0, in: line) }) {
                sensitive.insert(index)
            }
            if let value = labelledValue(line) {
                sensitive.insert(index)
                // A label alone on its line ("NAME") labels the next one.
                if value.isEmpty, index + 1 < lines.count { sensitive.insert(index + 1) }
            }
        }
        // A short line of capitalized words just above an address is most likely the name it belongs to.
        for index in addresses where index > 0 && looksLikeName(lines[index - 1]) {
            sensitive.insert(index - 1)
        }
        return sensitive
    }

    /// Words that label a personal field on a sticker, tag or form.
    static let labels = ["name", "owner", "address", "addr", "phone", "tel", "telephone", "mobile", "cell", "email",
                         "e-mail", "contact", "if found", "property of", "belongs to", "return to"]

    /// The text after a leading label ("Name: Alex" → "Alex"), or nil when the line does not start with one.
    static func labelledValue(_ line: String) -> String? {
        let pattern = "^\\s*(?:\(labels.joined(separator: "|")))\\b\\s*[:#.\\-]?\\s*"
        guard let range = line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return line[range.upperBound...].trimmingCharacters(in: .whitespaces)
    }

    static func hasEmail(_ line: String) -> Bool {
        line.range(of: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// A street line ("42 Elm Street", "P.O. Box 7") or a city line with a state and ZIP ("Boston, MA 02115").
    static func isAddress(_ line: String) -> Bool {
        let street = "\\b\\d{1,6}\\s+(?:[A-Za-z0-9.'-]+\\s+){0,4}(?:street|st|avenue|ave|road|rd|boulevard|blvd|"
            + "drive|dr|lane|ln|court|ct|way|place|pl|terrace|ter|circle|cir|parkway|pkwy|highway|hwy|square|sq)\\b"
        let poBox = "\\bP\\.?\\s?O\\.?\\s+Box\\s+\\d+"
        let cityStateZip = "\\b[A-Za-z][A-Za-z .'-]*,?\\s+[A-Z]{2}\\s+\\d{5}(?:-\\d{4})?\\b"
        return line.range(of: street, options: [.regularExpression, .caseInsensitive]) != nil
            || line.range(of: poBox, options: [.regularExpression, .caseInsensitive]) != nil
            || line.range(of: cityStateZip, options: .regularExpression) != nil
    }

    /// A phone number with at least 7 digits. A bare run of 8, 12, 13 or 14 digits is a barcode number, not a phone.
    static func isPhone(_ match: NSTextCheckingResult, in line: String) -> Bool {
        guard match.resultType == .phoneNumber, let range = Range(match.range, in: line) else { return false }
        let text = line[range]
        let digits = text.filter(\.isNumber)
        if digits.count == text.count, [8, 12, 13, 14].contains(digits.count) { return false }
        return digits.count >= 7
    }

    /// Two to four capitalized words of letters only, like "Alex Rivera".
    static func looksLikeName(_ line: String) -> Bool {
        let words = line.split(separator: " ")
        guard (2...4).contains(words.count), line.count <= 40 else { return false }
        return words.allSatisfy { word in
            guard let first = word.first, first.isUppercase else { return false }
            return word.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" || $0 == "." }
        }
    }
}
