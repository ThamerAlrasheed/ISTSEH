import SwiftUI

struct SearchView: View {
    @State private var query: String = ""
    @State private var isSearching: Bool = false
    @State private var errorText: String? = nil

    /// A single validated result (we only show rows that came from the API).
    @State private var validatedResult: String? = nil

    /// Debounce + stale-response protection
    @State private var debounceTask: Task<Void, Never>? = nil
    @State private var latestToken: UUID = UUID()
    @State private var lastSearchedText: String = ""

    var body: some View {
        NavigationStack {
            List {
                // Search box
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        TextField("Search medicine name", text: $query)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .onChange(of: query) { _, newValue in
                                scheduleDebouncedAPI(for: newValue)
                            }
                            .submitLabel(.search)
                            .onSubmit { Task { await runSearch(force: true) } }

                        if !query.isEmpty {
                            Button {
                                query = ""
                                resetState()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // STATES
                if isSearching {
                    Section { HStack { ProgressView(); Text("Searching…") } }
                } else if let err = errorText {
                    Section {
                        ContentUnavailableView("Couldn't search",
                                              systemImage: "exclamationmark.triangle",
                                              description: Text(err))
                    }
                } else if let result = validatedResult {
                    // We only show a row if we *already* validated it with the API
                    Section(header: Text("Results")) {
                        NavigationLink {
                            // Pass the same label to show on top; details will still prefer the
                            // API’s canonical title if it’s clean (fallback = this label).
                            MedDetailView(medName: result, displayTitle: result)
                        } label: {
                            Text(result)
                        }
                    }
                } else {
                    // No validated result for the current text
                    Section {
                        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty || trimmed.count < 3 {
                            ContentUnavailableView("Start typing to search",
                                                  systemImage: "magnifyingglass",
                                                  description: Text("Type at least 3 characters."))
                        } else {
                            ContentUnavailableView("No results for “\(trimmed)”",
                                                  systemImage: "doc.text.magnifyingglass",
                                                  description: Text("Try a different spelling or use a brand/generic name."))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Search") { Task { await runSearch(force: true) } }
                        .disabled(query.trimmingCharacters(in: .whitespaces).count < 3)
                }
            }
        }
    }

    // MARK: - Debounce & API

    private func scheduleDebouncedAPI(for text: String) {
        debounceTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= 3 else {
            // Reset UI to idle when input is too short
            resetState()
            return
        }

        // Avoid hammering API on the same string repeatedly
        if trimmed.caseInsensitiveCompare(lastSearchedText) == .orderedSame { return }

        debounceTask = Task { [trimmed] in
            try? await Task.sleep(nanoseconds: 450_000_000) // ~450ms
            await runSearch(force: false, queryOverride: trimmed)
        }
    }

    /// Calls the API once for the given query. If the API returns data, we show exactly one result row.
    /// If it returns nil, we show "No results" (no fake clickable items).
    private func runSearch(force: Bool, queryOverride: String? = nil) async {
        let q = (queryOverride ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { return }
        if !force, q.caseInsensitiveCompare(lastSearchedText) == .orderedSame { return }

        let token = UUID()
        latestToken = token
        await MainActor.run {
            isSearching = true
            errorText = nil
            validatedResult = nil
        }

        do {
            // We validate by actually fetching details from your service layer.
            if let details = try await OpenFDAService.fetchDetails(forName: q) {
                // Use API’s canonical title if it looks good; fallback to the query that worked.
                let apiTitle = details.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let display = cleanTitle(apiTitle) ?? q

                // Only apply if this is the latest outstanding request
                guard token == latestToken else { return }
                await MainActor.run {
                    self.validatedResult = display
                    self.isSearching = false
                    self.lastSearchedText = q
                }
            } else {
                // Only apply if latest
                guard token == latestToken else { return }
                await MainActor.run {
                    self.validatedResult = nil   // -> No results section shows
                    self.isSearching = false
                    self.lastSearchedText = q
                }
            }
        } catch {
            guard token == latestToken else { return }
            await MainActor.run {
                self.errorText = "Search failed. Please try again."
                self.isSearching = false
                self.validatedResult = nil
            }
        }
    }

    private func resetState() {
        isSearching = false
        errorText = nil
        validatedResult = nil
        lastSearchedText = ""
        latestToken = UUID()
    }

    /// Simple sanity filter for titles; returns nil for obviously bogus header strings.
    private func cleanTitle(_ t: String) -> String? {
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return nil }
        // Approve titles that look like normal drug names (reject all-caps headers etc.)
        if trimmed.range(of: #"^[A-Z][A-Za-z0-9 ()\-/.,]+$"#, options: .regularExpression) == nil {
            return nil
        }
        return trimmed
    }
}
