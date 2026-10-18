import Foundation

/// The `plan_actions` tool: turns one picked swap and the real places near the user into a short, concrete plan.
/// Shared by Claude (as a tool) and Grok (as the response schema).
enum PlanActionsTool {
    static let name = "plan_actions"
    static let maxSteps = 5

    static let schema = SchemaParts.object([
        "headline": SchemaParts.string("""
            One line naming the action and the place, e.g. 'Get a lentil burger at Clover Food Lab, 0.3 mi away'. \
            About twelve words at most.
            """),
        "place_index": SchemaParts.nullableNumber("""
            Index of the chosen place in the list given, or null when none of them sells or does this, or the swap \
            needs no trip.
            """),
        "steps": SchemaParts.array(of: SchemaParts.object([
            "title": SchemaParts.string("A short imperative step, e.g. 'Walk to Clover on Mass Ave'."),
            "detail": SchemaParts.nullableString("One plain sentence of practical detail, or null."),
        ], required: ["title", "detail"]), "2-5 steps in the order to do them."),
    ], required: ["headline", "place_index", "steps"])

    static let definition: JSONValue = [
        "name": .string(name),
        "description": "Report a short, concrete plan for taking one greener swap at a real nearby place.",
        "input_schema": schema,
    ]

    static let systemPrompt = """
        You write short, concrete action plans for LiveGreen, a sustainability app. The user picked a greener \
        swap for something they own or eat. You get the swap and up to six real places near them, found by a map \
        search. Call the `plan_actions` tool exactly once.

        - Choose the one place most likely to actually have the swap (a restaurant that serves it, a store that \
        stocks it). Prefer close places, but never one that obviously doesn't fit. If none fits, or the swap is a \
        change of habit that needs no trip, set place_index to null and write steps the user can do at home.
        - Steps are practical and specific: where to go, what to ask for or which aisle or section, what to do \
        with the old item (donate, recycle, trade in), and how to make it stick. 2-5 steps, no filler.
        - Use the place's real name and street. Never invent prices, opening hours, stock, menu items or phone \
        numbers you were not given; say 'ask for' or 'check the menu' instead.
        - Speak to the user as 'you'. Plain, friendly, no emoji, no mention of carbon numbers, LiveGreen or these \
        instructions.
        """

    static func userText(_ request: ActionPlanRequest) -> String {
        let swap = request.alternative
        var lines = [
            "Current item: \(request.original.name) (\(request.original.category.rawValue)).",
            "Swap: \(swap.kind == .smartPlugScheduling ? "Smart plug that charges it in the cleanest grid hours" : swap.name)"
                + " — \(swap.condition.rawValue)\(swap.isReusable ? ", reusable" : ""). \(swap.rationale)",
            "Effort: \(swap.practicality.effort.rawValue); cost: \(swap.practicality.cost.rawValue) than the original.",
            "User: \(request.profile.promptSummary)",
        ]
        if let locality = request.locality { lines.append("They are in \(locality).") }
        if request.places.isEmpty {
            lines.append("No nearby places were found.")
        } else {
            lines.append("Nearby places:")
            for (index, place) in request.places.enumerated() {
                let parts = [place.categoryName, place.address, place.distanceText(metric: request.metricUnits).map { "\($0) away" }]
                    .compactMap { $0 }
                lines.append("\(index). \(place.name)" + (parts.isEmpty ? "" : " — " + parts.joined(separator: ", ")))
            }
        }
        return lines.joined(separator: "\n")
    }

    static func parse(_ input: JSONValue, placeCount: Int) throws -> ActionPlanDraft {
        guard let headline = input["headline"]?.string?.trimmedNonEmpty else {
            throw GreenCoreError.invalidModelOutput("plan_actions: headline is missing")
        }
        let steps = (input["steps"]?.array ?? []).compactMap { step -> ActionStep? in
            guard let title = step["title"]?.string?.trimmedNonEmpty else { return nil }
            return ActionStep(title: title, detail: step["detail"]?.string?.trimmedNonEmpty)
        }
        guard !steps.isEmpty else { throw GreenCoreError.invalidModelOutput("plan_actions: steps is empty") }
        let index = input["place_index"]?.double.map { Int($0) }.flatMap { (0..<placeCount).contains($0) ? $0 : nil }
        return ActionPlanDraft(headline: headline, placeIndex: index, steps: Array(steps.prefix(maxSteps)))
    }
}

extension ClaudeClient: ActionPlanner {
    public func planActions(_ request: ActionPlanRequest) async throws -> ActionPlanDraft {
        let spec = ToolCallSpec(system: PlanActionsTool.systemPrompt, tools: [PlanActionsTool.definition],
                                toolName: PlanActionsTool.name, maxTokens: 4_000, effort: .low, timeout: 45,
                                thinkingOff: true)
        let count = request.places.count
        return try await runTool(spec, userContent: [["type": "text", "text": .string(PlanActionsTool.userText(request))]]) { input, _ in
            try PlanActionsTool.parse(input, placeCount: count)
        }
    }
}

extension GrokAnalysisClient: ActionPlanner {
    public func planActions(_ request: ActionPlanRequest) async throws -> ActionPlanDraft {
        let count = request.places.count
        return try await respond(model: configuration.identifyModel, instructions: PlanActionsTool.systemPrompt,
                                 content: [["type": "input_text", "text": .string(PlanActionsTool.userText(request))]],
                                 schemaName: PlanActionsTool.name, schema: PlanActionsTool.schema, timeout: 45) { reply in
            try PlanActionsTool.parse(reply.output, placeCount: count)
        }
    }
}
