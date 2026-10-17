import SwiftUI

/// Glass segmented control for the results metric (spec §6). Every option fits on one row: unselected
/// options show their icon, and the selected one expands to show its name.
struct MetricPicker: View {
    @Binding var selection: ResultMetricFilter
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ResultMetricFilter.allCases) { filter in
                segment(filter)
            }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Metric")
    }

    private func segment(_ filter: ResultMetricFilter) -> some View {
        let isSelected = filter == selection
        return Button {
            withAnimation(.snappy) { selection = filter }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.systemImage)
                if isSelected {
                    Text(filter.title).lineLimit(1).fixedSize()
                }
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .white : .primary)
            .frame(maxWidth: isSelected ? nil : .infinity)
            .padding(.horizontal, isSelected ? 14 : 0)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.leaf.gradient)
                        .matchedGeometryEffect(id: "selection", in: indicator)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("metric.\(filter.rawValue)")
    }
}

#Preview {
    @Previewable @State var filter = ResultMetricFilter.carbon
    MetricPicker(selection: $filter).padding()
}
