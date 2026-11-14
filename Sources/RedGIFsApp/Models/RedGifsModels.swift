import CoreGraphics
import Foundation

// MARK: - Auth

struct TemporaryAuthResponse: Codable, Sendable {
    let token: String
    let session: String?
    let addr: String?
    let agent: String?
    let rtfm: String?
}

// MARK: - Feed & Search Envelopes

struct FeedEnvelope: Codable, Sendable, Hashable {
    let gifs: [GifItem]
    let users: [CreatorUser]
    let niches: [NicheSummary]
    let tags: [String]
    let boostedGifs: [GifItem]
    let promotedGifs: [GifItem]
    let page: Int
    let pages: Int
    let total: Int

    init(
        gifs: [GifItem] = [],
        users: [CreatorUser] = [],
        niches: [NicheSummary] = [],
        tags: [String] = [],
        boostedGifs: [GifItem] = [],
        promotedGifs: [GifItem] = [],
        page: Int = 1,
        pages: Int = 1,
        total: Int = 0
    ) {
        self.gifs = gifs
        self.users = users
        self.niches = niches
        self.tags = tags
        self.boostedGifs = boostedGifs
        self.promotedGifs = promotedGifs
        self.page = page
        self.pages = pages
        self.total = total
    }

    enum CodingKeys: String, CodingKey {
        case gifs
        case users
        case niches
        case tags
        case boostedGifs = "boosted_gifs"
        case promotedGifs = "promoted_gifs"
        case page
        case pages
        case total
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.gifs = (try? container.decode([GifItem].self, forKey: .gifs)) ?? []
        self.users = (try? container.decode([CreatorUser].self, forKey: .users)) ?? []
        self.niches = (try? container.decode([NicheSummary].self, forKey: .niches)) ?? []
        self.tags = Self.decodeFlexibleStringArray(from: container, forKey: .tags)
        self.boostedGifs = (try? container.decode([GifItem].self, forKey: .boostedGifs)) ?? []
        self.promotedGifs = (try? container.decode([GifItem].self, forKey: .promotedGifs)) ?? []
        self.page = container.decodeFlexibleInt(forKey: .page) ?? 1
        self.pages = container.decodeFlexibleInt(forKey: .pages) ?? 1
        self.total = container.decodeFlexibleInt(forKey: .total) ?? gifs.count
    }

    static func decodeFlexibleStringArray<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> [String] {
        if let strings = try? container.decode([String].self, forKey: key) {
            return strings
        }
        if let rawItems = try? container.decode([FlexibleNamedValue].self, forKey: key) {
            return rawItems.compactMap(\.resolvedString)
        }
        return []
    }
}

// MARK: - Media Card

enum MediaTypeKind: Codable, Sendable, Hashable {
    case video
    case image
    case unknown(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            switch intValue {
            case 1: self = .video
            case 2: self = .image
            default: self = .unknown(String(intValue))
            }
            return
        }
        if let stringValue = try? container.decode(String.self) {
            switch stringValue.lowercased() {
            case "1", "g", "gif", "video": self = .video
            case "2", "i", "image", "photo": self = .image
            default: self = .unknown(stringValue)
            }
            return
        }
        self = .video
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .video: try container.encode(1)
        case .image: try container.encode(2)
        case .unknown(let value): try container.encode(value)
        }
    }
}

struct MediaURLs: Codable, Sendable, Hashable {
    let hd: String?
    let sd: String?
    let silent: String?
    let poster: String?
    let thumbnail: String?
    let html: String?
}

