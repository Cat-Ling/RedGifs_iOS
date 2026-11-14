import SwiftUI

struct MediaGridView: View {
    let items: [GifItem]
    let savedIDs: Set<String>
    var columnsCount: Int = 2
    let onSelect: (GifItem) -> Void
    var onItemAppear: ((GifItem) -> Void)?

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: columnsCount)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(items) { gif in
                MediaGridCard(
                    gif: gif,
                    isSaved: savedIDs.contains(gif.id),
                    onTap: { onSelect(gif) }
                )
                .onAppear {
                    onItemAppear?(gif)
                }
            }
        }
    }
}

struct MediaGridCard: View {
    let gif: GifItem
    let isSaved: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    CachedRemoteImage(
                        url: gif.previewImageURL,
                        contentMode: .fill,
                        placeholderColor: Color(hex: gif.avgColor)
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.2), .black.opacity(0.82)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    VStack {
                        HStack {
                            if isSaved {
                                Image(systemName: "heart.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.accent)
                                    .padding(6)
                                    .background(.black.opacity(0.55), in: Circle())
                            }
                            Spacer()
                            mediaBadge
                        }
                        Spacer()
                    }
                    .padding(8)

                    VStack(alignment: .leading, spacing: 3) {
                        if let userName = gif.userName, !userName.isEmpty {
                            HStack(spacing: 4) {
                                Text("@\(userName)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                if gif.verified {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.cyan)
                                }
                            }
                        }
                        HStack(spacing: 8) {
                            Label(MetricFormatter.compactCount(gif.views), systemImage: "eye.fill")
                            Label(MetricFormatter.compactCount(gif.likes), systemImage: "heart.fill")
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    }
                    .padding(10)
                }
            }
            .aspectRatio(9.0 / 13.5, contentMode: .fit)
            .compositingGroup()
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AppTheme.hairline, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var mediaBadge: some View {
        if gif.isVideo {
            HStack(spacing: 4) {
                if gif.hasAudio {
                    Image(systemName: "speaker.wave.2.fill")
                }
                let durationLabel = MetricFormatter.duration(gif.duration)
                Text(durationLabel.isEmpty ? "VIDEO" : durationLabel)
            }
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.black.opacity(0.6), in: Capsule())
        } else {
            Image(systemName: "photo")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(6)
                .background(.black.opacity(0.6), in: Circle())
        }
    }
}

// MARK: - Tag Feed Screen

struct TagFeedGridView: View {
    @Environment(LocalLibraryStore.self) private var libraryStore

    let tag: String

    @State private var items: [GifItem] = []
    @State private var usersByUsername: [String: CreatorUser] = [:]
    @State private var mediaType: String = "g"
    @State private var sortOrder: SearchOrder = .trending
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var immersiveSelection: ImmersiveFeedSelection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                filterBar

                if isLoading && items.isEmpty {
                    ProgressView()
                        .tint(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if let errorMessage, items.isEmpty {
                    ContentUnavailableView {
                        Label("Unable to load #\(tag)", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") {
                            Task { await reload() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                    }
                    .padding(.top, 60)
                } else if items.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "number",
                        description: Text("No media found for #\(tag).")
                    )
                    .padding(.top, 60)
                } else {
                    MediaGridView(
                        items: items,
                        savedIDs: Set(libraryStore.savedGifs.map(\.id)),
                        onSelect: { gif in
                            immersiveSelection = ImmersiveFeedSelection(
                                title: "#\(tag)",
                                items: items,
                                initialGifID: gif.id,
                                usersByUsername: usersByUsername
                            )
                        },
                        onItemAppear: { gif in
                            if let index = items.firstIndex(where: { $0.id == gif.id }),
                               index >= max(0, items.count - 6) {
                                Task { await loadMore() }
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .navigationTitle("#\(tag)")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(tag)-\(mediaType)-\(sortOrder.rawValue)") {
            await reload()
        }
        .fullScreenCover(item: $immersiveSelection) { selection in
            ImmersiveFeedView(selection: selection)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("Media", selection: $mediaType) {
                Text("Videos").tag("g")
                Text("Images").tag("i")
            }
            .pickerStyle(.segmented)

            Menu {
                ForEach(SearchOrder.allCases) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        if sortOrder == order {
                            Label(order.title, systemImage: "checkmark")
                        } else {
                            Text(order.title)
                        }
                    }
                }
            } label: {
                Label(sortOrder.title, systemImage: "arrow.up.arrow.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.surfaceElevated, in: Capsule())
            }
        }
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        page = 1
        do {
            let envelope = try await RedGifsAPIClient.shared.searchGifs(
                query: tag,
                mediaType: mediaType,
                order: sortOrder.rawValue,
                count: 30,
                page: 1
            )
            items = envelope.gifs
            for user in envelope.users {
                usersByUsername[user.username.lowercased()] = user
            }
            hasMore = !envelope.gifs.isEmpty && (envelope.pages <= 1 || envelope.page < envelope.pages)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        let nextPage = page + 1
        if let envelope = try? await RedGifsAPIClient.shared.searchGifs(
            query: tag,
            mediaType: mediaType,
            order: sortOrder.rawValue,
            count: 30,
            page: nextPage
        ) {
            let existing = Set(items.map(\.id))
            let unique = envelope.gifs.filter { !existing.contains($0.id) }
            items.append(contentsOf: unique)
            for user in envelope.users {
                usersByUsername[user.username.lowercased()] = user
            }
            page = nextPage
            hasMore = !unique.isEmpty && (envelope.pages <= 1 || envelope.page < envelope.pages)
        }
        isLoadingMore = false
    }
}
