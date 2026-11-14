import Foundation
import Observation

struct DeepLinkSearchRequest: Equatable, Sendable {
    let id = UUID()
    let query: String
    let scope: ExploreScope
    let order: SearchOrder?
}

struct DeepLinkResolvedMedia: Equatable, Sendable {
    let id = UUID()
    let gif: GifItem
    let users: [CreatorUser]
    let relatedNicheID: String?
}

enum DeepLinkDestination: Equatable, Sendable {
    case media(gifID: String, relatedNicheID: String? = nil, fallbackTagSearch: Bool = false)
    case creator(username: String)
    case niche(id: String, selectedGifID: String? = nil)
    case tag(String)
    case search(query: String, scope: ExploreScope, order: SearchOrder?)
    case feed(mode: FeedMode?)
    case explore
    case niches(order: NicheSortOrder?)
    case library
}

enum DeepLinkParser {
    private static let redgifsHostSuffix = ".redgifs.com"
    private static let wrapperQueryKeys: Set<String> = ["url", "target", "link", "path", "redirect", "to"]
    private static let mediaExtensions: Set<String> = ["mp4", "m3u8", "jpg", "jpeg", "png", "webp", "webm", "gif"]
    private static let derivativeSuffixes = [
        "-mobile", "-silent", "-poster", "-thumbnail", "-thumb", "-large", "-small", "-hd", "-sd", "-lq"
    ]

    static func parse(_ url: URL) -> DeepLinkDestination? {
        parse(url.absoluteString, depth: 0)
    }

    static func parse(_ rawString: String) -> DeepLinkDestination? {
        parse(rawString, depth: 0)
    }

    static func looksLikeExplicitLink(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return false
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("redgifs://")
            || lower.contains("redgifs.com/")
            || lower.hasPrefix("http://")
            || lower.hasPrefix("https://") {
            return true
        }
        let barePrefixes = [
            "watch/", "/watch/", "ifr/", "/ifr/",
            "users/", "/users/", "user/", "/user/",
            "niches/", "/niches/", "tag/", "/tag/"
        ]
        if barePrefixes.contains(where: { lower.hasPrefix($0) }) {
            return true
        }
        return lower.hasPrefix("@") && trimmed.count > 1
    }

    private static func parse(_ rawString: String, depth: Int) -> DeepLinkDestination? {
        guard depth < 4 else { return nil }

        let cleaned = normalizeRawString(rawString)
        guard !cleaned.isEmpty else { return nil }

        // Percent-encoded wrapped URLs (e.g. redgifs://https%3A%2F%2Fwww.redgifs.com%2Fwatch%2Fabc)
        let prefixBeforeQuery = cleaned.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? cleaned
        if !prefixBeforeQuery.contains("://"),
           let decoded = cleaned.removingPercentEncoding,
           decoded != cleaned {
            let loweredDecoded = decoded.lowercased()
            if loweredDecoded.hasPrefix("http://")
                || loweredDecoded.hasPrefix("https://")
                || loweredDecoded.hasPrefix("redgifs:")
                || prefixBeforeQuery.localizedCaseInsensitiveContains("%2f")
                || prefixBeforeQuery.localizedCaseInsensitiveContains("%3a") {
                return parse(decoded, depth: depth + 1)
            }
        }

        let lowerCleaned = cleaned.lowercased()
        let hasWebScheme = lowerCleaned.hasPrefix("http://") || lowerCleaned.hasPrefix("https://")
        let firstSlashPart = String(prefixBeforeQuery.split(separator: "/", maxSplits: 1).first ?? "")

        var isRedgifsDomain = false
        var components: URLComponents?

        if hasWebScheme {
            components = URLComponents(string: cleaned)
            if let host = components?.host?.lowercased() {
                guard isSupportedHost(host) || hasWrapperQuery(in: components) else {
                    return nil
                }
                isRedgifsDomain = isSupportedHost(host)
            }
        } else if isSupportedHost(firstSlashPart.lowercased()) {
            components = URLComponents(string: "https://\(cleaned)")
            isRedgifsDomain = true
        } else {
            let pathCandidate = cleaned.hasPrefix("/") ? cleaned : "/\(cleaned)"
            components = URLComponents(string: "https://redgifs.internal\(pathCandidate)")
        }

        guard let components else { return nil }

        let queryItems = components.queryItems ?? []
        if let wrappedValue = queryItems.first(where: { item in
            wrapperQueryKeys.contains(item.name.lowercased()) && !(item.value ?? "").isEmpty
        })?.value {
            return parse(wrappedValue, depth: depth + 1)
        }

        let host = components.host?.lowercased() ?? ""
        var segments = components.path
            .split(separator: "/")
            .map { String($0).removingPercentEncoding ?? String($0) }
            .filter { !$0.isEmpty }

        if isRedgifsDomain && isMediaCDNHost(host) {
            if let last = segments.last, let mediaID = extractMediaID(fromFilename: last, requireMediaHint: false) {
                return .media(gifID: mediaID)
            }
            return nil
        }

        if let first = segments.first?.lowercased(), first == "v2" || first == "v1" {
            segments.removeFirst()
        }

        let fragment = components.fragment ?? ""
        let relNiche = extractRelatedNiche(fragment: fragment, queryItems: queryItems)

        if segments.isEmpty {
            return parseRootRoute(queryItems: queryItems, fallbackToFeed: isRedgifsDomain || hasWrapperQuery(in: components) == false)
        }

        if let last = segments.last,
           let directMediaID = extractMediaID(fromFilename: last, requireMediaHint: true) {
            return .media(gifID: directMediaID, relatedNicheID: relNiche)
        }

        return routeSegments(segments, queryItems: queryItems, relNiche: relNiche)
    }

