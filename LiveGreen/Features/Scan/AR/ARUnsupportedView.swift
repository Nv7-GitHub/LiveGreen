import SwiftUI

/// Shown when world tracking is unavailable (e.g. the Simulator), offering to fall back to photo mode.
struct ARUnsupportedView: View {
    let onSwitchToPhoto: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.moss, .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("AR isn't available here", systemImage: "arkit")
                        .font(.headline)
                    Text("AR labels need a device with ARKit world tracking. Photo mode gives you the same results with tappable boxes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Switch to Photo mode", systemImage: "camera", action: onSwitchToPhoto)
                        .buttonStyle(.glassProminent)
                }
            }
            .padding(24)
        }
    }
}

#Preview {
    ARUnsupportedView {}
}
