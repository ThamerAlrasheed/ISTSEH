import Foundation

enum BackendHTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

private struct BackendErrorEnvelope: Decodable {
    let detail: String?
    let error: String?
}

private struct EmptyResponse: Decodable {}

actor BackendClient {
    static let shared = BackendClient()

    private let sessionStore = SessionStore.shared
    private let urlSession: URLSession
    private var refreshTask: Task<Void, Error>?

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func request<T: Decodable>(
        _ path: String,
        method: BackendHTTPMethod = .get,
        requiresAuth: Bool = true,
        allowRefresh: Bool = true
    ) async throws -> T {
        let request = try makeRequest(path: path, method: method, requiresAuth: requiresAuth)
        return try await perform(request, allowRefresh: allowRefresh)
    }

    func request<T: Decodable, Body: Encodable>(
        _ path: String,
        method: BackendHTTPMethod,
        body: Body,
        requiresAuth: Bool = true,
        allowRefresh: Bool = true
    ) async throws -> T {
        let request = try makeRequest(path: path, method: method, body: body, requiresAuth: requiresAuth)
        return try await perform(request, allowRefresh: allowRefresh)
    }

    func requestVoid<Body: Encodable>(
        _ path: String,
        method: BackendHTTPMethod,
        body: Body,
        requiresAuth: Bool = true,
        allowRefresh: Bool = true
    ) async throws {
        let _: EmptyResponse = try await request(
            path,
            method: method,
            body: body,
            requiresAuth: requiresAuth,
            allowRefresh: allowRefresh
        )
    }

    private func perform<T: Decodable>(_ request: URLRequest, allowRefresh: Bool) async throws -> T {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "BackendClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."])
        }

        if http.statusCode == 401,
           allowRefresh,
           sessionStore.accessToken != nil,
           sessionStore.refreshToken != nil {
            try await refreshSessionIfNeeded()
            var retry = request
            if let accessToken = sessionStore.accessToken {
                retry.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
            let (retryData, retryResponse) = try await urlSession.data(for: retry)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                throw NSError(domain: "BackendClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid retry response."])
            }
            guard (200..<300).contains(retryHTTP.statusCode) else {
                throw error(from: retryData, statusCode: retryHTTP.statusCode)
            }
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            return try decoder.decode(T.self, from: retryData)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw error(from: data, statusCode: http.statusCode)
        }

        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }

        return try decoder.decode(T.self, from: data)
    }

    private func makeRequest(
        path: String,
        method: BackendHTTPMethod,
        requiresAuth: Bool
    ) throws -> URLRequest {
        guard let url = url(for: path) else {
            throw NSError(domain: "BackendClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL."])
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try applyAuth(to: &request, requiresAuth: requiresAuth)
        return request
    }

    private func makeRequest<Body: Encodable>(
        path: String,
        method: BackendHTTPMethod,
        body: Body,
        requiresAuth: Bool
    ) throws -> URLRequest {
        var request = try makeRequest(path: path, method: method, requiresAuth: requiresAuth)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return request
    }

    private func applyAuth(to request: inout URLRequest, requiresAuth: Bool) throws {
        guard requiresAuth else { return }

        if let accessToken = sessionStore.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            return
        }

        if let deviceToken = sessionStore.deviceToken {
            request.setValue(deviceToken, forHTTPHeaderField: "X-Device-Token")
            return
        }

        throw NSError(domain: "BackendClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "No active session."])
    }

    private func refreshSessionIfNeeded() async throws {
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task {
            guard let refreshToken = sessionStore.refreshToken else {
                throw NSError(domain: "BackendClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing refresh token."])
            }

            let request = try makeRequest(
                path: "/auth/refresh",
                method: .post,
                body: APIRefreshRequest(refreshToken: refreshToken),
                requiresAuth: false
            )
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                sessionStore.clear()
                throw error(from: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 401)
            }

            let payload = try decoder.decode(APIAuthSession.self, from: data)
            sessionStore.storeAuthenticatedSession(payload)
        }

        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private func url(for path: String) -> URL? {
        let baseURLString = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String ?? "http://localhost:8000"
        guard let baseURL = URL(string: baseURLString) else { return nil }
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = String(parts.first ?? "")
        let rawQuery = parts.count > 1 ? String(parts[1]) : nil

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/api/v1" + rawPath
        components.percentEncodedQuery = rawQuery
        return components.url
    }

    private func error(from data: Data, statusCode: Int) -> Error {
        if let envelope = try? decoder.decode(BackendErrorEnvelope.self, from: data) {
            let message = envelope.detail ?? envelope.error ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
            return NSError(domain: "BackendClient", code: statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = json["detail"] {
            return NSError(domain: "BackendClient", code: statusCode, userInfo: [NSLocalizedDescriptionKey: String(describing: detail)])
        }

        let raw = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
        return NSError(domain: "BackendClient", code: statusCode, userInfo: [NSLocalizedDescriptionKey: raw])
    }
}
