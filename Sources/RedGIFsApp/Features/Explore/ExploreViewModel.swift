import Foundation
import Observation

enum ExploreScope: String, CaseIterable, Identifiable, Sendable {
    case videos = "Videos"
    case images = "Images"
    case creators = "Creators"
    case niches = "Niches"

    var id: String { rawValue }
}

@Observable
@MainActor
final class ExploreViewModel {
    var query = ""
    var scope: ExploreScope = .videos
    var sortOrder: SearchOrder = .trending
    var verifiedOnly = false

    private(set) var trendingTags: [TrendingTag] = []
    private(set) var trendingCreators: [CreatorUser] = []
    private(set) var featuredNiches: [NichePreviewItem] = []
    private(set) var popularGifs: [GifItem] = []

    private(set) var searchGifs: [GifItem] = []
    private(set) var searchCreators: [CreatorUser] = []
    private(set) var searchNiches: [NichePreviewItem] = []
    private(set) var usersByUsername: [String: CreatorUser] = [:]

    private(set) var isLoadingDiscovery = false
    private(set) var isSearching = false
    private(set) var isLoadingMore = false
    private(set) var discoveryError: String?
    private(set) var searchError: String?
    private(set) var hasMoreResults = true

    private var currentPage = 1
    private var seenGifIDs: Set<String> = []
    private let pageSize = 30
    private let apiClient: RedGifsAPIClient

    init(apiClient: RedGifsAPIClient = .shared) {
        self.apiClient = apiClient
    }

    var isShowingSearchResults: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func loadDiscoveryIfNeeded() async {
        guard popularGifs.isEmpty && trendingTags.isEmpty && !isLoadingDiscovery else { return }
        await refreshDiscovery()
    }

    func refreshDiscovery() async {
        isLoadingDiscovery = true
        discoveryError = nil

        async let tagsTask = try? apiClient.trendingTags()
        async let creatorsTask = try? apiClient.searchCreators(order: "trending", page: 1, count: 16)
        async let nichesTask = try? apiClient.searchNiches(order: "subscribers", page: 1, count: 12)
        async let popularTask: Result<FeedEnvelope, Error> = {
            do {
                return .success(try await apiClient.trendingFeed(page: 1, count: pageSize))
            } catch {
                return .failure(error)
            }
        }()

        let tags = await tagsTask
        let creatorsEnvelope = await creatorsTask
        let nichesEnvelope = await nichesTask
        let popularResult = await popularTask

        if let tags {
            trendingTags = tags
        }
        if let creatorsEnvelope {
            trendingCreators = creatorsEnvelope.users
            mergeUsers(creatorsEnvelope.users)
        }
        if let nichesEnvelope {
            featuredNiches = nichesEnvelope.previews
        }

        switch popularResult {
        case .success(let envelope):
            mergeUsers(envelope.users)
            popularGifs = deduplicatedGifs(envelope.gifs, reset: true)
            if trendingCreators.isEmpty && !envelope.users.isEmpty {
                trendingCreators = Array(envelope.users.prefix(16))
            }
        case .failure(let error):
            if trendingTags.isEmpty && featuredNiches.isEmpty && popularGifs.isEmpty {
                discoveryError = error.localizedDescription
            }
        }

        isLoadingDiscovery = false
    }

    func performSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearSearchResults()
            return
        }

        isSearching = true
        searchError = nil
        currentPage = 1

        do {
            try await executeSearchPage(query: trimmed, page: 1, reset: true)
        } catch {
            searchError = error.localizedDescription
        }
        isSearching = false
    }

    func selectTag(_ tag: String) async {
        query = tag
        scope = .videos
        await performSearch()
    }

    func clearSearchResults() {
        searchGifs = []
        searchCreators = []
        searchNiches = []
        searchError = nil
        currentPage = 1
        hasMoreResults = true
    }

    func loadMoreIfNeeded(forGifID id: String) async {
        guard isShowingSearchResults, hasMoreResults, !isSearching, !isLoadingMore else { return }
        guard let index = searchGifs.firstIndex(where: { $0.id == id }),
              index >= max(0, searchGifs.count - 6) else { return }
        await loadNextSearchPage()
    }

    func loadNextSearchPage() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, hasMoreResults, !isSearching, !isLoadingMore else { return }

        isLoadingMore = true
        let nextPage = currentPage + 1
        do {
            try await executeSearchPage(query: trimmed, page: nextPage, reset: false)
            currentPage = nextPage
        } catch {
            // Preserve existing results on pagination error.
        }
        isLoadingMore = false
    }

    // MARK: - Private

    private func executeSearchPage(query: String, page: Int, reset: Bool) async throws {
        switch scope {
        case .videos, .images:
            let mediaType = scope == .images ? "i" : "g"
            let envelope = try await apiClient.searchGifs(
                query: query,
                mediaType: mediaType,
                order: sortOrder.rawValue,
                count: pageSize,
                page: page,
                verifiedOnly: verifiedOnly
            )
            mergeUsers(envelope.users)
            let fresh = deduplicatedGifs(envelope.gifs, reset: reset)
            if reset {
                searchGifs = fresh
            } else {
                searchGifs.append(contentsOf: fresh)
            }
            hasMoreResults = !fresh.isEmpty && (envelope.pages <= 1 || envelope.page < envelope.pages)

        case .creators:
            let creatorOrder = (sortOrder == .latest) ? "latest" : (sortOrder == .trending ? "trending" : "best_match")
            let envelope = try await apiClient.searchCreators(
                query: query,
                order: creatorOrder,
                page: page,
                count: pageSize,
                verifiedOnly: verifiedOnly
            )
            mergeUsers(envelope.users)
            if reset {
                searchCreators = envelope.users
            } else {
                let existing = Set(searchCreators.map(\.username))
                let unique = envelope.users.filter { !existing.contains($0.username) }
                searchCreators.append(contentsOf: unique)
            }
            hasMoreResults = !envelope.users.isEmpty && (envelope.pages <= 1 || envelope.page < envelope.pages)

        case .niches:
            let envelope = try await apiClient.searchNiches(
                query: query,
                order: "subscribers",
                page: page,
                count: pageSize
            )
            if reset {
                searchNiches = envelope.previews
            } else {
                let existing = Set(searchNiches.map(\.id))
                let unique = envelope.previews.filter { !existing.contains($0.id) }
                searchNiches.append(contentsOf: unique)
            }
            hasMoreResults = !envelope.previews.isEmpty && (envelope.pages <= 1 || envelope.page < envelope.pages)
        }
    }

    private func mergeUsers(_ users: [CreatorUser]) {
        for user in users {
            usersByUsername[user.username.lowercased()] = user
        }
    }

    private func deduplicatedGifs(_ incoming: [GifItem], reset: Bool) -> [GifItem] {
        if reset {
            seenGifIDs.removeAll()
        }
        var accepted: [GifItem] = []
        accepted.reserveCapacity(incoming.count)
        for gif in incoming where seenGifIDs.insert(gif.id).inserted {
            accepted.append(gif)
        }
        return accepted
    }
}