struct GifItem: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let avgColor: String?
    let createDate: TimeInterval?
    let description: String?
    let duration: Double?
    let hasAudio: Bool
    let height: Int?
    let width: Int?
    let hls: Bool
    let likes: Int
    let views: Int
    let niches: [String]
    let tags: [String]
    let type: MediaTypeKind
    let urls: MediaURLs?
    let userName: String?
    let verified: Bool

    init(
        id: String,
        avgColor: String? = nil,
        createDate: TimeInterval? = nil,
        description: String? = nil,
        duration: Double? = nil,
        hasAudio: Bool = false,
        height: Int? = nil,
        width: Int? = nil,
        hls: Bool = false,
        likes: Int = 0,
        views: Int = 0,
        niches: [String] = [],
        tags: [String] = [],
        type: MediaTypeKind = .video,
        urls: MediaURLs? = nil,
        userName: String? = nil,
        verified: Bool = false
    ) {
        self.id = id
        self.avgColor = avgColor
        self.createDate = createDate
        self.description = description
        self.duration = duration
        self.hasAudio = hasAudio
        self.height = height
        self.width = width
        self.hls = hls
        self.likes = likes
        self.views = views
        self.niches = niches
        self.tags = tags
        self.type = type
        self.urls = urls
        self.userName = userName
        self.verified = verified
    }

    enum CodingKeys: String, CodingKey {
        case id
        case avgColor
        case createDate
        case description
        case duration
        case hasAudio
        case height
        case width
        case hls
        case likes
        case views
        case niches
        case tags
        case type
        case urls
        case userName
        case verified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.avgColor = try? container.decodeIfPresent(String.self, forKey: .avgColor)
        self.createDate = container.decodeFlexibleDouble(forKey: .createDate)
        self.description = try? container.decodeIfPresent(String.self, forKey: .description)
        self.duration = container.decodeFlexibleDouble(forKey: .duration)
        self.hasAudio = (try? container.decodeIfPresent(Bool.self, forKey: .hasAudio)) ?? false
        self.height = container.decodeFlexibleInt(forKey: .height)
        self.width = container.decodeFlexibleInt(forKey: .width)
        self.hls = (try? container.decodeIfPresent(Bool.self, forKey: .hls)) ?? false
        self.likes = container.decodeFlexibleInt(forKey: .likes) ?? 0
        self.views = container.decodeFlexibleInt(forKey: .views) ?? 0
        self.niches = FeedEnvelope.decodeFlexibleStringArray(from: container, forKey: .niches)
        self.tags = FeedEnvelope.decodeFlexibleStringArray(from: container, forKey: .tags)
        self.type = (try? container.decodeIfPresent(MediaTypeKind.self, forKey: .type)) ?? .video
        self.urls = try? container.decodeIfPresent(MediaURLs.self, forKey: .urls)
        self.userName = try? container.decodeIfPresent(String.self, forKey: .userName)
        self.verified = (try? container.decodeIfPresent(Bool.self, forKey: .verified)) ?? false
    }

    var isVideo: Bool {
        switch type {
        case .video:
            return true
        case .image:
            return false
        case .unknown:
            return duration != nil || hls || urls?.sd != nil || urls?.hd != nil
        }
    }

    var aspectRatio: CGFloat {
        guard let width, let height, width > 0, height > 0 else {
            return 9.0 / 16.0
        }
        return CGFloat(width) / CGFloat(height)
    }

    func bestVideoURL(preferHD: Bool) -> URL? {
        let candidates: [String?] = preferHD
            ? [urls?.hd, urls?.sd, urls?.silent]
            : [urls?.sd, urls?.hd, urls?.silent]
        for raw in candidates {
            if let raw, let url = URL(string: raw), !raw.isEmpty {
                return url
            }
        }
        return hlsURL(preferHD: preferHD)
    }

    func hlsURL(preferHD: Bool) -> URL? {
        let quality = preferHD ? "hd" : "sd"
        return URL(string: "https://api.redgifs.com/v2/gifs/\(id)/\(quality).m3u8")
    }

    var previewImageURL: URL? {
        let candidates = [urls?.poster, urls?.thumbnail, urls?.hd, urls?.sd]
        for raw in candidates {
            if let raw, let url = URL(string: raw), !raw.isEmpty {
                return url
            }
        }
        return nil
    }

    var fullImageURL: URL? {
        let candidates = [urls?.hd, urls?.poster, urls?.sd, urls?.thumbnail]
        for raw in candidates {
            if let raw, let url = URL(string: raw), !raw.isEmpty {
                return url
            }
        }
        return nil
    }

    var watchPageURL: URL {
        URL(string: "https://www.redgifs.com/watch/\(id)")!
    }

    var deepLinkURL: URL {
        URL(string: "redgifs://watch/\(id)")!
    }
}

