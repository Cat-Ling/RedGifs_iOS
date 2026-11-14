import SwiftUI
import UIKit

struct CreatorProfileView: View {
    @Environment(LocalLibraryStore.self) private var libraryStore

    @State private var viewModel: CreatorProfileViewModel
    @State private var immersiveSelection: ImmersiveFeedSelection?

    init(username: String, initialUser: CreatorUser? = nil) {
        self._viewModel = State(
            initialValue: CreatorProfileViewModel(username: username, initialUser: initialUser)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                profileHeader

                if !viewModel.tags.isEmpty {
                    creatorTagsStrip
                }

                if !viewModel.socials.isEmpty {
                    socialLinksRow
                }

                if !viewModel.pins.isEmpty {
                    pinnedSection
                }

                mediaPicker

                mediaGridSection
            }
            .padding(.bottom, 28)
        }
        .background(AppTheme.background)
        .navigationTitle("@\(viewModel.username)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let encodedUser = viewModel.username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? viewModel.username
                let webProfileURL = URL(string: "https://www.redgifs.com/users/\(encodedUser)")
                let appProfileURL = URL(string: "redgifs://users/\(encodedUser)")

                Menu {
                    if let webProfileURL {
                        ShareLink(item: webProfileURL) {
                            Label("Share Web Profile", systemImage: "safari")
                        }
                    }
                    if let appProfileURL {
                        ShareLink(item: appProfileURL) {
                            Label("Share redgifs:// Link", systemImage: "app.badge")
                        }
                        Button {
                            UIPasteboard.general.string = appProfileURL.absoluteString
                        } label: {
                            Label("Copy redgifs:// Link", systemImage: "doc.on.doc")
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share profile links")
            }
        }
        .refreshable {
            await viewModel.reloadAll()
        }
        .task {
            await viewModel.loadInitialIfNeeded()
        }
        .fullScreenCover(item: $immersiveSelection) { selection in
            ImmersiveFeedView(selection: selection)
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        let user = viewModel.resolvedUser
        let isFollowed = libraryStore.isCreatorFollowed(user.username)

        return VStack(spacing: 14) {
            AvatarView(url: user.avatarURL, name: user.displayName, size: 88)
                .overlay {
                    Circle().strokeBorder(AppTheme.accentGradient, lineWidth: 2.5)
                }

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(user.displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    if user.verified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.subheadline)
                            .foregroundStyle(.cyan)
                    }
                }
                Text("@\(user.username)")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            HStack(spacing: 28) {
                StatColumn(value: MetricFormatter.compactCount(user.followers), label: "Followers")
                StatColumn(value: MetricFormatter.compactCount(user.views), label: "Views")
                StatColumn(value: MetricFormatter.compactCount(max(user.publishedGifs, user.gifs)), label: "Posts")
            }
            .padding(.vertical, 4)

            if let bio = user.description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !bio.isEmpty {
                Text(bio)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Button {
                libraryStore.toggleFollow(creator: user)
            } label: {
                Label(
                    isFollowed ? "Following Locally" : "Follow Locally",
                    systemImage: isFollowed ? "checkmark" : "plus"
                )
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: 220)
                .padding(.vertical, 11)
                .background(
                    isFollowed ? AnyShapeStyle(AppTheme.surfaceElevated) : AnyShapeStyle(AppTheme.accentGradient),
                    in: Capsule()
                )
                .overlay {
                    if isFollowed {
                        Capsule().strokeBorder(AppTheme.hairline, lineWidth: 1)
                    }
                }
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: isFollowed)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.horizontal, 14)
    }

    // MARK: - Auxiliary Strips

    private var creatorTagsStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(viewModel.tags.prefix(16), id: \.self) { tag in
                    NavigationLink(value: AppRoute.tagSearch(tag)) {
                        Text("#\(tag)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(AppTheme.surfaceElevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollIndicators(.hidden)
    }

    private var socialLinksRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(viewModel.socials, id: \.self) { rawLink in
                    if let url = URL(string: rawLink), url.scheme?.hasPrefix("http") == true {
                        Link(destination: url) {
                            Label(url.host ?? "Link", systemImage: "link")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(AppTheme.surfaceElevated, in: Capsule())
                                .overlay {
                                    Capsule().strokeBorder(AppTheme.hairline, lineWidth: 0.75)
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollIndicators(.hidden)
    }

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pinned", systemImage: "pin.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(viewModel.pins) { gif in
                        MediaGridCard(
                            gif: gif,
                            isSaved: libraryStore.isGifSaved(gif.id),
                            onTap: {
                                immersiveSelection = ImmersiveFeedSelection(
                                    title: "Pinned • @\(viewModel.username)",
                                    items: viewModel.pins,
                                    initialGifID: gif.id,
                                    usersByUsername: viewModel.usersMap
                                )
                            }
                        )
                        .frame(width: 132)
                    }
                }
                .padding(.horizontal, 14)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Media Feed

    private var mediaPicker: some View {
        Picker("Media Type", selection: Binding(
            get: { viewModel.mediaType },
            set: { newValue in
                Task { await viewModel.switchMediaType(newValue) }
            }
        )) {
            Text("Videos").tag("g")
            Text("Images").tag("i")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var mediaGridSection: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView()
                .tint(AppTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
        } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Creator", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") {
                    Task { await viewModel.reloadAll() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
            .padding(.top, 24)
        } else if viewModel.items.isEmpty {
            ContentUnavailableView(
                viewModel.mediaType == "i" ? "No Images" : "No Videos",
                systemImage: viewModel.mediaType == "i" ? "photo.on.rectangle" : "film",
                description: Text("@\(viewModel.username) hasn't posted any items in this category.")
            )
            .padding(.top, 24)
        } else {
            MediaGridView(
                items: viewModel.items,
                savedIDs: Set(libraryStore.savedGifs.map(\.id)),
                onSelect: { gif in
                    immersiveSelection = ImmersiveFeedSelection(
                        title: "@\(viewModel.username)",
                        items: viewModel.items,
                        initialGifID: gif.id,
                        usersByUsername: viewModel.usersMap
                    )
                },
                onItemAppear: { gif in
                    Task { await viewModel.loadMoreIfNeeded(forGifID: gif.id) }
                }
            )
            .padding(.horizontal, 14)
        }
    }
}

private struct StatColumn: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}
