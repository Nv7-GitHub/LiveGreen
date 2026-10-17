import SwiftUI

/// Glass segmented control for the results metric (spec §6). Scrolls horizontally on narrow widths.
struct MetricPicker: View {
    @Binding var selection: ResultMetricFilter
    @Namespace private var indicator

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(ResultMetricFilter.allCases) { filter in
                    segment(filter)
                }
            }
            .padding(4)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Metric")
    }

    private func segment(_ filter: ResultMetricFilter) -> some View {
        let isSelected = filter == selection
        return Button {
            withAnimation(.snappy) { selection = filter }
        } label: {
            Label(filter.title, systemImage: filter.systemImage)
                .labelStyle(.titleAndIcon)
                .font(.footnote.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Theme.leaf.opacity(0.35))
                            .matchedGeometryEffect(id: "selection", in: indicator)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("metric.\(filter.rawValue)")
    }
}

#Preview {
    @Previewable @State var filter = ResultMetricFilter.carbon
    MetricPicker(selection: $filter).padding()
}