// MARK: - Creator User

struct CreatorUser: Codable, Sendable, Identifiable, Hashable {
    let username: String
    let name: String?
    let description: String?
    let profileImageUrl: String?
    let profileUrl: String?
    let url: String?
    let creationTime: TimeInterval?
    let followers: Int
    let following: Int
    let views: Int
    let gifs: Int
    let publishedGifs: Int
    let verified: Bool

    var id: String { username }

    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return username
    }

    var avatarURL: URL? {
        guard let profileImageUrl, !profileImageUrl.isEmpty else { return nil }
        return URL(string: profileImageUrl)
    }

    init(
        username: String,
        name: String? = nil,
        description: String? = nil,
        profileImageUrl: String? = nil,
        profileUrl: String? = nil,
        url: String? = nil,
        creationTime: TimeInterval? = nil,
        followers: Int = 0,
        following: Int = 0,
        views: Int = 0,
        gifs: Int = 0,
        publishedGifs: Int = 0,
        verified: Bool = false
    ) {
        self.username = username
        self.name = name
        self.description = description
        self.profileImageUrl = profileImageUrl
        self.profileUrl = profileUrl
        self.url = url
        self.creationTime = creationTime
        self.followers = followers
        self.following = following
        self.views = views
        self.gifs = gifs
        self.publishedGifs = publishedGifs
        self.verified = verified
    }

    enum CodingKeys: String, CodingKey {
        case username
        case name
        case description
        case profileImageUrl
        case profileUrl
        case url
        case creationTime = "creationtime"
        case followers
        case following
        case views
        case gifs
        case publishedGifs
        case verified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedUsername = try? container.decodeIfPresent(String.self, forKey: .username)
        let decodedName = try? container.decodeIfPresent(String.self, forKey: .name)
        self.username = (decodedUsername?.isEmpty == false ? decodedUsername : nil)
            ?? (decodedName?.isEmpty == false ? decodedName : nil)
            ?? "unknown"
        self.name = decodedName
        self.description = try? container.decodeIfPresent(String.self, forKey: .description)
        self.profileImageUrl = try? container.decodeIfPresent(String.self, forKey: .profileImageUrl)
        self.profileUrl = try? container.decodeIfPresent(String.self, forKey: .profileUrl)
        self.url = try? container.decodeIfPresent(String.self, forKey: .url)
        self.creationTime = container.decodeFlexibleDouble(forKey: .creationTime)
        self.followers = container.decodeFlexibleInt(forKey: .followers) ?? 0
        self.following = container.decodeFlexibleInt(forKey: .following) ?? 0
        self.views = container.decodeFlexibleInt(forKey: .views) ?? 0
        self.gifs = container.decodeFlexibleInt(forKey: .gifs) ?? 0
        self.publishedGifs = container.decodeFlexibleInt(forKey: .publishedGifs) ?? 0
        self.verified = (try? container.decodeIfPresent(Bool.self, forKey: .verified)) ?? false
    }
}

// MARK: - Niches

