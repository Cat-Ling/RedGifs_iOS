import Foundation
import Observation

@Observable
@MainActor
final class NichesViewModel {
    var query = ""
    var sortOrder: NicheSortOrder = .subscribers

    private(set) var previews: [NichePreviewItem] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private(set) var hasMore = true

    private var currentPage = 1
    private var seenIDs: Set<String> = []
    private let pageSize = 30
    private let apiClient: RedGifsAPIClient

    init(apiClient: RedGifsAPIClient = .shared) {
        self.apiClient = apiClient
    }

    func loadInitialIfNeeded() async {
        guard previews.isEmpty && !isLoading else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        currentPage = 1

        do {
            let envelope = try await apiClient.searchNiches(
                query: query,
                order: sortOrder.rawValue,
                page: 1,
                count: pageSize
            )
            seenIDs.removeAll()
            previews = deduplicated(envelope.previews)
            hasMore = !previews.isEmpty && (envelope.pages <= 1 || envelope.page < envelope.pages)
        } catch {
            if previews.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    func loadMoreIfNeeded(currentID: String?) async {
        guard hasMore, !isLoading, !isLoadingMore, let currentID else { return }
        guard let index = previews.firstIndex(where: { $0.id == currentID }),
              index >= max(0, previews.count - 6) else { return }

        isLoadingMore = true
        let nextPage = currentPage + 1
        do {
            let envelope = try await apiClient.searchNiches(
                query: query,
                order: sortOrder.rawValue,
                page: nextPage,
                count: pageSize
            )
            let fresh = deduplicated(envelope.previews)
            if !fresh.isEmpty {
                previews.append(contentsOf: fresh)
                currentPage = nextPage
            }
            hasMore = !fresh.isEmpty && (envelope.pages <= 1 || envelope.page < envelope.pages)
        } catch {
            // Keep existing previews on transient pagination failure.
        }
        isLoadingMore = false
    }

    private func deduplicated(_ incoming: [NichePreviewItem]) -> [NichePreviewItem] {
        var result: [NichePreviewItem] = []
        result.reserveCapacity(incoming.count)
        for item in incoming where seenIDs.insert(item.id).inserted {
            result.append(item)
        }
        return result
    }
}
