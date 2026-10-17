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
        case .location: "Your area sets the starting estimate above and how clean your electricity is."
        case .household: "Count everyone you share a home with. Energy and appliances are split between you."
        case .diet: "What you usually eat. Food is one of the biggest parts of most footprints."
        case .commute: "Pick every way you get around in a typical week, then set roughly how far."
        case .home: "The size of your home and how it's heated drive your home energy."
        case .clothing: "Making new clothes is carbon-heavy; second-hand avoids most of it."
        case .chargers: "Things you plug in to charge. A smart plug can charge them when the grid is cleanest."
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
