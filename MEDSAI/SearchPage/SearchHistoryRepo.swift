import Foundation

@MainActor
final class SearchHistoryRepo: ObservableObject {
    @Published private(set) var recent: [String] = []
    @Published private(set) var errorMessage: String?

    private var supabase: SupabaseManager { .shared }

    /// Fetch recent searches for the signed-in user (latest first).
    func start(limit: Int = 10) {
        guard supabase.currentUserID != nil else { recent = []; return }
        Task { await fetchRecent(limit: limit) }
    }

    private func fetchRecent(limit: Int) async {
        guard let uid = supabase.currentUserID else { return }
        do {
            struct Row: Decodable { let search_query: String }
            let rows: [Row] = try await supabase.client
                .from("search_history")
                .select("search_query")
                .eq("user_id", value: uid.uuidString)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value

            // Deduplicate while keeping order
            var seen = Set<String>(); var out: [String] = []
            for r in rows {
                let key = r.search_query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !key.isEmpty && !seen.contains(key) {
                    out.append(r.search_query); seen.insert(key)
                }
            }
            self.recent = out
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Append a query to the user's history.
    func add(query: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let uid = supabase.currentUserID else { return }
        do {
            try await supabase.client
                .from("search_history")
                .insert([
                    "user_id": uid.uuidString,
                    "search_query": q
                ])
                .execute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
