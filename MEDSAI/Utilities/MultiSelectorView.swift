import SwiftUI

struct MultiSelectorView: View {
    let title: String
    let presets: [String]
    @Binding var selectedItems: [String]
    
    @State private var searchText = ""
    @State private var isShowingPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Tag Cloud
            if !selectedItems.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(selectedItems, id: \.self) { item in
                        TagView(text: item) {
                            withAnimation {
                                selectedItems.removeAll { $0 == item }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Add Button
            Button {
                isShowingPicker = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(selectedItems.isEmpty ? "Tap to add..." : "Add more...")
                    Spacer()
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $isShowingPicker) {
                ItemPickerView(
                    title: title,
                    presets: presets,
                    selectedItems: $selectedItems,
                    searchText: $searchText
                )
            }
        }
    }
}

private struct ItemPickerView: View {
    let title: String
    let presets: [String]
    @Binding var selectedItems: [String]
    @Binding var searchText: String
    @Environment(\.dismiss) private var dismiss
    
    var filteredPresets: [String] {
        if searchText.isEmpty {
            return presets.filter { !selectedItems.contains($0) }
        } else {
            return presets.filter { 
                $0.localizedCaseInsensitiveContains(searchText) && !selectedItems.contains($0)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if !searchText.isEmpty && !presets.contains(where: { $0.localizedCaseInsensitiveCompare(searchText) == .orderedSame }) {
                    Button {
                        addItem(searchText)
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add \"\(searchText)\"")
                            Spacer()
                        }
                        .foregroundStyle(.green)
                    }
                }
                
                ForEach(filteredPresets, id: \.self) { item in
                    Button {
                        addItem(item)
                    } label: {
                        HStack {
                            Text(item)
                            Spacer()
                            if selectedItems.contains(item) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search or type new...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func addItem(_ item: String) {
        let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !selectedItems.contains(trimmed) {
            selectedItems.append(trimmed)
        }
        searchText = ""
    }
}

private struct TagView: View {
    let text: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.subheadline)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.1))
        .foregroundStyle(.green)
        .clipShape(Capsule())
    }
}

// Simple FlowLayout for Tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var totalHeight: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > width {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
        totalHeight = currentY + lineHeight
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
    }
}
