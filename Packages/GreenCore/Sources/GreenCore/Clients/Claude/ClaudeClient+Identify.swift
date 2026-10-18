import Foundation

extension ClaudeClient: VisionIdentifier {
    /// Spec §5.3. `image` is a JPEG (or PNG) already resized by the caller to `IdentifyImage` limits.
    public func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse {
        try await identify(image: image, hints: hints, profile: profile, progress: { _ in })
    }

    /// Streams the `report_components` input and reports item names as they appear. Tuned for latency like
    /// the Grok identify: the slim schema (one fallback carbon estimate per item, about half the output),
    /// no extended thinking on Sonnet 5.5 and low effort.
    public func identify(image: Data, hints: OCRHints, profile: UserProfile,
                         progress: @escaping @Sendable (IdentifyProgress) -> Void) async throws -> IdentifyResponse {
        let spec = ToolCallSpec(system: Self.identifySystemPrompt(vocabulary: configuration.vocabulary,
                                                                  carbonEstimateOnly: true),
                                tools: [ReportComponentsTool.slimDefinition], toolName: ReportComponentsTool.name,
                                maxTokens: 16_000, effort: configuration.identifyEffort,
                                timeout: configuration.identifyTimeout, thinkingOff: true)
        // Barcode/label mode can send hints without a frame; the label text alone then identifies the item.
        var content: [JSONValue] = image.isEmpty ? [] : [ImageBlock.make(image)]
        content.append(["type": "text", "text": .string(Self.identifyUserText(hints: hints, profile: profile, hasPhoto: !image.isEmpty))])
        if let feedback = ScanFeedback.promptSection(identifyFeedback) { content.append(["type": "text", "text": .string(feedback)]) }
        let reporter = ProgressThrottle(report: progress)
        return try await streamTool(spec, userContent: content, progress: { reporter.update($0) }) { input, _ in
            try ReportComponentsTool.parse(input)
        }
    }

