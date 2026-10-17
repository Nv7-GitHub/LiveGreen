import Foundation
import GreenCore

extension AppModel {
    /// Scanned components that can be scheduled on a smart plug, newest scan first, one per name.
    var plugCandidateComponents: [Component] {
        var seen = Set<String>()
        return scans.flatMap(\.components).filter { component in
            component.plugCandidate != nil && seen.insert(component.name.lowercased()).inserted
        }
    }

    func scannedComponent(withID id: UUID) -> Component? {
        scans.lazy.compactMap { $0.component(withID: id) }.first
    }
}
