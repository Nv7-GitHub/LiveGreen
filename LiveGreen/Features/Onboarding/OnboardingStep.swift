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
        case .clothing: "How often do you buy new clothes?"
        case .chargers: "What do you charge?"
        }
    }

    var subtitle: String {
        switch self {
        case .location: "Your area sets the starting estimate above and how clean your electricity is."
        case .household: "Count everyone you share a home with. Energy and appliances are split between you."
        case .diet: "Of the 21 meals in a typical week, how many have meat or dairy as a main part?"
        case .commute: "Pick any you use in a typical week, or none. Walking and cycling add nothing, so they're left out."
        case .home: "Its type, rough size and heating drive your home energy. Pick every heating source you use."
        case .clothing: "Count new items, not second-hand. Making new clothes is carbon-heavy; second-hand avoids most of it."
        case .chargers: "Things you plug in to charge. A smart plug can charge them when the grid is cleanest."
        }
    }

    var symbol: String {
        switch self {
        case .location: "map"
        case .household: "person.2"
        case .diet: "fork.knife"
        case .commute: "car"
        case .home: "house"
        case .clothing: "tshirt"
        case .chargers: "powerplug"
        }
    }
}
