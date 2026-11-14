import SwiftUI

struct NicheDetailView: View {
    @Environment(LocalLibraryStore.self) private var libraryStore

    let niche: NicheSummary

    @State private var resolvedNiche: NicheSummary
    @State private var items: [GifItem] = []
    @State private var topCreators: [CreatorUser] = []
    @State private var usersByUsername: [String: CreatorUser] = [:]
    @State private var order: String = "hot"
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var immersiveSelection: ImmersiveFeedSelection?

    init(niche: NicheSummary) {
        self.niche = niche
        self._resolvedNiche = State(initialValue: niche)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard

                if !topCreators.isEmpty {
                    topCreatorsStrip
                }

                sortBar

                mediaSection
            }
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .navigationTitle(resolvedNiche.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(niche.id)-\(order)") {
            await loadAll()
        }
        .fullScreenCover(item: $immersiveSelection) { selection in
            ImmersiveFeedView(selection: selection)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CachedRemoteImage(
                url: resolvedNiche.coverURL ?? items.first?.previewImageURL,
                contentMode: .fill,
                placeholderColor: AppTheme.surfaceElevated
            )
            .frame(height: 165)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 12) {
                    CachedRemoteImage(
                        url: resolvedNiche.thumbnailURL ?? items.first?.previewImageURL,
                        contentMode: .fill,
                        placeholderColor: AppTheme.surface
                    )
                    .frame(width: 60, height: 60)
                    .clipShape(.rect(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(resolvedNiche.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        HStack(spacing: 12) {
                            Label("\(MetricFormatter.compactCount(resolvedNiche.subscribers)) subscribers", systemImage: "person.2.fill")
                                .lineLimit(1)
                            if resolvedNiche.gifs > 0 {
                                Label("\(MetricFormatter.compactCount(resolvedNiche.gifs)) posts", systemImage: "film")
                                    .lineLimit(1)
                            }
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    let saved = libraryStore.isNicheSaved(resolvedNiche.id)
                    Button {
                        libraryStore.toggleSave(niche: resolvedNiche)
                    } label: {
                        Label(saved ? "Saved" : "Save", systemImage: saved ? "bookmark.fill" : "bookmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                saved ? AnyShapeStyle(AppTheme.surfaceElevated) : AnyShapeStyle(AppTheme.accentGradient),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .sensoryFeedback(.selection, trigger: saved)
                }
                .padding(14)
            }
            .compositingGroup()
            .clipShape(.rect(cornerRadius: 18, style: .continuous))

            if let desc = resolvedNiche.description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var topCreatorsStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top Creators")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(topCreators) { creator in
                        NavigationLink(value: AppRoute.creator(username: creator.username, initialUser: creator)) {
                            VStack(spacing: 6) {
                                AvatarView(url: creator.avatarURL, name: creator.displayName, size: 54)
                                Text(creator.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            .frame(width: 76)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var sortBar: some View {
        HStack(spacing: 8) {
            nicheSortPill(title: "Hot", value: "hot")
            nicheSortPill(title: "Top", value: "top")
            nicheSortPill(title: "Latest", value: "latest")
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    private func nicheSortPill(title: String, value: String) -> some View {
        let selected = order == value
        return Button {
            order = value
        } label: {
            Text(title)
                .font(.caption.weight(selected ? .bold : .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    selected ? AnyShapeStyle(AppTheme.accentGradient) : AnyShapeStyle(AppTheme.surfaceElevated),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var mediaSection: some View {
        if isLoading && items.isEmpty {
            ProgressView()
                .tint(AppTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, 50)
        } else if let errorMessage, items.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Niche", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Retry") {
                    Task { await loadAll() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
            .padding(.top, 30)
        } else if items.isEmpty {
            ContentUnavailableView(
                "No Media Yet",
                systemImage: "film.stack",
                description: Text("No posts found in this niche.")
            )
            .padding(.top, 30)
        } else {
            MediaGridView(
                items: items,
                savedIDs: Set(libraryStore.savedGifs.map(\.id)),
                onSelect: { gif in
                    immersiveSelection = ImmersiveFeedSelection(
                        title: resolvedNiche.name,
                        items: items,
                        initialGifID: gif.id,
                        usersByUsername: usersByUsername
                    )
                },
                onItemAppear: { gif in
                    if let idx = items.firstIndex(where: { $0.id == gif.id }),
                       idx >= max(0, items.count - 6) {
                        Task { await loadMore() }
                    }
                }
            )
            .padding(.horizontal, 14)
        }
    }

    private func loadAll() async {
        isLoading = true
        errorMessage = nil
        page = 1

        async let creatorsTask = try? RedGifsAPIClient.shared.nicheTopCreators(nicheId: niche.id)
        async let nicheInfoTask = try? RedGifsAPIClient.shared.nicheDetail(nicheId: niche.id)
        do {
            let envelope = try await RedGifsAPIClient.shared.nicheGifs(
                nicheId: niche.id,
                order: order,
                page: 1,
                count: 30
            )
            items = envelope.gifs
            for user in envelope.users {
                usersByUsername[user.username.lowercased()] = user
            }
            if let matchedNiche = envelope.niches.first(where: {
                $0.id.caseInsensitiveCompare(niche.id) == .orderedSame
                    || $0.name.caseInsensitiveCompare(niche.name) == .orderedSame
            }) {
                resolvedNiche = matchedNiche
            }
            hasMore = !envelope.gifs.isEmpty && (envelope.pages <= 1 || envelope.page < envelope.pages)
        } catch {
            errorMessage = error.localizedDescription
        }

        if let fetchedNiche = await nicheInfoTask {
            resolvedNiche = fetchedNiche
        }
        if let fetchedCreators = await creatorsTask {
            topCreators = fetchedCreators
            for user in fetchedCreators {
                usersByUsername[user.username.lowercased()] = user
            }
        }
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        let nextPage = page + 1
        if let envelope = try? await RedGifsAPIClient.shared.nicheGifs(
            nicheId: niche.id,
            order: order,
            page: nextPage,
            count: 30
        ) {
            let existing = Set(items.map(\.id))
            let fresh = envelope.gifs.filter { !existing.contains($0.id) }
            items.append(contentsOf: fresh)
            for user in envelope.users {
                usersByUsername[user.username.lowercased()] = user
            }
            page = nextPage
            hasMore = !fresh.isEmpty && (envelope.pages <= 1 || envelope.page < envelope.pages)
        }
        isLoadingMore = false
    }
}