struct NicheSummary: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let cover: String?
    let thumbnail: String?
    let gifs: Int
    let subscribers: Int

    var coverURL: URL? {
        if let cover, let url = URL(string: cover), !cover.isEmpty { return url }
        if let thumbnail, let url = URL(string: thumbnail), !thumbnail.isEmpty { return url }
        return nil
    }

    var thumbnailURL: URL? {
        if let thumbnail, let url = URL(string: thumbnail), !thumbnail.isEmpty { return url }
        if let cover, let url = URL(string: cover), !cover.isEmpty { return url }
        return nil
    }

    init(
        id: String,
        name: String,
        description: String? = nil,
        cover: String? = nil,
        thumbnail: String? = nil,
        gifs: Int = 0,
        subscribers: Int = 0
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.cover = cover
        self.thumbnail = thumbnail
        self.gifs = gifs
        self.subscribers = subscribers
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case cover
        case thumbnail
        case gifs
        case subscribers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedId: String? =
            (try? container.decodeIfPresent(String.self, forKey: .id))
            ?? (try? container.decodeIfPresent(Int.self, forKey: .id)).map(String.init)
        let decodedName = try? container.decodeIfPresent(String.self, forKey: .name)
        self.name = decodedName ?? decodedId ?? "Niche"
        self.id = decodedId ?? decodedName ?? UUID().uuidString
        self.description = try? container.decodeIfPresent(String.self, forKey: .description)
        self.cover = try? container.decodeIfPresent(String.self, forKey: .cover)
        self.thumbnail = try? container.decodeIfPresent(String.self, forKey: .thumbnail)
        self.gifs = container.decodeFlexibleInt(forKey: .gifs) ?? 0
        self.subscribers = container.decodeFlexibleInt(forKey: .subscribers) ?? 0
    }
}

struct NichePreviewItem: Codable, Sendable, Identifiable, Hashable {
    let niche: NicheSummary
    let gif: GifItem?
    let user: CreatorUser?

    var id: String { niche.id }

    enum CodingKeys: String, CodingKey {
        case niche
        case gif
        case user
    }

    init(niche: NicheSummary, gif: GifItem? = nil, user: CreatorUser? = nil) {
        self.niche = niche
        self.gif = gif
        self.user = user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let nestedNiche = try? container.decode(NicheSummary.self, forKey: .niche) {
            self.niche = nestedNiche
            self.gif = try? container.decodeIfPresent(GifItem.self, forKey: .gif)
            self.user = try? container.decodeIfPresent(CreatorUser.self, forKey: .user)
        } else {
            self.niche = try NicheSummary(from: decoder)
            self.gif = nil
            self.user = nil
        }
    }
}

struct NichePreviewsEnvelope: Codable, Sendable, Hashable {
    let previews: [NichePreviewItem]
    let page: Int
    let pages: Int
    let total: Int

    init(previews: [NichePreviewItem] = [], page: Int = 1, pages: Int = 1, total: Int = 0) {
        self.previews = previews
        self.page = page
        self.pages = pages
        self.total = total
    }

    enum CodingKeys: String, CodingKey {
        case previews
        case niches
        case page
        case pages
        case total
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedPreviews = try? container.decode([NichePreviewItem].self, forKey: .previews) {
            self.previews = decodedPreviews
        } else if let directNiches = try? container.decode([NicheSummary].self, forKey: .niches) {
            self.previews = directNiches.map { NichePreviewItem(niche: $0) }
        } else {
            self.previews = []
        }
        self.page = container.decodeFlexibleInt(forKey: .page) ?? 1
        self.pages = container.decodeFlexibleInt(forKey: .pages) ?? 1
        self.total = container.decodeFlexibleInt(forKey: .total) ?? previews.count
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(previews, forKey: .previews)
        try container.encode(page, forKey: .page)
        try container.encode(pages, forKey: .pages)
        try container.encode(total, forKey: .total)
    }
}

// MARK: - Auxiliary Responses

struct NicheDetailEnvelope: Decodable, Sendable {
    let niche: NicheSummary
}

struct TrendingTag: Codable, Sendable, Identifiable, Hashable {
    let name: String
    let count: Int?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case count
    }

    init(name: String, count: Int? = nil) {
        self.name = name
        self.count = count
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let rawName = try? single.decode(String.self) {
            self.name = rawName
            self.count = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = (try? container.decode(String.self, forKey: .name)) ?? ""
        self.count = container.decodeFlexibleInt(forKey: .count)
    }
}

struct TrendingTagsEnvelope: Decodable, Sendable {
    let tags: [TrendingTag]

    enum CodingKeys: String, CodingKey {
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tags = (try? container.decode([TrendingTag].self, forKey: .tags)) ?? []
    }
}

