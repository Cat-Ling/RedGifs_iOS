import SwiftUI

struct ExploreView: View {
    @Environment(LocalLibraryStore.self) private var libraryStore
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(VideoPlayerCoordinator.self) private var playerCoordinator

    @State private var viewModel = ExploreViewModel()
    @State private var immersiveSelection: ImmersiveFeedSelection?

    var body: some View {
        @Bindable var router = deepLinkRouter

        NavigationStack(path: $router.exploreNavigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if viewModel.isShowingSearchResults {
                        searchControlsBar
                        searchResultsContent
                    } else {
                        discoveryContent
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(AppTheme.background)
            .navigationTitle("Explore")
            .searchable(
                text: $viewModel.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search videos, creators, tags, or paste link"
            )
            .onSubmit(of: .search) {
                let trimmed = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
                if DeepLinkParser.looksLikeExplicitLink(trimmed),
                   deepLinkRouter.open(rawURLString: trimmed, playerCoordinator: playerCoordinator) {
                    viewModel.query = ""
                    viewModel.clearSearchResults()
                    return
                }
                Task { await viewModel.performSearch() }
            }
            .onChange(of: viewModel.query) { _, newValue in
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    viewModel.clearSearchResults()
                }
            }
            .onChange(of: viewModel.scope) { _, _ in
                if viewModel.isShowingSearchResults {
                    Task { await viewModel.performSearch() }
                }
            }
            .onChange(of: viewModel.sortOrder) { _, _ in
                if viewModel.isShowingSearchResults {
                    Task { await viewModel.performSearch() }
                }
            }
            .onChange(of: viewModel.verifiedOnly) { _, _ in
                if viewModel.isShowingSearchResults {
                    Task { await viewModel.performSearch() }
                }
            }
            .refreshable {
                if viewModel.isShowingSearchResults {
                    await viewModel.performSearch()
                } else {
                    await viewModel.refreshDiscovery()
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .creator(let username, let initialUser):
                    CreatorProfileView(username: username, initialUser: initialUser)
                case .niche(let niche):
                    NicheDetailView(niche: niche)
                case .tagSearch(let tag):
                    TagFeedGridView(tag: tag)
                }
            }
            .fullScreenCover(item: $immersiveSelection) { selection in
                ImmersiveFeedView(selection: selection)
            }
        }
        .task {
            await applyPendingSearchIfNeeded()
            await viewModel.loadDiscoveryIfNeeded()
        }
        .onChange(of: deepLinkRouter.pendingSearchRequest) { _, _ in
            Task {
                await applyPendingSearchIfNeeded()
            }
        }
    }

    private func applyPendingSearchIfNeeded() async {
        guard let request = deepLinkRouter.pendingSearchRequest else { return }
        deepLinkRouter.pendingSearchRequest = nil
        viewModel.query = request.query
        viewModel.scope = request.scope
        if let order = request.order {
            viewModel.sortOrder = order
        }
        await viewModel.performSearch()
    }

    // MARK: - Discovery Mode

