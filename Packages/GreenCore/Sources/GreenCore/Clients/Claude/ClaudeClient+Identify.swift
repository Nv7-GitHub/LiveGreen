import Foundation

extension ClaudeClient: VisionIdentifier {
    /// Spec §5.3. `image` is a JPEG (or PNG) already resized by the caller (long edge ≤ 1568 px).
    public func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse {
        let spec = ToolCallSpec(system: Self.identifySystemPrompt(vocabulary: configuration.vocabulary),
                                tools: [ReportComponentsTool.definition], toolName: ReportComponentsTool.name,
                                maxTokens: 16_000, effort: configuration.identifyEffort,
                                timeout: configuration.identifyTimeout)
        // Barcode/label mode can send hints without a frame; the label text alone then identifies the item.
        var content: [JSONValue] = image.isEmpty ? [] : [ImageBlock.make(image)]
        content.append(["type": "text", "text": .string(Self.identifyUserText(hints: hints, profile: profile))])
        return try await runTool(spec, userContent: content) { input, _ in try ReportComponentsTool.parse(input) }
    }

    static func identifySystemPrompt(vocabulary: ReferenceVocabulary) -> String {
        """
        You are the vision step of LiveGreen, a sustainability scanner. The user photographs an item, \
        appliance, meal or setup. You break the photo into components and report what each one is and its \
        physical facts by calling the `report_components` tool. Always answer with exactly one call to that tool.

        You do NOT calculate environmental impacts. LiveGreen resolves impacts itself, in this order: exact \
        database records (Open Food Facts by GTIN, ENERGY STAR by brand + model), cited spec sheets, factor \
        tables multiplied by the quantities you report, and only as a last resort your `fallback_estimates`. \
        So the most valuable things you can report are accurate identifiers (brand, model number, GTIN) and \
        physical quantities (mass, serving size, screen size, wattage, material split). Never present a guess \
        as an identifier: a wrong model number makes the app look up the wrong product.

        Components
        - Report up to 8 distinct items, the most environmentally significant first. Group trivial items \
        (e.g. cutlery) or omit them. Ignore people, pets, walls and floors.
        - A meal is split into its foods and drinks (e.g. burger, fries, cola can), not reported as one plate.
        - Choose the category from the table below; it fixes which metrics apply:
        \(PromptParts.categoryTable)
        - Anything that plugs in or charges, including kitchen and laundry appliances (dishwasher, washer, \
        kettle), is `electronic`. `household` is for unpowered goods such as furniture, cookware and cleaning supplies.

        Bounding boxes
        - Normalized to the image: x and y are the box's top-left corner as fractions of width and height \
        (origin top-left), width and height are fractions too. Keep boxes tight around the visible item.

        Identifiers
        - brand: only when a logo, label or unmistakable design shows it. model: only when legible in the photo \
        or present in the OCR hints and plausibly belonging to this item. Otherwise null.
        - gtin: assign a barcode hint to the item it is printed on (if there is a single packaged product, it is \
        that product). Never fabricate digits.
        - materials: the mass split of the item itself (fiber percentages from a care label are exact; otherwise \
        estimate typical construction, e.g. a paper cup ≈ 95% paperboard, 5% polyethylene).

        Quantities
        - Estimate from visible size cues and typical products: mass of one unit or of the portion shown, \
        serving size for food, packaging mass, screen diagonal, rated wattage (prefer wattage hints), volume.
        - Set food_group or device_type using the reference keys so LiveGreen's factor tables apply.
        \(PromptParts.vocabularyList(vocabulary))

        Default usage
        - Typical usage for this specific user (see their profile): hours on and in standby per day for \
        electronics, servings per week for food, wears per year for clothing, uses per week for single-use and \
        household items, charges per week for battery devices. Fill only the fields that fit the category.

        Deferrable loads
        - Set deferrable_load when the item is a load whose charging or running could be moved to cleaner-grid \
        hours: \(PromptParts.deferrableLoads). Otherwise null.

        Fallback estimates (last resort only)
        - For every metric that applies to the component's category, give value, low and high in the canonical \
        unit below. Make the range honest: wide enough that the true value falls inside ~90% of the time. These \
        are placeholders the app discards whenever a better source exists; do not spend effort refining them.
        \(PromptParts.metricDefinitions)

        Questions
        - Add a needs_question entry only when one answer from the user would change the component's carbon or \
        yearly electricity by more than about 1.6x (e.g. hours a screen is on, how often a meal is eaten, charges \
        per week). At most one per component, 2-4 options, each option setting one usage field to a value.

        OCR and barcode hints come from on-device recognition and can be partial or wrong; use them when they \
        agree with what you see.
        """
    }

    static func identifyUserText(hints: OCRHints, profile: UserProfile) -> String {
        var lines = ["User profile: \(profile.promptSummary)"]
        if hints.isEmpty {
            lines.append("On-device hints: none.")
        } else {
            lines.append("On-device hints:")
            if !hints.gtins.isEmpty { lines.append("- Barcodes (GTIN): \(hints.gtins.joined(separator: ", "))") }
            if !hints.modelNumbers.isEmpty { lines.append("- Model-number-like tokens: \(hints.modelNumbers.joined(separator: ", "))") }
            if !hints.wattages.isEmpty { lines.append("- Wattages: \(hints.wattages.map { "\(Self.compact($0)) W" }.joined(separator: ", "))") }
            if !hints.fiberPercentages.isEmpty {
                lines.append("- Fiber content: " + hints.fiberPercentages.map { "\(Self.compact($0.percent))% \($0.material)" }
                    .joined(separator: ", "))
            }
            if !hints.resinCodes.isEmpty { lines.append("- Resin codes: \(hints.resinCodes.map(String.init).joined(separator: ", "))") }
            if !hints.textLines.isEmpty {
                lines.append("- Text lines (top to bottom):")
                lines += hints.textLines.prefix(40).map { "  \($0)" }
            }
        }
        lines.append("Identify the components in the photo and call `report_components`.")
        return lines.joined(separator: "\n")
    }

    static func compact(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// Base64 image content block; detects PNG so a non-JPEG input is labeled correctly.
enum ImageBlock {
    static func make(_ data: Data) -> JSONValue {
        [
            "type": "image",
            "source": ["type": "base64", "media_type": .string(mediaType(of: data)), "data": .string(data.base64EncodedString())],
        ]
    }

    static func mediaType(of data: Data) -> String {
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        return data.prefix(4).elementsEqual(png) ? "image/png" : "image/jpeg"
    }
}
