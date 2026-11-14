import Foundation

enum RedGifsAPIError: Error, LocalizedError, Sendable, Equatable {
    case invalidURL(String)
    case invalidResponse
    case httpError(status: Int, body: String)
    case decodingError(String)
    case transportError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid request URL: \(url)"
        case .invalidResponse:
            return "Received an invalid server response."
        case .httpError(let status, let body):
            if status == 429 {
                return "Rate limited by RedGIFs (HTTP 429). Please wait a moment and try again."
            }
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "Server returned HTTP \(status)."
                : "Server returned HTTP \(status): \(String(trimmed.prefix(180)))"
        case .decodingError(let details):
            return "Unable to decode server response: \(details)"
        case .transportError(let details):
            return details
        }
    }
}

actor RedGifsAPIClient {
    static let shared = RedGifsAPIClient()

    static let apiRoot = "https://api.redgifs.com/v2"
    static let webOrigin = "https://www.redgifs.com"
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    private let session: URLSession
    private let decoder: JSONDecoder

    private var token: String?
    private var sessionId: String?
    private var refreshTask: Task<(token: String, session: String?), Error>?

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 30
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            self.session = URLSession(configuration: configuration)
        }
        self.decoder = JSONDecoder()
    }

    nonisolated func mediaHeaders() -> [String: String] {
        [
            "Referer": "\(Self.webOrigin)/",
            "Origin": Self.webOrigin,
            "User-Agent": Self.userAgent,
        ]
    }

    // MARK: - Auth Bootstrap

    private func baseHeaders(accept: String = "application/json, text/plain, */*") -> [String: String] {
        [
            "Accept": accept,
            "Origin": Self.webOrigin,
            "Referer": "\(Self.webOrigin)/",
            "User-Agent": Self.userAgent,
        ]
    }

    private func ensureAuthContext(forceRefresh: Bool = false) async throws -> (token: String, session: String?) {
        if !forceRefresh, let token, !token.isEmpty {
            return (token, sessionId)
        }
        if forceRefresh {
            token = nil
        }
        if let existingTask = refreshTask {
            return try await existingTask.value
        }

        let initialHeaders = baseHeaders()
        let task = Task<(token: String, session: String?), Error> { [session, decoder, initialHeaders] in
            var components = URLComponents(string: "\(Self.apiRoot)/auth/temporary")
            components?.queryItems = [URLQueryItem(name: "path", value: "/")]
            guard let url = components?.url else {
                throw RedGifsAPIError.invalidURL("\(Self.apiRoot)/auth/temporary")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            for (header, value) in initialHeaders {
                request.setValue(value, forHTTPHeaderField: header)
            }

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw RedGifsAPIError.transportError(error.localizedDescription)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw RedGifsAPIError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw RedGifsAPIError.httpError(status: httpResponse.statusCode, body: body)
            }

            let auth: TemporaryAuthResponse
            do {
                auth = try decoder.decode(TemporaryAuthResponse.self, from: data)
            } catch {
                throw RedGifsAPIError.decodingError(error.localizedDescription)
            }

            guard !auth.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RedGifsAPIError.decodingError("Temporary auth response contained an empty token.")
            }
            let resolvedSession = (auth.session?.isEmpty == false) ? auth.session : nil
            return (auth.token, resolvedSession)
        }

        refreshTask = task
        do {
            let credentials = try await task.value
            self.token = credentials.token
            self.sessionId = credentials.session
            self.refreshTask = nil
            return credentials
        } catch {
            self.refreshTask = nil
            throw error
        }
    }

    // MARK: - Core GET Transport

    private func apiGet<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        includeSessionHeader: Bool = false,
        extraHeaders: [String: String] = [:]
    ) async throws -> T {
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard var components = URLComponents(string: "\(Self.apiRoot)\(normalizedPath)") else {
            throw RedGifsAPIError.invalidURL("\(Self.apiRoot)\(normalizedPath)")
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw RedGifsAPIError.invalidURL(components.string ?? normalizedPath)
        }

        for attempt in 0..<2 {
            let credentials = try await ensureAuthContext(forceRefresh: attempt > 0)
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            for (header, value) in baseHeaders() {
                request.setValue(value, forHTTPHeaderField: header)
            }
            request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")

            if includeSessionHeader, let activeSession = credentials.session {
                request.setValue(activeSession, forHTTPHeaderField: "X-Session-Id")
            }
            for (header, value) in extraHeaders {
                request.setValue(value, forHTTPHeaderField: header)
            }

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw RedGifsAPIError.transportError(error.localizedDescription)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw RedGifsAPIError.invalidResponse
            }

            if httpResponse.statusCode == 401 && attempt == 0 {
                token = nil
                continue
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw RedGifsAPIError.httpError(status: httpResponse.statusCode, body: body)
            }

            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw RedGifsAPIError.decodingError(error.localizedDescription)
            }
        }

        throw RedGifsAPIError.invalidResponse
    }

    private func encodePathSegment(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
    }

    // MARK: - Feeds & Search

    func trendingFeed(
        page: Int = 1,
        count: Int = 30,
        variation: String = "popular"
    ) async throws -> FeedEnvelope {
        let safeVariation = encodePathSegment(variation)
        return try await apiGet(
            path: "/feeds/trending/\(safeVariation)",
            queryItems: [
                URLQueryItem(name: "page", value: String(max(1, page))),
                URLQueryItem(name: "count", value: String(max(1, count))),
            ],
            includeSessionHeader: true
        )
    }

    func searchGifs(
        query: String,
        mediaType: String = "g",
        order: String = "latest",
        count: Int = 30,
        page: Int = 1,
        verifiedOnly: Bool = false
    ) async throws -> FeedEnvelope {
        var items = [
            URLQueryItem(name: "type", value: mediaType),
            URLQueryItem(name: "order", value: order),
            URLQueryItem(name: "count", value: String(max(1, count))),
            URLQueryItem(name: "page", value: String(max(1, page))),
        ]
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            items.insert(URLQueryItem(name: "query", value: trimmedQuery), at: 0)
        }
        if verifiedOnly {
            items.append(URLQueryItem(name: "verified", value: "y"))
        }
        return try await apiGet(path: "/gifs/search", queryItems: items)
    }

    func searchCreators(
        query: String = "",
        order: String = "trending",
        page: Int = 1,
        count: Int = 30,
        verifiedOnly: Bool = false
    ) async throws -> FeedEnvelope {
        var items = [
            URLQueryItem(name: "order", value: order),
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "count", value: String(max(1, count))),
        ]
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            items.append(URLQueryItem(name: "query", value: trimmedQuery))
        }
        if verifiedOnly {
            items.append(URLQueryItem(name: "verified", value: "y"))
        }
        return try await apiGet(path: "/creators/search/previews", queryItems: items)
    }

    // MARK: - Creators

    func creatorFeed(
        username: String,
        mediaType: String = "g",
        order: String = "new",
        count: Int = 40,
        page: Int = 1
    ) async throws -> FeedEnvelope {
        let safeUser = encodePathSegment(username)
        return try await apiGet(
            path: "/users/\(safeUser)/search",
            queryItems: [
                URLQueryItem(name: "order", value: order),
                URLQueryItem(name: "count", value: String(max(1, count))),
                URLQueryItem(name: "type", value: mediaType),
                URLQueryItem(name: "page", value: String(max(1, page))),
            ]
        )
    }

    func creatorProfile(username: String, mediaType: String = "g") async throws -> CreatorProfileBundle {
        let safeUser = encodePathSegment(username)

        async let primaryFeedTask = creatorFeed(username: username, mediaType: mediaType)
        async let pinsTask: FeedEnvelope? = try? apiGet(path: "/pins/\(safeUser)")
        async let socialsTask: SocialsEnvelope? = try? apiGet(path: "/socials/\(safeUser)")
        async let tagsTask: CreatorTagsEnvelope? = try? apiGet(path: "/creators/\(safeUser)/tags")

        let feed = try await primaryFeedTask
        let pinsEnvelope = await pinsTask
        let socialsEnvelope = await socialsTask
        let tagsEnvelope = await tagsTask

        let matchedUser = feed.users.first {
            $0.username.caseInsensitiveCompare(username) == .orderedSame
        } ?? feed.users.first

        return CreatorProfileBundle(
            user: matchedUser,
            feed: feed,
            pins: pinsEnvelope?.gifs ?? [],
            socials: socialsEnvelope?.links ?? [],
            tags: tagsEnvelope?.tags ?? []
        )
    }

    // MARK: - Tags & Niches

    func trendingTags() async throws -> [TrendingTag] {
        let envelope: TrendingTagsEnvelope = try await apiGet(path: "/tags/trending")
        return envelope.tags.filter { !$0.name.isEmpty }
    }

    func searchNiches(
        query: String = "",
        order: String = "subscribers",
        page: Int = 1,
        count: Int = 30
    ) async throws -> NichePreviewsEnvelope {
        var items = [
            URLQueryItem(name: "order", value: order),
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "count", value: String(max(1, count))),
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items.append(URLQueryItem(name: "query", value: trimmed))
        }
        return try await apiGet(path: "/niches/search/previews", queryItems: items)
    }

    func nicheGifs(
        nicheId: String,
        order: String = "hot",
        page: Int = 1,
        count: Int = 30
    ) async throws -> FeedEnvelope {
        let safeNiche = encodePathSegment(nicheId)
        return try await apiGet(
            path: "/niches/\(safeNiche)/gifs",
            queryItems: [
                URLQueryItem(name: "order", value: order),
                URLQueryItem(name: "page", value: String(max(1, page))),
                URLQueryItem(name: "count", value: String(max(1, count))),
            ]
        )
    }

    func nicheTopCreators(nicheId: String) async throws -> [CreatorUser] {
        let safeNiche = encodePathSegment(nicheId)
        let envelope: TopCreatorsEnvelope = try await apiGet(path: "/niches/\(safeNiche)/top-creators")
        return envelope.creators
    }

    func nicheDetail(nicheId: String) async throws -> NicheSummary {
        let safeNiche = encodePathSegment(nicheId)
        let envelope: NicheDetailEnvelope = try await apiGet(path: "/niches/\(safeNiche)")
        return envelope.niche
    }

    // MARK: - GIF Detail

    func gifDetailEnvelope(gifId: String) async throws -> GifDetailEnvelope {
        let safeId = encodePathSegment(gifId.lowercased())
        return try await apiGet(
            path: "/gifs/\(safeId)",
            queryItems: [
                URLQueryItem(name: "views", value: "yes"),
                URLQueryItem(name: "users", value: "yes"),
                URLQueryItem(name: "niches", value: "yes"),
            ],
            includeSessionHeader: true,
            extraHeaders: [
                "Referer": "\(Self.webOrigin)/watch/\(safeId)",
                "x-customheader": "\(Self.webOrigin)/watch/\(safeId)",
            ]
        )
    }

    func gifDetail(gifId: String) async throws -> GifItem {
        try await gifDetailEnvelope(gifId: gifId).gif
    }
}
