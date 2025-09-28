import SwiftUI

struct SearchView: View {
    @State private var query: String = ""
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var result: DrugPayload?

    @State private var fetchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    TextField("Search medication (e.g., Augmentin, Panadol…)", text: $query)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onChange(of: query) { _, new in
                            scheduleLookup(for: new)
                        }

                    if isLoading {
                        ProgressView().frame(width: 20, height: 20)
                    }
                }
                .padding(.horizontal)

                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Initial empty state
                    VStack(spacing: 12) {
                        Image(systemName: "pills.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)
                        Text("Search for a medicine to see details")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if let err = errorText {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .padding(.horizontal)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let r = result {
                                Text(r.title.isEmpty ? query : r.title)
                                    .font(.title2).bold()
                                    .padding(.horizontal)

                                if !r.strengths.isEmpty {
                                    SectionHeader("Strengths")
                                    WrapChips(items: r.strengths)
                                }

                                if r.foodRule != nil || r.minIntervalHours != nil {
                                    SectionHeader("Rules")
                                    VStack(alignment: .leading, spacing: 6) {
                                        if let fr = r.foodRule { Text("Food: \(fr)") }
                                        if let ih = r.minIntervalHours { Text("Min interval: \(ih)h") }
                                    }
                                    .padding(.horizontal)
                                }

                                if !r.howToTake.isEmpty {
                                    SectionHeader("How to take")
                                    BulletList(r.howToTake)
                                }

                                if !r.indications.isEmpty {
                                    SectionHeader("What it’s for")
                                    BulletList(r.indications)
                                }

                                if !r.interactionsToAvoid.isEmpty {
                                    SectionHeader("Don’t mix with")
                                    BulletList(r.interactionsToAvoid)
                                }

                                if !r.commonSideEffects.isEmpty {
                                    SectionHeader("Common side effects")
                                    BulletList(r.commonSideEffects)
                                }
                            } else if !isLoading {
                                ContentUnavailableView(
                                    "No results",
                                    systemImage: "magnifyingglass",
                                    description: Text("Try a different spelling or a brand/generic name.")
                                )
                                .padding(.top, 24)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Search")
        }
    }

    private func scheduleLookup(for input: String) {
        fetchTask?.cancel()
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            result = nil; errorText = nil; isLoading = false
            return
        }
        fetchTask = Task { [trimmed] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            await lookup(trimmed)
        }
    }

    @MainActor
    private func lookup(_ term: String) async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let payload = try await DrugInfo.fetchDetails(name: term)
            result = payload

            // 👇 Save to global catalog
            Task.detached {
                do {
                    _ = try await MedCatalogRepo.shared.upsert(from: payload, searchedName: term, imageURL: nil)
                } catch {
                    print("⚠️ MedCatalog upsert failed:", error.localizedDescription)
                }
            }
        } catch {
            errorText = "Couldn’t fetch drug info. \(error.localizedDescription)"
            result = nil
        }
    }
}

// MARK: - Helpers (same as before)

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View { Text(title).font(.headline).padding(.horizontal) }
}

private struct BulletList: View {
    let items: [String]
    init(_ items: [String]) { self.items = items }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items.prefix(12), id: \.self) { t in
                HStack(alignment: .top, spacing: 8) { Text("•").bold(); Text(t) }
            }
        }
        .padding(.horizontal)
    }
}

private struct WrapChips: View {
    let items: [String]
    var body: some View {
        FlexibleWrap(items: items) { text in
            Text(text)
                .font(.footnote)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
        .padding(.horizontal)
    }
}

private struct FlexibleWrap<Content: View>: View {
    let items: [String]; let content: (String) -> Content
    @State private var totalHeight = CGFloat.zero
    var body: some View {
        VStack { GeometryReader { geo in self.generateContent(in: geo) } }
            .frame(height: totalHeight)
    }
    private func generateContent(in g: GeometryProxy) -> some View {
        var width = CGFloat.zero; var height = CGFloat.zero
        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item)
                    .alignmentGuide(.leading) { d in
                        if (abs(width - d.width) > g.size.width) { width = 0; height -= d.height }
                        let res = width; if item == items.last! { width = 0 } else { width -= d.width }; return res
                    }
                    .alignmentGuide(.top) { _ in let res = height; if item == items.last! { height = 0 }; return res }
            }
        }.background(viewHeightReader($totalHeight))
    }
    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        GeometryReader { geo -> Color in
            DispatchQueue.main.async { binding.wrappedValue = geo.size.height }; return .clear
        }
    }
}
