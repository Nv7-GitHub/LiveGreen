import SwiftUI

extension View {
    /// Adds a gear toolbar button that presents `SettingsView` as a sheet.
    func settingsToolbarButton() -> some View {
        modifier(SettingsToolbarButton())
    }
}

private struct SettingsToolbarButton: ViewModifier {
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { isPresented = true }
                }
            }
            .sheet(isPresented: $isPresented) {
                NavigationStack { SettingsView() }
            }
    }
}