    @ViewBuilder
    private var discoveryContent: some View {
        if viewModel.isLoadingDiscovery && viewModel.popularGifs.isEmpty && viewModel.trendingTags.isEmpty {
            ProgressView()
                .tint(AppTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, 90)
        } else if let error = viewModel.discoveryError, viewModel.popularGifs.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Explore", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") {
                    Task { await viewModel.refreshDiscovery() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
            .padding(.top, 60)
        } else {
            if !viewModel.trendingTags.isEmpty {
                ExploreSectionHeader(title: "Trending Tags", systemImage: "flame.fill")
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.trendingTags.prefix(24)) { tag in
                            Button {
                                Task { await viewModel.selectTag(tag.name) }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("#\(tag.name)")
                                        .font(.subheadline.weight(.semibold))
                                    if let count = tag.count {
                                        Text(MetricFormatter.compactCount(count))
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.surfaceElevated, in: Capsule())
                                .overlay {
                                    Capsule().strokeBorder(AppTheme.hairline, lineWidth: 0.75)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if !viewModel.trendingCreators.isEmpty {
                ExploreSectionHeader(title: "Trending Creators", systemImage: "person.2.fill")
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(viewModel.trendingCreators) { creator in
                            NavigationLink(value: AppRoute.creator(username: creator.username, initialUser: creator)) {
                                VStack(spacing: 6) {
                                    AvatarView(url: creator.avatarURL, name: creator.displayName, size: 64)
                                        .overlay {
                                            Circle().strokeBorder(AppTheme.accent.opacity(0.65), lineWidth: 1.5)
                                        }
                                    HStack(spacing: 3) {
                                        Text(creator.displayName)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        if creator.verified {
                                            Image(systemName: "checkmark.seal.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.cyan)
                                        }
                                    }
                                    Text("\(MetricFormatter.compactCount(creator.followers)) followers")
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                                .frame(width: 90)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if !viewModel.featuredNiches.isEmpty {
                ExploreSectionHeader(title: "Popular Niches", systemImage: "square.grid.2x2.fill")
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(viewModel.featuredNiches) { preview in
                            NavigationLink(value: AppRoute.niche(preview.niche)) {
                                NicheCarouselCard(preview: preview)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if !viewModel.popularGifs.isEmpty {
                ExploreSectionHeader(title: "Popular Now", systemImage: "sparkles")
                MediaGridView(
                    items: viewModel.popularGifs,
                    savedIDs: Set(libraryStore.savedGifs.map(\.id)),
                    onSelect: { gif in
                        immersiveSelection = ImmersiveFeedSelection(
                            title: "Popular Now",
                            items: viewModel.popularGifs,
                            initialGifID: gif.id,
                            usersByUsername: viewModel.usersByUsername
                        )
                    }
                )
            }
        }
    }

    // MARK: - Search Results Mode

    private var searchControlsBar: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ExploreScope.allCases) { itemScope in
                        let isSelected = viewModel.scope == itemScope
                        Button {
                            viewModel.scope = itemScope
                        } label: {
                            Text(itemScope.rawValue)
                                .font(.subheadline.weight(isSelected ? .bold : .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    isSelected ? AnyShapeStyle(AppTheme.accentGradient) : AnyShapeStyle(AppTheme.surfaceElevated),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)

            if viewModel.scope != .niches {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(SearchOrder.allCases) { order in
                            Button {
                                viewModel.sortOrder = order
                            } label: {
                                if viewModel.sortOrder == order {
                                    Label(order.title, systemImage: "checkmark")
                                } else {
                                    Text(order.title)
                                }
                            }
                        }
                    } label: {
                        Label(viewModel.sortOrder.title, systemImage: "arrow.up.arrow.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(AppTheme.surfaceElevated, in: Capsule())
                    }

                    Button {
                        viewModel.verifiedOnly.toggle()
                    } label: {
                        Label("Verified", systemImage: viewModel.verifiedOnly ? "checkmark.seal.fill" : "checkmark.seal")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(viewModel.verifiedOnly ? .cyan : .white.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(AppTheme.surfaceElevated, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        if viewModel.isSearching {
            ProgressView()
                .tint(AppTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        } else if let error = viewModel.searchError {
            ContentUnavailableView {
                Label("Search Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") {
                    Task { await viewModel.performSearch() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
            .padding(.top, 50)
        } else {
            switch viewModel.scope {
            case .videos, .images:
                if viewModel.searchGifs.isEmpty {
                    ContentUnavailableView.search(text: viewModel.query)
                        .padding(.top, 50)
                } else {
                    MediaGridView(
                        items: viewModel.searchGifs,
                        savedIDs: Set(libraryStore.savedGifs.map(\.id)),
                        onSelect: { gif in
                            immersiveSelection = ImmersiveFeedSelection(
                                title: viewModel.query,
                                items: viewModel.searchGifs,
                                initialGifID: gif.id,
                                usersByUsername: viewModel.usersByUsername
                            )
                        },
                        onItemAppear: { gif in
                            Task { await viewModel.loadMoreIfNeeded(forGifID: gif.id) }
                        }
                    )
                }

            case .creators:
                if viewModel.searchCreators.isEmpty {
                    ContentUnavailableView.search(text: viewModel.query)
                        .padding(.top, 50)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.searchCreators) { creator in
                            NavigationLink(value: AppRoute.creator(username: creator.username, initialUser: creator)) {
                                CreatorRowCard(creator: creator)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

            case .niches:
                if viewModel.searchNiches.isEmpty {
                    ContentUnavailableView.search(text: viewModel.query)
                        .padding(.top, 50)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.searchNiches) { preview in
                            NavigationLink(value: AppRoute.niche(preview.niche)) {
                                NicheListRow(preview: preview)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Explore Subviews

private struct ExploreSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
    }
}

private struct NicheCarouselCard: View {
    let preview: NichePreviewItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedRemoteImage(
                url: preview.niche.thumbnailURL ?? preview.gif?.previewImageURL,
                contentMode: .fill,
                placeholderColor: AppTheme.surfaceElevated
            )
            .frame(width: 155, height: 112)

            LinearGradient(
                colors: [.clear, .black.opacity(0.84)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(preview.niche.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(MetricFormatter.compactCount(preview.niche.subscribers)) subscribers")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(10)
        }
        .frame(width: 155, height: 112)
        .compositingGroup()
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 0.75)
        }
    }
}

struct CreatorRowCard: View {
    let creator: CreatorUser

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: creator.avatarURL, name: creator.displayName, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(creator.displayName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if creator.verified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.subheadline)
                            .foregroundStyle(.cyan)
                    }
                }
                Text("@\(creator.username)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                HStack(spacing: 12) {
                    Text("\(MetricFormatter.compactCount(creator.followers)) followers")
                    Text("\(MetricFormatter.compactCount(creator.views)) views")
                }
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 0.5)
        }
    }
}

struct NicheListRow: View {
    let preview: NichePreviewItem

    var body: some View {
        HStack(spacing: 12) {
            CachedRemoteImage(
                url: preview.niche.thumbnailURL ?? preview.gif?.previewImageURL,
                contentMode: .fill,
                placeholderColor: AppTheme.surfaceElevated
            )
            .frame(width: 64, height: 64)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(preview.niche.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let desc = preview.niche.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    Label(MetricFormatter.compactCount(preview.niche.subscribers), systemImage: "person.2.fill")
                    Label(MetricFormatter.compactCount(preview.niche.gifs), systemImage: "film")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(10)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 0.5)
        }
    }
}
