import Foundation
import Observation

@Observable
@MainActor
final class CreatorProfileViewModel {
    let username: String

    var mediaType: String = "g"

    private(set) var user: CreatorUser?
    private(set) var items: [GifItem] = []
    private(set) var pins: [GifItem] = []
    private(set) var socials: [String] = []
    private(set) var tags: [String] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private(set) var hasMore = true

    private var currentPage = 1
    private var seenIDs: Set<String> = []
    private let pageSize = 40
    private let apiClient: RedGifsAPIClient

    init(
        username: String,
        initialUser: CreatorUser? = nil,
        apiClient: RedGifsAPIClient = .shared
    ) {
        self.username = username
        self.user = initialUser
        self.apiClient = apiClient
    }

    var resolvedUser: CreatorUser {
        user ?? CreatorUser(username: username)
    }

    var usersMap: [String: CreatorUser] {
        [resolvedUser.username.lowercased(): resolvedUser]
    }

    func loadInitialIfNeeded() async {
        guard items.isEmpty && !isLoading else { return }
        await reloadAll()
    }

    func reloadAll() async {
        isLoading = true
        errorMessage = nil
        currentPage = 1

        do {
            let bundle = try await apiClient.creatorProfile(username: username, mediaType: mediaType)
            if let fetchedUser = bundle.user {
                user = fetchedUser
            }
            seenIDs.removeAll()
            items = deduplicated(bundle.feed.gifs)
            pins = bundle.pins
            socials = bundle.socials
            tags = bundle.tags
            hasMore = !items.isEmpty && (bundle.feed.pages <= 1 || bundle.feed.page < bundle.feed.pages)
        } catch {
            if items.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    func switchMediaType(_ newType: String) async {
        guard newType != mediaType else { return }
        mediaType = newType
        isLoading = true
        errorMessage = nil
        currentPage = 1

        do {
            let envelope = try await apiClient.creatorFeed(
                username: username,
                mediaType: mediaType,
                order: "new",
                count: pageSize,
                page: 1
            )
            if user == nil, let fetchedUser = envelope.users.first {
                user = fetchedUser
            }
            seenIDs.removeAll()
            items = deduplicated(envelope.gifs)
            hasMore = !items.isEmpty && (envelope.pages <= 1 || envelope.page < envelope.pages)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadMoreIfNeeded(forGifID id: String) async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        guard let index = items.firstIndex(where: { $0.id == id }),
              index >= max(0, items.count - 8) else { return }

        isLoadingMore = true
        let nextPage = currentPage + 1
        if let envelope = try? await apiClient.creatorFeed(
            username: username,
            mediaType: mediaType,
            order: "new",
            count: pageSize,
            page: nextPage
        ) {
            let fresh = deduplicated(envelope.gifs)
            if !fresh.isEmpty {
                items.append(contentsOf: fresh)
                currentPage = nextPage
            }
            hasMore = !fresh.isEmpty && (envelope.pages <= 1 || envelope.page < envelope.pages)
        }
        isLoadingMore = false
    }

    private func deduplicated(_ incoming: [GifItem]) -> [GifItem] {
        var accepted: [GifItem] = []
        accepted.reserveCapacity(incoming.count)
        for gif in incoming where seenIDs.insert(gif.id).inserted {
            accepted.append(gif)
        }
        return accepted
    }
}
