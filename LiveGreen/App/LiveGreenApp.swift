import SwiftUI
import SwiftData

@main
struct LiveGreenApp: App {
    @State private var model: AppModel

    init() {
        let launch = LaunchArguments()
        let container: ModelContainer
        do {
            container = try Persistence.makeContainer(inMemory: launch.inMemoryStore)
        } catch {
            // A corrupt on-disk store should not brick the app; fall back to memory for this session.
            container = try! Persistence.makeContainer(inMemory: true)
        }
        let model = AppModel(container: container, launch: launch)
        _model = State(initialValue: model)
        BackgroundRefresh.register(model: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(model.container)
                .tint(Theme.accent)
        }
    }
}
