import SwiftUI

struct SearchView: View {
    @State private var query: String = ""
    @State private var isSearching: Bool = false
    @State private var errorText: String? = nil

    // A single validated display name to show as a clickable result
    @State private var validatedResult: String? = nil

    // Explicit "no results" state after a completed lookup
    @State private var noResults: Bool = false

    // Debounce + stale-response protection
    @State private var debounceTask: Task<Void, Never>? = nil
    @State private var latestToken: UUID = UUID()
    @State private var lastSearchedText: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    List {
                        Section { HStack { ProgressView(); Text("Searching…") } }
                    }
                } else if let err = errorText {
                    List {
                        Section {
                            ContentUnavailableView(
                                "Couldn't search",
                                systemImage: "exclamationmark.triangle",
                                description: Text(err)
                            )
                        }
                    }
                } else if let result = validatedResult {
                    // We have a meaningful API-backed result: show one clean, clickable row
                    List {
                        Section(header: Text("Results")) {
                            NavigationLink {
                                // Keep the displayTitle consistent with the result
                                MedDetailView(medName: result, displayTitle: result)
                            } label: {
                                Text(result)
                            }
                        }
                    }
                } else if noResults {
                    // Only show this when the API returns nil/empty for the user’s query
                    List {
                        Section {
                            ContentUnavailableView(
                                "No results found",
                                systemImage: "magnifyingglass",
                                description: Text("Try another name — brand or generic.")
                            )
                        }
                    }
                } else {
                    // Initial / idle state (same clean feel as your old version)
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(.secondary)
                        Text("Search for a medicine")
                            .font(.title3.weight(.semibold))
                        Text("Type a brand or generic name in the search field above.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                    .background(Color(.systemBackground))
                }
            }
            .navigationTitle("Search")
            // Native, clean “type to search” input
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search medicines")
            .onChange(of: query) { _, newValue in
                scheduleDebouncedAPI(for: newValue)
            }
            .onSubmit(of: .search) {
                Task { await runSearch(force: true) }
            }
        }
    }

    // MARK: - Debounce & API

    private func scheduleDebouncedAPI(for text: String) {
        debounceTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Reset to idle if too short
        guard trimmed.count >= 3 else {
            resetState()
            return
        }

        // Avoid re-querying the exact same text
        if trimmed.caseInsensitiveCompare(lastSearchedText) == .orderedSame { return }

        debounceTask = Task { [trimmed] in
            try? await Task.sleep(nanoseconds: 250_000_000) // ~250ms
            await runSearch(force: false, queryOverride: trimmed)
        }
    }

    /// Calls the API for the query. If the API returns *meaningful* data,
    /// we show exactly one result row with the name to tap. If not, we show "No results found".
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
            noResults = false
        }

        do {
            if let details = try await OpenFDAService.fetchDetails(forName: q),
               isMeaningful(details) {
                let apiTitle = details.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let display = cleanTitle(apiTitle) ?? q

                guard token == latestToken else { return }
                await MainActor.run {
                    self.validatedResult = display
                    self.noResults = false
                    self.isSearching = false
                    self.lastSearchedText = q
                }
            } else {
                // API returned nil / empty → explicit No results state
                guard token == latestToken else { return }
                await MainActor.run {
                    self.validatedResult = nil
                    self.noResults = true
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
                self.noResults = false
            }
        }
    }

    private func resetState() {
        isSearching = false
        errorText = nil
        validatedResult = nil
        noResults = false
        lastSearchedText = ""
        latestToken = UUID()
    }

    /// Treat obviously empty/garbage responses as “no result”.
    private func isMeaningful(_ d: MedDetails) -> Bool {
        let titleOK: Bool = {
            let t = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, t.count <= 120 else { return false }
            // reject big ALL-CAPS headers and weird boilerplate
            if t.range(of: #"^[A-Z ]{10,}$"#, options: .regularExpression) != nil { return false }
            return true
        }()

        // Require at least one non-trivial section
        let bodyOK =
            d.combinedText.replacingOccurrences(of: "\\s", with: "", options: .regularExpression).count > 200
            || !d.uses.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !d.dosage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !d.warnings.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !d.sideEffects.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return titleOK && bodyOK
    }

    /// Simple sanity filter for titles; returns nil for obviously bogus header strings.
    private func cleanTitle(_ t: String) -> String? {
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return nil }
        if trimmed.range(of: #"^[A-Z][A-Za-z0-9 ()\-/.,]+$"#, options: .regularExpression) == nil {
            return nil
        }
        return trimmed
    }
}
