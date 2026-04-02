import Foundation

@MainActor
final class SearchHistoryRepo: ObservableObject {
    @Published private(set) var recent: [String] = []
    @Published private(set) var errorMessage: String?

    /// Fetch recent searches for the signed-in user (latest first).
    func start(limit: Int = 10) {
        guard SessionStore.shared.currentUserID != nil else { recent = []; return }
        Task { await fetchRecent(limit: limit) }
    }

    private func fetchRecent(limit: Int) async {
        guard SessionStore.shared.currentUserID != nil else { return }
        do {
            let response: APISearchHistoryResponse = try await BackendClient.shared.request("/search-history?limit=\(limit)")
            self.recent = response.recent
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Append a query to the user's history.
    func add(query: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, SessionStore.shared.currentUserID != nil else { return }
        do {
            let _: APIMessageResponse = try await BackendClient.shared.request(
                "/search-history",
                method: .post,
                body: APISearchHistoryRequest(searchQuery: q)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
