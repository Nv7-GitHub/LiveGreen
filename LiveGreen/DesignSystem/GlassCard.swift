import SwiftUI

/// Rounded Liquid Glass card used for floating panels and onboarding cards.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = Theme.cardCornerRadius
    var tint: Color?
    var interactive = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(Glass.regular.tint(tint).interactive(interactive), in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    /// Applies the standard LiveGreen glass background in a rounded rectangle.
    func glassCard(cornerRadius: CGFloat = Theme.cardCornerRadius, tint: Color? = nil, interactive: Bool = false) -> some View {
        padding()
            .glassEffect(Glass.regular.tint(tint).interactive(interactive), in: .rect(cornerRadius: cornerRadius))
    }
}