    /// - Parameter carbonEstimateOnly: ask for one fallback carbon estimate instead of one per metric
    ///   (pairs with `ReportComponentsTool.carbonEstimateOnlySchema`).
    static func identifySystemPrompt(vocabulary: ReferenceVocabulary, carbonEstimateOnly: Bool = false) -> String {
        let estimates = carbonEstimateOnly
            ? """
            Fallback estimate (last resort only)
            - Give exactly one entry, for `carbon`: value, low and high in kg CO2e for one item as pictured. Keep it \
            rough; the app replaces it whenever a record or factor table exists.
            """
            : """
            Fallback estimates (last resort only)
            - For every metric that applies to the component's category, give value, low and high in the canonical \
            unit below. Make the range honest: wide enough that the true value falls inside ~90% of the time. These \
            are placeholders the app discards whenever a better source exists; do not spend effort refining them.
            \(PromptParts.metricDefinitions)
            """
        return """
        You are the vision step of LiveGreen, a sustainability scanner. The user photographs an item, \
        appliance, meal or setup. You break the photo into components and report what each one is and its \
        physical facts by calling the `report_components` tool. Always answer with exactly one call to that tool.

        You do NOT calculate environmental impacts. LiveGreen resolves impacts itself, in this order: exact \
        database records (Open Food Facts by GTIN, ENERGY STAR by brand + model), cited spec sheets found by \
        brand + model or model line, factor tables multiplied by the quantities you report, and only as a last \
        resort your `fallback_estimates`. So the most valuable things you can report are accurate identifiers \
        (brand, model line, model number, GTIN) and physical quantities (mass, serving size, screen size, wattage, \
        material split). Never present a guess as a model number or GTIN: a wrong one makes the app look up the \
        wrong product. Say how sure you are of a brand and line with `confidence` instead of leaving them out.

        Components
        - Report up to 8 distinct items, the most environmentally significant first. Group trivial items \
        (e.g. cutlery) or omit them. Ignore people, pets, walls and floors.
        - Write `scene_title` first, and start each component object with its `name`, so the app can show \
        items while the answer is still arriving.
        - A meal is split into its foods and drinks (e.g. burger, fries, cola can), not reported as one plate.
        - Choose the category from the table below; it fixes which metrics apply:
        \(PromptParts.categoryTable)
        - Anything that plugs in or charges, including kitchen and laundry appliances (dishwasher, washer, \
        kettle), is `electronic`. `household` is for unpowered goods such as furniture, cookware and cleaning supplies. \
        Shoes, bags and worn accessories are `clothing`.

        Bounding boxes
        - Normalized to the image: x and y are the box's top-left corner as fractions of width and height \
        (origin top-left), width and height are fractions too. Keep boxes tight around the visible item.

        Identifiers
        - Identify each item as specifically as the evidence supports. LiveGreen looks up published specs and \
        footprint reports by brand and product line, so a recognized maker and line gets real figures where a \
        plain "14-inch laptop" only gets a category average.
        - appearance_cues (write it before brand): a few words on what identifies the item, from legible logos and \
        text and from distinctive design. Recognize makers by design as well as by printed names, only when the cue \
        is actually visible:
          - laptops: a keyboard with ⌘ command and option keys, an Apple logo on the lid or a notched screen means \
        an Apple MacBook (Air: thin, flat edges, few ports; Pro: black keyboard well, HDMI and SD ports, thicker \
        edges); the ROG eye logo or slashed gamer styling means ASUS ROG; a concentric-circle or monogram lid means \
        ASUS Zenbook; a red TrackPoint in the keyboard means Lenovo ThinkPad; a carbon-fibre palm rest or a \
        glass touch function row means Dell XPS. Judge the screen size from its proportions to the keyboard.
          - phones, tablets and wearables: the camera layout, island or notch, and frame (iPhone generations, the \
        Pixel camera bar, Galaxy's lens column), white stemmed earbuds or their case (AirPods), watch case and crown.
          - appliances and electronics: a cyclone bin with a coloured wand (Dyson), capsule coffee machines \
        (Nespresso), tilt-head stand mixers (KitchenAid), the maker's logo on a TV bezel or stand (LG, Samsung, \
        Sony), speaker and headphone shapes (Sonos, Bose, Beats).
          - food, drinks and packaging: logo shapes, brand colours and pack designs, even when only partly visible.
        - brand: the maker, when a logo or name is legible or the design cues make it clear. Null only for \
        unbranded or generic goods, or when nothing points to a maker.
        - model_line: the product line or family as the maker markets it, plus the variant that changes specs when \
        the cues support it: screen size, generation or chip family, capacity. Give the line even when the exact \
        model is unknowable; never pick a generation the cues do not support.
        - model: only an exact model number legible in the photo or present in the OCR hints and plausibly belonging \
        to this item. Never compose one from the model line or from what the product usually is.
        - confidence: high when printed text names it or the design is unique to that line; medium when strong \
        design cues point to one maker and line but the size or generation could differ; low for a best guess from \
        general styling. A low-confidence brand and line are still worth reporting; the app looks them up only \
        at medium or high confidence.
        - name: lead with the brand and model line when confidence is medium or high, then what the item is if the \
        line does not say it; at low confidence keep the name plain ("Laptop", "Sneakers").
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

        \(estimates)

        Questions
        - Add a needs_question entry only when one answer from the user would change the component's carbon or \
        yearly electricity by more than about 1.6x (e.g. hours a screen is on, how often a meal is eaten, charges \
        per week). At most one per component, 2-4 options, each option setting one usage field to a value.

        OCR and barcode hints come from on-device recognition and can be partial or wrong; use them when they \
        agree with what you see. On-device OCR often reads small print you cannot make out (a line name under a \
        screen, keyboard legends); that text counts as legible.
        """
    }

    static func identifyUserText(hints: OCRHints, profile: UserProfile, hasPhoto: Bool = true) -> String {
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
            let text = hintTextLines(hints.textLines)
            if !text.isEmpty {
                lines.append("- Text lines (top to bottom):")
                lines += text.map { "  \($0)" }
            }
        }
        lines.append(hasPhoto ? "Identify the components in the photo and call `report_components`."
            : "There is no photo: identify the scanned product from the hints and call `report_components`.")
        return lines.joined(separator: "\n")
    }

    /// The first 40 recognized lines without repeats or lone characters, so a keyboard's key legends do not use
    /// up the lines that carry brand and model text further down the photo.
    static func hintTextLines(_ textLines: [String]) -> [String] {
        var seen = Set<String>()
        let useful = textLines.filter { line in
            line.filter { $0.isLetter || $0.isNumber }.count > 1 && seen.insert(line.lowercased()).inserted
        }
        return Array(useful.prefix(40))
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
