import SwiftUI

/// A grid of glass chips for picking one option.
struct SingleChoiceChips<Option: ProfileOption>: View {
    @Binding var selection: Option

    var body: some View {
        ChipGrid(options: Array(Option.allCases), isSelected: { $0 == selection }, toggle: { selection = $0 })
    }
}

/// A grid of glass chips for picking any number of options.
struct MultiChoiceChips<Option: ProfileOption>: View {
    @Binding var selection: Set<Option>

    var body: some View {
        ChipGrid(options: Array(Option.allCases), isSelected: { selection.contains($0) }) { option in
            if selection.contains(option) { selection.remove(option) } else { selection.insert(option) }
        }
    }
}

private struct ChipGrid<Option: ProfileOption>: View {
    let options: [Option]
    let isSelected: (Option) -> Bool
    let toggle: (Option) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(options, id: \.self) { option in
                    chip(option)
                }
            }
        }
    }

    private func chip(_ option: Option) -> some View {
        let selected = isSelected(option)
        return Button {
            withAnimation(.snappy) { toggle(option) }
        } label: {
            Label(option.profileLabel, systemImage: option.profileSymbol)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? .white : .primary)
                // Glass is drawn, not hit-tested: without a content shape only the text and icon took taps.
                .contentShape([.interaction, .accessibility], .rect(cornerRadius: Self.cornerRadius))
                .glassEffect(.regular.tint(selected ? Theme.leaf : nil).interactive(),
                             in: .rect(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private static var cornerRadius: CGFloat { 16 }
}
