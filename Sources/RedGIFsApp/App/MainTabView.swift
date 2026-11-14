import SwiftUI

enum AppTab: Hashable {
    case feed
    case explore
    case niches
    case library
}

struct MainTabView: View {
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    var body: some View {
        @Bindable var router = deepLinkRouter

        ZStack(alignment: .top) {
            TabView(selection: $router.selectedTab) {
                VerticalFeedView(isActiveTab: router.selectedTab == .feed)
                    .tag(AppTab.feed)
                    .tabItem {
                        Label("Feed", systemImage: "play.rectangle.fill")
                    }
                    .toolbarBackground(.black.opacity(0.85), for: .tabBar)
                    .toolbarBackground(.visible, for: .tabBar)

                ExploreView()
                    .tag(AppTab.explore)
                    .tabItem {
                        Label("Explore", systemImage: "magnifyingglass")
                    }
                    .toolbarBackground(.visible, for: .tabBar)

                NichesBrowserView()
                    .tag(AppTab.niches)
                    .tabItem {
                        Label("Niches", systemImage: "square.grid.2x2.fill")
                    }
                    .toolbarBackground(.visible, for: .tabBar)

                SavedLibraryView()
                    .tag(AppTab.library)
                    .tabItem {
                        Label("Library", systemImage: "heart.fill")
                    }
                    .toolbarBackground(.visible, for: .tabBar)
            }
            .tint(AppTheme.accent)

            if router.isResolvingMedia {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(AppTheme.accent)
                    Text("Opening RedGIFs link…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassSurface(cornerRadius: 22)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if let errorMessage = router.resolutionErrorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "link.badge.plus")
                        .foregroundStyle(AppTheme.accent)
                    Text(errorMessage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button {
                        router.dismissError()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss link error")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: 380)
                .glassSurface(cornerRadius: 18)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: router.isResolvingMedia)
        .animation(.snappy(duration: 0.22), value: router.resolutionErrorMessage)
        .fullScreenCover(
            item: $router.presentedImmersiveSelection,
            onDismiss: {
                router.didDismissImmersiveCover()
            }
        ) { selection in
            ImmersiveFeedView(
                selection: selection,
                onLoadMore: router.presentedImmersiveLoader
            )
            .id(selection.id)
        }
    }
}
