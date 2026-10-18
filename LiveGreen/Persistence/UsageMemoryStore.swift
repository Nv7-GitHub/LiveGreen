import Foundation
import SwiftData
import GreenCore

/// How often the user said they have each kind of item, for the next scans (`ScanPipeline.rememberedUsage`). Written
/// when a usage question is answered or a usage slider is moved; "Erase all data" clears it.
final class UsageMemoryStore {
    /// Rate a week by kind of item.
    private(set) var rates: [String: Double] = [:]
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        let stored = (try? context.fetch(FetchDescriptor<StoredUsageAnswer>())) ?? []
        rates = Dictionary(stored.map { ($0.key, $0.perWeek) }, uniquingKeysWith: { _, latest in latest })
    }

    func remember(_ perWeek: Double, for key: String) throws {
        try context.delete(model: StoredUsageAnswer.self, where: #Predicate { $0.key == key })
        context.insert(StoredUsageAnswer(key: key, perWeek: perWeek))
        try context.save()
        rates[key] = perWeek
    }

    /// Remembers the rates the user gave between `base` and `updated` (`UsageSource.answered`), by kind of item.
    /// Containers that follow their food are left out: the food's rate covers them.
    func remember(answersIn updated: ScanResult, since base: ScanResult, reference: any ReferenceProviding) throws {
        for component in updated.components where component.usage?.source == .answered
            && component.usage != base.component(withID: component.id)?.usage {
            guard let key = UsageDefaults.kindKey(for: component, reference: reference),
                  let perWeek = UsageDefaults.perWeek(of: component) else { continue }
            try remember(perWeek, for: key)
        }
    }

    func deleteAll() throws {
        try context.delete(model: StoredUsageAnswer.self)
        try context.save()
        rates = [:]
    }
}