    private static func routeSegments(
        _ segments: [String],
        queryItems: [URLQueryItem],
        relNiche: String?
    ) -> DeepLinkDestination? {
        let head = segments[0].lowercased()

        if head.hasPrefix("@") {
            let username = String(segments[0].dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return username.isEmpty ? nil : .creator(username: username)
        }

        switch head {
        case "watch", "ifr", "gif", "media", "video", "v", "w":
            guard segments.count >= 2 else { return .feed(mode: nil) }
            let rawID = segments[1]
            let gifID = extractMediaID(fromFilename: rawID, requireMediaHint: false) ?? rawID.lowercased()
            return gifID.isEmpty ? nil : .media(gifID: gifID, relatedNicheID: relNiche)

        case "gifs":
            if segments.count >= 2 {
                let second = segments[1]
                if second.caseInsensitiveCompare("search") == .orderedSame {
                    return buildSearchDestination(defaultScope: .videos, queryItems: queryItems)
                }
                let gifID = extractMediaID(fromFilename: second, requireMediaHint: false) ?? second.lowercased()
                return gifID.isEmpty ? nil : .media(gifID: gifID, relatedNicheID: relNiche, fallbackTagSearch: true)
            }
            return .feed(mode: feedMode(fromOrder: queryValue("order", in: queryItems)))

        case "users", "user", "u", "creators", "creator", "profile", "pins":
            if segments.count >= 2 {
                let rawName = segments[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanedName = rawName.hasPrefix("@") ? String(rawName.dropFirst()) : rawName
                if cleanedName.caseInsensitiveCompare("search") == .orderedSame {
                    return buildSearchDestination(defaultScope: .creators, queryItems: queryItems)
                }
                return cleanedName.isEmpty ? nil : .creator(username: cleanedName)
            }
            return .explore

        case "niches", "niche", "n":
            if segments.count >= 2 {
                let slug = segments[1]
                if slug.caseInsensitiveCompare("search") == .orderedSame {
                    return buildSearchDestination(defaultScope: .niches, queryItems: queryItems)
                }
                let selectedGifID = queryValue("gif", in: queryItems)
                    .flatMap { extractMediaID(fromFilename: $0, requireMediaHint: false) }
                return .niche(id: slug, selectedGifID: selectedGifID)
            }
            return .niches(order: nicheSortOrder(from: queryValue("order", in: queryItems)))

        case "tag", "tags":
            if segments.count >= 2 {
                let tagName = segments[1].trimmingCharacters(in: .whitespacesAndNewlines)
                return tagName.isEmpty ? .explore : .tag(tagName)
            }
            return .explore

        case "search":
            let scopeSegment = segments.count >= 2 ? segments[1].lowercased() : nil
            let defaultScope = scope(from: scopeSegment) ?? scope(from: queryValue("type", in: queryItems)) ?? .videos
            return buildSearchDestination(defaultScope: defaultScope, queryItems: queryItems)

        case "explore":
            let sub = segments.count >= 2 ? segments[1].lowercased() : ""
            switch sub {
            case "gifs", "videos":
                return .feed(mode: feedMode(fromOrder: queryValue("order", in: queryItems)) ?? .trending)
            case "images", "photos":
                return .feed(mode: .images)
            case "creators", "users":
                let q = searchQueryValue(in: queryItems)
                if !q.isEmpty {
                    return .search(query: q, scope: .creators, order: searchOrder(from: queryValue("order", in: queryItems)))
                }
                return .explore
            case "niches":
                return .niches(order: nicheSortOrder(from: queryValue("order", in: queryItems)))
            default:
                return .explore
            }

        case "feed", "home":
            return .feed(mode: feedMode(fromOrder: queryValue("mode", in: queryItems) ?? queryValue("order", in: queryItems)))

        case "trending":
            return .feed(mode: .trending)

        case "latest":
            return .feed(mode: .latest)

        case "top7":
            return .feed(mode: .topWeek)

        case "top28":
            return .feed(mode: .topMonth)

        case "images":
            return .feed(mode: .images)

        case "library", "saved":
            return .library

        case "open", "redirect":
            return nil

        default:
            if segments.count == 1 {
                let token = segments[0]
                let normalized = extractMediaID(fromFilename: token, requireMediaHint: false) ?? token.lowercased()
                return normalized.isEmpty ? nil : .media(gifID: normalized, relatedNicheID: relNiche, fallbackTagSearch: true)
            }
            return nil
        }
    }

    private static func parseRootRoute(queryItems: [URLQueryItem], fallbackToFeed: Bool) -> DeepLinkDestination? {
        if let gifParam = queryValue("gif", in: queryItems),
           let gifID = extractMediaID(fromFilename: gifParam, requireMediaHint: false) {
            return .media(gifID: gifID, relatedNicheID: queryValue("niche", in: queryItems))
        }
        if let tagParam = queryValue("tag", in: queryItems), !tagParam.isEmpty {
            return .tag(tagParam)
        }
        let searchQuery = searchQueryValue(in: queryItems)
        if !searchQuery.isEmpty {
            let scope = scope(from: queryValue("type", in: queryItems)) ?? .videos
            return .search(query: searchQuery, scope: scope, order: searchOrder(from: queryValue("order", in: queryItems)))
        }
        return fallbackToFeed ? .feed(mode: nil) : nil
    }

    private static func buildSearchDestination(defaultScope: ExploreScope, queryItems: [URLQueryItem]) -> DeepLinkDestination {
        let q = searchQueryValue(in: queryItems)
        let resolvedScope = scope(from: queryValue("type", in: queryItems)) ?? defaultScope
        let order = searchOrder(from: queryValue("order", in: queryItems))
        if q.isEmpty {
            return resolvedScope == .niches ? .niches(order: nil) : .explore
        }
        return .search(query: q, scope: resolvedScope, order: order)
    }

    private static func normalizeRawString(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.lowercased().hasPrefix("redgifs:") {
            value = String(value.dropFirst("redgifs:".count))
            while value.hasPrefix("/") {
                value.removeFirst()
            }
        }
        while value.hasPrefix("/") {
            value.removeFirst()
        }
        return value
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "redgifs.com" || host.hasSuffix(redgifsHostSuffix)
    }

    private static func isMediaCDNHost(_ host: String) -> Bool {
        host == "media.redgifs.com" || host == "i.redgifs.com" || (host.hasPrefix("thumbs") && host.hasSuffix(redgifsHostSuffix))
    }

    private static func hasWrapperQuery(in components: URLComponents?) -> Bool {
        guard let items = components?.queryItems else { return false }
        return items.contains { wrapperQueryKeys.contains($0.name.lowercased()) && !($0.value ?? "").isEmpty }
    }

    private static func extractMediaID(fromFilename filename: String, requireMediaHint: Bool) -> String? {
        var name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        var hadExtension = false
        let ns = name as NSString
        let ext = ns.pathExtension.lowercased()
        if !ext.isEmpty && mediaExtensions.contains(ext) {
            name = ns.deletingPathExtension
            hadExtension = true
        }

        var hadSuffix = false
        var changed = true
        while changed {
            changed = false
            let lower = name.lowercased()
            for suffix in derivativeSuffixes where lower.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
                hadSuffix = true
                changed = true
                break
            }
        }

        if requireMediaHint && !hadExtension && !hadSuffix {
            return nil
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func extractRelatedNiche(fragment: String, queryItems: [URLQueryItem]) -> String? {
        if let direct = queryValue("niche", in: queryItems), !direct.isEmpty {
            return direct
        }
        guard !fragment.isEmpty else { return nil }
        let decoded = fragment.removingPercentEncoding ?? fragment
        for pair in decoded.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased() == "rel" {
                let value = String(parts[1])
                if value.lowercased().hasPrefix("niche:") {
                    let slug = String(value.dropFirst("niche:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !slug.isEmpty { return slug }
                }
            }
        }
        return nil
    }

    private static func queryValue(_ key: String, in items: [URLQueryItem]) -> String? {
        items.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func searchQueryValue(in items: [URLQueryItem]) -> String {
        queryValue("query", in: items) ?? queryValue("q", in: items) ?? ""
    }

    private static func scope(from raw: String?) -> ExploreScope? {
        switch raw?.lowercased() {
        case "g", "gif", "gifs", "video", "videos": return .videos
        case "i", "image", "images", "photo", "photos": return .images
        case "c", "creator", "creators", "user", "users": return .creators
        case "n", "niche", "niches": return .niches
        default: return nil
        }
    }

    private static func searchOrder(from raw: String?) -> SearchOrder? {
        switch raw?.lowercased() {
        case "trending": return .trending
        case "latest", "new": return .latest
        case "score", "best": return .score
        case "top7": return .topWeek
        case "top28": return .topMonth
        default: return nil
        }
    }

    private static func feedMode(fromOrder raw: String?) -> FeedMode? {
        switch raw?.lowercased() {
        case "trending", "popular": return .trending
        case "latest", "new": return .latest
        case "top7": return .topWeek
        case "top28": return .topMonth
        case "images", "i": return .images
        default: return nil
        }
    }

    private static func nicheSortOrder(from raw: String?) -> NicheSortOrder? {
        switch raw?.lowercased() {
        case "subscribers": return .subscribers
        case "posts": return .posts
        case "alphabetical_asc": return .alphabeticalAsc
        case "alphabetical_desc": return .alphabeticalDesc
        default: return nil
        }
    }
}

@Observable
@MainActor
final class DeepLinkRouter {
    var selectedTab: AppTab = .feed
    var feedNavigationPath: [AppRoute] = []
    var exploreNavigationPath: [AppRoute] = []
    var nichesNavigationPath: [AppRoute] = []
    var libraryNavigationPath: [AppRoute] = []

    var pendingFeedMode: FeedMode?
    var pendingSearchRequest: DeepLinkSearchRequest?
    var pendingNicheSort: NicheSortOrder?
    var pendingResolvedMedia: DeepLinkResolvedMedia?

    var presentedImmersiveSelection: ImmersiveFeedSelection?
    var presentedImmersiveLoader: (@MainActor @Sendable (Int) async throws -> FeedEnvelope)?
    var isResolvingMedia = false
    var resolutionErrorMessage: String?
    var coverDismissCounter = 0

    private var activeResolutionTask: Task<Void, Never>?
    private var activeResolutionID = UUID()

    func open(url: URL, playerCoordinator: VideoPlayerCoordinator) {
        _ = open(rawURLString: url.absoluteString, playerCoordinator: playerCoordinator)
    }

    @discardableResult
    func open(rawURLString: String, playerCoordinator: VideoPlayerCoordinator) -> Bool {
        guard let destination = DeepLinkParser.parse(rawURLString) else {
            return false
        }
        route(to: destination, playerCoordinator: playerCoordinator)
        return true
    }

    func didDismissImmersiveCover() {
        presentedImmersiveSelection = nil
        presentedImmersiveLoader = nil
        coverDismissCounter += 1
    }

    func dismissError() {
        resolutionErrorMessage = nil
    }

    private func route(to destination: DeepLinkDestination, playerCoordinator: VideoPlayerCoordinator) {
        activeResolutionTask?.cancel()
        activeResolutionID = UUID()
        isResolvingMedia = false
        resolutionErrorMessage = nil

        switch destination {
        case .media(let gifID, let relatedNicheID, let fallbackTagSearch):
            resolveAndPresentMedia(
                gifID: gifID,
                relatedNicheID: relatedNicheID,
                fallbackTagSearch: fallbackTagSearch,
                playerCoordinator: playerCoordinator
            )

        case .creator(let username):
            dismissImmersiveCoverIfNeeded()
            selectedTab = .explore
            exploreNavigationPath = [.creator(username: username, initialUser: nil)]

        case .niche(let id, let selectedGifID):
            selectedTab = .niches
            nichesNavigationPath = [.niche(NicheSummary(id: id, name: id))]
            if let selectedGifID {
                resolveAndPresentMedia(
                    gifID: selectedGifID,
                    relatedNicheID: id,
                    fallbackTagSearch: false,
                    playerCoordinator: playerCoordinator
                )
            } else {
                dismissImmersiveCoverIfNeeded()
            }

        case .tag(let tagName):
            dismissImmersiveCoverIfNeeded()
            selectedTab = .explore
            exploreNavigationPath = [.tagSearch(tagName)]

        case .search(let query, let scope, let order):
            dismissImmersiveCoverIfNeeded()
            selectedTab = .explore
            exploreNavigationPath = []
            pendingSearchRequest = DeepLinkSearchRequest(query: query, scope: scope, order: order)

        case .feed(let mode):
            dismissImmersiveCoverIfNeeded()
            selectedTab = .feed
            feedNavigationPath = []
            if let mode {
                pendingFeedMode = mode
            }

        case .explore:
            dismissImmersiveCoverIfNeeded()
            selectedTab = .explore
            exploreNavigationPath = []

        case .niches(let order):
            dismissImmersiveCoverIfNeeded()
            selectedTab = .niches
            nichesNavigationPath = []
            if let order {
                pendingNicheSort = order
            }

        case .library:
            dismissImmersiveCoverIfNeeded()
            selectedTab = .library
            libraryNavigationPath = []
        }
    }

    private func dismissImmersiveCoverIfNeeded() {
        if presentedImmersiveSelection != nil {
            didDismissImmersiveCover()
        }
    }

    private func resolveAndPresentMedia(
        gifID: String,
        relatedNicheID: String?,
        fallbackTagSearch: Bool,
        playerCoordinator: VideoPlayerCoordinator
    ) {
        let resolutionID = UUID()
        activeResolutionID = resolutionID
        playerCoordinator.pauseAll()
        dismissImmersiveCoverIfNeeded()
        selectedTab = .feed
        feedNavigationPath = []
        isResolvingMedia = true

        activeResolutionTask = Task {
            do {
                let envelope = try await RedGifsAPIClient.shared.gifDetailEnvelope(gifId: gifID)
                guard !Task.isCancelled, activeResolutionID == resolutionID else { return }

                var resolvedUsers: [CreatorUser] = []
                if let user = envelope.user {
                    resolvedUsers.append(user)
                }
                resolvedUsers.append(contentsOf: envelope.users)

                isResolvingMedia = false
                pendingResolvedMedia = DeepLinkResolvedMedia(
                    gif: envelope.gif,
                    users: resolvedUsers,
                    relatedNicheID: relatedNicheID
                )
            } catch is CancellationError {
                if activeResolutionID == resolutionID {
                    isResolvingMedia = false
                }
            } catch {
                guard !Task.isCancelled, activeResolutionID == resolutionID else { return }
                isResolvingMedia = false
                if fallbackTagSearch {
                    selectedTab = .explore
                    exploreNavigationPath = [.tagSearch(gifID)]
                } else {
                    let fallbackGif = GifItem(
                        id: gifID.lowercased(),
                        hasAudio: true,
                        hls: true,
                        type: .video
                    )
                    pendingResolvedMedia = DeepLinkResolvedMedia(
                        gif: fallbackGif,
                        users: [],
                        relatedNicheID: relatedNicheID
                    )
                }
            }
        }
    }
}