struct TopCreatorsEnvelope: Decodable, Sendable {
    let creators: [CreatorUser]

    enum CodingKeys: String, CodingKey {
        case creators
        case users
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let creators = try? container.decode([CreatorUser].self, forKey: .creators) {
            self.creators = creators
        } else if let users = try? container.decode([CreatorUser].self, forKey: .users) {
            self.creators = users
        } else {
            self.creators = []
        }
    }
}

struct SocialsEnvelope: Decodable, Sendable {
    let links: [String]

    enum CodingKeys: String, CodingKey {
        case links
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.links = FeedEnvelope.decodeFlexibleStringArray(from: container, forKey: .links)
    }
}

struct CreatorTagsEnvelope: Decodable, Sendable {
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tags = FeedEnvelope.decodeFlexibleStringArray(from: container, forKey: .tags)
    }
}

struct GifDetailEnvelope: Decodable, Sendable {
    let gif: GifItem
    let user: CreatorUser?
    let users: [CreatorUser]
    let niches: [NicheSummary]

    enum CodingKeys: String, CodingKey {
        case gif
        case user
        case users
        case niches
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.gif = try container.decode(GifItem.self, forKey: .gif)
        self.user = try? container.decodeIfPresent(CreatorUser.self, forKey: .user)
        self.users = (try? container.decode([CreatorUser].self, forKey: .users)) ?? []
        self.niches = (try? container.decode([NicheSummary].self, forKey: .niches)) ?? []
    }
}

struct CreatorProfileBundle: Sendable {
    let user: CreatorUser?
    let feed: FeedEnvelope
    let pins: [GifItem]
    let socials: [String]
    let tags: [String]
}

// MARK: - Feed & Sort Enums

enum FeedMode: String, CaseIterable, Identifiable, Sendable {
    case trending
    case latest
    case topWeek
    case topMonth
    case images

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trending: return "Trending"
        case .latest: return "Latest"
        case .topWeek: return "Top 7d"
        case .topMonth: return "Top 28d"
        case .images: return "Images"
        }
    }

    var searchOrder: String {
        switch self {
        case .trending: return "trending"
        case .latest: return "latest"
        case .topWeek: return "top7"
        case .topMonth: return "top28"
        case .images: return "latest"
        }
    }

    var mediaType: String {
        self == .images ? "i" : "g"
    }
}

enum SearchOrder: String, CaseIterable, Identifiable, Sendable {
    case trending = "trending"
    case latest = "latest"
    case score = "score"
    case topWeek = "top7"
    case topMonth = "top28"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trending: return "Trending"
        case .latest: return "Latest"
        case .score: return "Top Score"
        case .topWeek: return "Top Week"
        case .topMonth: return "Top Month"
        }
    }
}

enum NicheSortOrder: String, CaseIterable, Identifiable, Sendable {
    case subscribers = "subscribers"
    case posts = "posts"
    case alphabeticalAsc = "alphabetical_asc"
    case alphabeticalDesc = "alphabetical_desc"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subscribers: return "Subscribers"
        case .posts: return "Most Posts"
        case .alphabeticalAsc: return "Name A–Z"
        case .alphabeticalDesc: return "Name Z–A"
        }
    }
}

// MARK: - Resilient Decoding Helpers

private struct FlexibleNamedValue: Decodable {
    let resolvedString: String?

    enum CodingKeys: String, CodingKey {
        case name
        case url
        case link
        case id
        case tag
        case value
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let str = try? single.decode(String.self) {
            resolvedString = str
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var resolved: String?
        for key in [CodingKeys.url, .link, .name, .tag, .value, .id] {
            if let value = try? container.decodeIfPresent(String.self, forKey: key), !value.isEmpty {
                resolved = value
                break
            }
        }
        resolvedString = resolved
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let doubleValue = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(doubleValue)
        }
        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return Int(stringValue)
        }
        return nil
    }

    func decodeFlexibleDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(intValue)
        }
        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return Double(stringValue)
        }
        return nil
    }
}
