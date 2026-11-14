import Foundation
import Observation

@Observable
@MainActor
final class FeedViewModel {
    private(set) var items: [GifItem] = []
    private(set) var usersByUsername: [String: CreatorUser] = [:]
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private(set) var hasMore = true

    var mode: FeedMode = .trending
    var verifiedOnly = false

    private var currentPage = 1
    private var seenIDs: Set<String> = []
    private var pinnedLeadingItems: [GifItem] = []
    private var pinnedUsers: [String: CreatorUser] = [:]
    private let pageSize = 30
    private let apiClient: RedGifsAPIClient
    private let customLoader: (@MainActor @Sendable (Int) async throws -> FeedEnvelope)?

    init(
        apiClient: RedGifsAPIClient = .shared,
        initialItems: [GifItem] = [],
        initialUsers: [String: CreatorUser] = [:],
        customLoader: (@MainActor @Sendable (Int) async throws -> FeedEnvelope)? = nil
    ) {
        self.apiClient = apiClient
        self.customLoader = customLoader
        if !initialItems.isEmpty {
            self.items = initialItems
            self.seenIDs = Set(initialItems.map(\.id))
            self.usersByUsername = initialUsers
            self.hasMore = customLoader != nil
        }
    }

    func loadInitialIfNeeded() async {
        guard items.isEmpty && !isLoading else { return }
        await loadFirstPage()
    }

    func refresh() async {
        await loadFirstPage()
    }

    func switchMode(_ newMode: FeedMode) async {
        guard newMode != mode else { return }
        mode = newMode
        await loadFirstPage()
    }

    func toggleVerifiedOnly() async {
        verifiedOnly.toggle()
        await loadFirstPage()
    }

    func prependAndFocus(gif: GifItem, users: [CreatorUser]) {
        for user in users {
            let key = user.username.lowercased()
            pinnedUsers[key] = user
            usersByUsername[key] = user
        }
        pinnedLeadingItems.removeAll { $0.id == gif.id }
        pinnedLeadingItems.insert(gif, at: 0)

        items.removeAll { $0.id == gif.id }
        items.insert(gif, at: 0)
        seenIDs.insert(gif.id)
        errorMessage = nil
    }

    func loadMoreIfNeeded(currentID: String?) async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        guard let currentID,
              let index = items.firstIndex(where: { $0.id == currentID }),
              index >= max(0, items.count - 4) else {
            return
        }
        await loadNextPage()
    }

    func neighbors(for gifID: String) -> [GifItem] {
        guard let index = items.firstIndex(where: { $0.id == gifID }) else {
            return []
        }
        var result: [GifItem] = []
        if index + 1 < items.count {
            result.append(items[index + 1])
        }
        if index - 1 >= 0 {
            result.append(items[index - 1])
        }
        return result
    }

    func creator(for gif: GifItem) -> CreatorUser? {
        guard let username = gif.userName?.lowercased() else { return nil }
        return usersByUsername[username]
    }

    // MARK: - Private Fetching

    private func loadFirstPage() async {
        isLoading = true
        errorMessage = nil
        currentPage = 1

        do {
            let envelope = try await fetchPage(1)
            seenIDs.removeAll()
            usersByUsername.removeAll()
            if mode == .trending && !verifiedOnly {
                for (key, user) in pinnedUsers {
                    usersByUsername[key] = user
                }
            }
            mergeUsers(envelope.users)
            let leading = (mode == .trending && !verifiedOnly) ? deduplicated(pinnedLeadingItems) : []
            let fetched = deduplicated(envelope.gifs)
            items = leading + fetched
            hasMore = computeHasMore(envelope: envelope, fetchedCount: envelope.gifs.count)
        } catch {
            if items.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func loadNextPage() async {
        isLoadingMore = true
        let nextPage = currentPage + 1
        do {
            let envelope = try await fetchPage(nextPage)
            mergeUsers(envelope.users)
            let newItems = deduplicated(envelope.gifs)
            if !newItems.isEmpty {
                items.append(contentsOf: newItems)
                currentPage = nextPage
            }
            hasMore = !newItems.isEmpty && computeHasMore(envelope: envelope, fetchedCount: envelope.gifs.count)
        } catch {
            // Keep existing feed items intact on transient pagination error.
        }
        isLoadingMore = false
    }

    private func fetchPage(_ page: Int) async throws -> FeedEnvelope {
        if let customLoader {
            return try await customLoader(page)
        }
        if mode == .trending && !verifiedOnly {
            return try await apiClient.trendingFeed(page: page, count: pageSize, variation: "popular")
        }
        return try await apiClient.searchGifs(
            query: "",
            mediaType: mode.mediaType,
            order: mode.searchOrder,
            count: pageSize,
            page: page,
            verifiedOnly: verifiedOnly
        )
    }

    private func mergeUsers(_ users: [CreatorUser]) {
        for user in users {
            usersByUsername[user.username.lowercased()] = user
        }
    }

    private func deduplicated(_ incoming: [GifItem]) -> [GifItem] {
        var accepted: [GifItem] = []
        accepted.reserveCapacity(incoming.count)
        for item in incoming where seenIDs.insert(item.id).inserted {
            accepted.append(item)
        }
        return accepted
    }

    private func computeHasMore(envelope: FeedEnvelope, fetchedCount: Int) -> Bool {
        if envelope.pages > 1 {
            return envelope.page < envelope.pages
        }
        return fetchedCount > 0
    }
}
