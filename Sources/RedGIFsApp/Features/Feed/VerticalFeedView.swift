import SwiftUI

struct VerticalFeedView: View {
    @Environment(VideoPlayerCoordinator.self) private var playerCoordinator
    @Environment(LocalLibraryStore.self) private var libraryStore
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    let isActiveTab: Bool

    @State private var viewModel = FeedViewModel()
    @State private var activeGifID: String?

    var body: some View {
        @Bindable var router = deepLinkRouter

        NavigationStack(path: $router.feedNavigationPath) {
            ZStack(alignment: .top) {
                AppTheme.background.ignoresSafeArea()

                feedContent

                topModeBar
            }
            .hiddenNavigationBar()
            .navigationDestination(for: AppRoute.self) { route in
                Group {
                    switch route {
                    case .creator(let username, let initialUser):
                        CreatorProfileView(username: username, initialUser: initialUser)
                    case .niche(let niche):
                        NicheDetailView(niche: niche)
                    case .tagSearch(let tag):
                        TagFeedGridView(tag: tag)
                    }
                }
                .visibleNavigationBar()
            }
        }
        .task {
            await applyPendingFeedModeIfNeeded()
            applyPendingResolvedMediaIfNeeded()
            await viewModel.loadInitialIfNeeded()
            applyPendingResolvedMediaIfNeeded()
            ensureInitialSelection()
        }
        .onChange(of: viewModel.items) { _, newItems in
            if activeGifID == nil || !newItems.contains(where: { $0.id == activeGifID }) {
                activeGifID = newItems.first?.id
            }
            activateCurrentItem()
        }
        .onChange(of: activeGifID) { _, newID in
            activateCurrentItem()
            Task {
                await viewModel.loadMoreIfNeeded(currentID: newID)
            }
        }
        .onChange(of: isActiveTab) { _, active in
            if active && deepLinkRouter.feedNavigationPath.isEmpty {
                activateCurrentItem()
            } else {
                playerCoordinator.pauseAll()
            }
        }
        .onChange(of: deepLinkRouter.feedNavigationPath.count) { _, depth in
            if depth == 0 && isActiveTab {
                activateCurrentItem()
            } else if depth > 0 {
                playerCoordinator.pauseAll()
            }
        }
        .onChange(of: deepLinkRouter.pendingFeedMode) { _, _ in
            Task {
                await applyPendingFeedModeIfNeeded()
            }
        }
        .onChange(of: deepLinkRouter.pendingResolvedMedia) { _, _ in
            applyPendingResolvedMediaIfNeeded()
        }
        .onChange(of: deepLinkRouter.coverDismissCounter) { _, _ in
            if isActiveTab && deepLinkRouter.feedNavigationPath.isEmpty {
                activateCurrentItem()
            }
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(AppTheme.accent)
                Text("Loading RedGIFs feed…")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Feed", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.white)
            } description: {
                Text(errorMessage)
                    .foregroundStyle(AppTheme.textSecondary)
            } actions: {
                Button("Retry") {
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.items) { gif in
                        feedCell(for: gif)
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(gif.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $activeGifID)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
        }
    }

    private func feedCell(for gif: GifItem) -> some View {
        let isActive = activeGifID == gif.id
        return VideoFeedCell(
            gif: gif,
            creator: viewModel.creator(for: gif),
            isActive: isActive,
            player: playerCoordinator.player(for: gif),
            preferAspectFill: playerCoordinator.preferAspectFill,
            isMuted: playerCoordinator.isMuted,
            isSaved: libraryStore.isGifSaved(gif.id),
            isPausedByUser: playerCoordinator.isPausedByUser,
            isBuffering: isActive && playerCoordinator.isBuffering,
            hasPlaybackError: playerCoordinator.failedGifIDs.contains(gif.id),
            progress: isActive ? playerCoordinator.progress : 0,
            currentTime: isActive ? playerCoordinator.currentTime : 0,
            duration: isActive ? playerCoordinator.duration : (gif.duration ?? 0),
            bottomPadding: 92,
            onTogglePlayPause: {
                playerCoordinator.togglePlayPause()
            },
            onDoubleTapSave: {
                libraryStore.ensureSaved(gif: gif)
            },
            onToggleSave: {
                libraryStore.toggleSave(gif: gif)
            },
            onToggleMute: {
                playerCoordinator.isMuted.toggle()
            },
            onToggleAspect: {
                playerCoordinator.preferAspectFill.toggle()
            },
            onRetryPlayback: {
                playerCoordinator.retry(gif: gif, neighbors: viewModel.neighbors(for: gif.id))
            },
            onSeek: { fraction in
                playerCoordinator.seek(to: fraction)
            },
            onSelectCreator: { username, creator in
                deepLinkRouter.feedNavigationPath.append(.creator(username: username, initialUser: creator))
            },
            onSelectTag: { tag in
                deepLinkRouter.feedNavigationPath.append(.tagSearch(tag))
            },
            onSelectNiche: { nicheName in
                let niche = NicheSummary(id: nicheName, name: nicheName)
                deepLinkRouter.feedNavigationPath.append(.niche(niche))
            }
        )
    }

    private var topModeBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(FeedMode.allCases) { mode in
                        let selected = viewModel.mode == mode
                        Button {
                            Task {
                                await viewModel.switchMode(mode)
                                activeGifID = viewModel.items.first?.id
                            }
                        } label: {
                            Text(mode.title)
                                .font(.subheadline.weight(selected ? .bold : .medium))
                                .foregroundStyle(selected ? .white : .white.opacity(0.75))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    selected ? AnyShapeStyle(AppTheme.accentGradient) : AnyShapeStyle(.clear),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
            }
            .scrollIndicators(.hidden)
            .glassSurface(cornerRadius: 22)

            Button {
                Task {
                    await viewModel.toggleVerifiedOnly()
                    activeGifID = viewModel.items.first?.id
                }
            } label: {
                Image(systemName: viewModel.verifiedOnly ? "checkmark.seal.fill" : "checkmark.seal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(viewModel.verifiedOnly ? .cyan : .white.opacity(0.85))
                    .padding(10)
                    .glassSurface(cornerRadius: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.verifiedOnly ? "Showing verified creators only" : "Filter verified creators")

            Button {
                playerCoordinator.preferHD.toggle()
            } label: {
                Text(playerCoordinator.preferHD ? "HD" : "SD")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(playerCoordinator.preferHD ? AppTheme.accent : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .glassSurface(cornerRadius: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle HD or SD playback")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func applyPendingFeedModeIfNeeded() async {
        guard let mode = deepLinkRouter.pendingFeedMode else { return }
        deepLinkRouter.pendingFeedMode = nil
        await viewModel.switchMode(mode)
        activeGifID = viewModel.items.first?.id
    }

    private func applyPendingResolvedMediaIfNeeded() {
        guard let media = deepLinkRouter.pendingResolvedMedia else { return }
        deepLinkRouter.pendingResolvedMedia = nil
        viewModel.prependAndFocus(gif: media.gif, users: media.users)
        activeGifID = media.gif.id
        activateCurrentItem()
    }

    private func ensureInitialSelection() {
        if activeGifID == nil {
            activeGifID = viewModel.items.first?.id
        }
        activateCurrentItem()
    }

    private func activateCurrentItem() {
        guard isActiveTab,
              deepLinkRouter.feedNavigationPath.isEmpty,
              deepLinkRouter.presentedImmersiveSelection == nil,
              !deepLinkRouter.isResolvingMedia else {
            return
        }
        guard let targetID = activeGifID ?? viewModel.items.first?.id,
              let gif = viewModel.items.first(where: { $0.id == targetID }) else {
            return
        }
        playerCoordinator.activate(gif: gif, neighbors: viewModel.neighbors(for: gif.id))
    }
}

// MARK: - Standalone Immersive Feed (Full-Screen Launch from Any Grid)

struct ImmersiveFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(VideoPlayerCoordinator.self) private var playerCoordinator
    @Environment(LocalLibraryStore.self) private var libraryStore

    let selection: ImmersiveFeedSelection
    let onLoadMore: (@MainActor @Sendable (Int) async throws -> FeedEnvelope)?

    @State private var viewModel: FeedViewModel
    @State private var activeGifID: String?
    @State private var navigationPath: [AppRoute] = []
    @State private var didCompleteInitialScroll = false

    init(
        selection: ImmersiveFeedSelection,
        onLoadMore: (@MainActor @Sendable (Int) async throws -> FeedEnvelope)? = nil
    ) {
        self.selection = selection
        self.onLoadMore = onLoadMore
        self._viewModel = State(
            initialValue: FeedViewModel(
                initialItems: selection.items,
                initialUsers: selection.usersByUsername,
                customLoader: onLoadMore
            )
        )
        self._activeGifID = State(initialValue: selection.initialGifID)
    }

    private var scrollPositionBinding: Binding<String?> {
        Binding(
            get: { activeGifID },
            set: { newValue in
                guard didCompleteInitialScroll else { return }
                activeGifID = newValue
            }
        )
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .top) {
                AppTheme.background.ignoresSafeArea()

                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.items) { gif in
                                immersiveCell(for: gif)
                                    .containerRelativeFrame([.horizontal, .vertical])
                                    .id(gif.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: scrollPositionBinding)
                    .scrollIndicators(.hidden)
                    .ignoresSafeArea()
                    .task(id: selection.id) {
                        didCompleteInitialScroll = false
                        activeGifID = selection.initialGifID
                        scrollProxy.scrollTo(selection.initialGifID, anchor: .top)
                        activateCurrent()
                        try? await Task.sleep(for: .milliseconds(60))
                        guard !Task.isCancelled else { return }
                        scrollProxy.scrollTo(selection.initialGifID, anchor: .top)
                        didCompleteInitialScroll = true
                        await viewModel.loadMoreIfNeeded(currentID: activeGifID)
                    }
                }

                HStack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.down")
                                .font(.subheadline.weight(.bold))
                            Text(selection.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassSurface(cornerRadius: 20)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        playerCoordinator.preferHD.toggle()
                    } label: {
                        Text(playerCoordinator.preferHD ? "HD" : "SD")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(playerCoordinator.preferHD ? AppTheme.accent : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .glassSurface(cornerRadius: 18)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }
            .hiddenNavigationBar()
            .navigationDestination(for: AppRoute.self) { route in
                Group {
                    switch route {
                    case .creator(let username, let initialUser):
                        CreatorProfileView(username: username, initialUser: initialUser)
                    case .niche(let niche):
                        NicheDetailView(niche: niche)
                    case .tagSearch(let tag):
                        TagFeedGridView(tag: tag)
                    }
                }
                .visibleNavigationBar()
            }
        }
        .onDisappear {
            playerCoordinator.pauseAll()
        }
        .onChange(of: activeGifID) { _, newID in
            activateCurrent()
            Task {
                await viewModel.loadMoreIfNeeded(currentID: newID)
            }
        }
        .onChange(of: navigationPath.count) { _, depth in
            if depth == 0 {
                activateCurrent()
            } else {
                playerCoordinator.pauseAll()
            }
        }
    }

    private func immersiveCell(for gif: GifItem) -> some View {
        let isActive = activeGifID == gif.id
        return VideoFeedCell(
            gif: gif,
            creator: viewModel.creator(for: gif),
            isActive: isActive,
            player: playerCoordinator.player(for: gif),
            preferAspectFill: playerCoordinator.preferAspectFill,
            isMuted: playerCoordinator.isMuted,
            isSaved: libraryStore.isGifSaved(gif.id),
            isPausedByUser: playerCoordinator.isPausedByUser,
            isBuffering: isActive && playerCoordinator.isBuffering,
            hasPlaybackError: playerCoordinator.failedGifIDs.contains(gif.id),
            progress: isActive ? playerCoordinator.progress : 0,
            currentTime: isActive ? playerCoordinator.currentTime : 0,
            duration: isActive ? playerCoordinator.duration : (gif.duration ?? 0),
            bottomPadding: 44,
            onTogglePlayPause: {
                playerCoordinator.togglePlayPause()
            },
            onDoubleTapSave: {
                libraryStore.ensureSaved(gif: gif)
            },
            onToggleSave: {
                libraryStore.toggleSave(gif: gif)
            },
            onToggleMute: {
                playerCoordinator.isMuted.toggle()
            },
            onToggleAspect: {
                playerCoordinator.preferAspectFill.toggle()
            },
            onRetryPlayback: {
                playerCoordinator.retry(gif: gif, neighbors: viewModel.neighbors(for: gif.id))
            },
            onSeek: { fraction in
                playerCoordinator.seek(to: fraction)
            },
            onSelectCreator: { username, creator in
                navigationPath.append(.creator(username: username, initialUser: creator))
            },
            onSelectTag: { tag in
                navigationPath.append(.tagSearch(tag))
            },
            onSelectNiche: { nicheName in
                navigationPath.append(.niche(NicheSummary(id: nicheName, name: nicheName)))
            }
        )
    }

    private func activateCurrent() {
        guard navigationPath.isEmpty else { return }
        guard let targetID = activeGifID ?? viewModel.items.first?.id,
              let gif = viewModel.items.first(where: { $0.id == targetID }) else {
            return
        }
        playerCoordinator.activate(gif: gif, neighbors: viewModel.neighbors(for: gif.id))
    }
}

private struct NavigationBarVisibilityModifier: ViewModifier {
    let visibility: Visibility

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.toolbarVisibility(visibility, for: .navigationBar)
        } else {
            content.toolbar(visibility, for: .navigationBar)
        }
    }
}

private extension View {
    func hiddenNavigationBar() -> some View {
        modifier(NavigationBarVisibilityModifier(visibility: .hidden))
    }

    func visibleNavigationBar() -> some View {
        modifier(NavigationBarVisibilityModifier(visibility: .visible))
    }
}
