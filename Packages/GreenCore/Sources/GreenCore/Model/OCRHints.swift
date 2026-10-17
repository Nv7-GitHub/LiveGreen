/// On-device Vision pre-pass output (spec §5.2), passed to Claude as hints and used as identifiers.
public struct OCRHints: Codable, Sendable, Hashable {
    public var gtins: [String]
    public var modelNumbers: [String]
    public var wattages: [Double]
    public var fiberPercentages: [MaterialShare]
    /// Resin identification codes 1–7.
    public var resinCodes: [Int]
    /// Recognized text lines, top to bottom.
    public var textLines: [String]

    public init(gtins: [String] = [], modelNumbers: [String] = [], wattages: [Double] = [],
                fiberPercentages: [MaterialShare] = [], resinCodes: [Int] = [], textLines: [String] = []) {
        self.gtins = gtins
        self.modelNumbers = modelNumbers
        self.wattages = wattages
        self.fiberPercentages = fiberPercentages
        self.resinCodes = resinCodes
        self.textLines = textLines
    }

    public static let none = OCRHints()

    public var isEmpty: Bool {
        gtins.isEmpty && modelNumbers.isEmpty && wattages.isEmpty && fiberPercentages.isEmpty
            && resinCodes.isEmpty && textLines.isEmpty
    }
}
