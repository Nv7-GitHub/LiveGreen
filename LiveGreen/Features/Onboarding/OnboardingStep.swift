/// The questions of the onboarding questionnaire, in order (spec §9).
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case location, household, diet, commute, home, clothing, chargers

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .location: "Where do you live?"
        case .household: "Who's in your household?"
        case .diet: "How do you eat?"
        case .commute: "How do you get around?"
        case .home: "What's home like?"
        case .clothing: "How do you shop for clothes?"
        case .chargers: "What do you charge?"
        }
    }

    var subtitle: String {
        switch self {
        case .location: "Sets your electricity grid and the per-capita baseline you're compared with."
        case .household: "Shared homes split their energy and appliance footprint."
        case .diet: "Diet shifts the food footprint of people like you."
        case .commute: "Your typical weekly commute."
        case .home: "Home type and heating shape your energy baseline."
        case .clothing: "New versus second-hand clothing."
        case .chargers: "Loads like these can charge when the grid is cleanest with a smart plug."
        }
    }

    var symbol: String {
        switch self {
        case .location: "map"
        case .household: "person.2"
        case .diet: "fork.knife"
        case .commute: "figure.walk.motion"
        case .home: "house"
        case .clothing: "tshirt"
        case .chargers: "powerplug"
        }
    }
}
