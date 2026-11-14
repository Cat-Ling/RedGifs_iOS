import SwiftUI

struct SavedLibraryView: View {
    @Environment(LocalLibraryStore.self) private var libraryStore
    @Environment(VideoPlayerCoordinator.self) private var playerCoordinator
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    private enum LibrarySection: String, CaseIterable, Identifiable {
        case videos = "Saved"
        case creators = "Creators"
        case niches = "Niches"

        var id: String { rawValue }
    }

    @State private var selectedSection: LibrarySection = .videos
    @State private var immersiveSelection: ImmersiveFeedSelection?
    @State private var showSettingsSheet = false

    var body: some View {
        @Bindable var router = deepLinkRouter

        NavigationStack(path: $router.libraryNavigationPath) {
            VStack(spacing: 12) {
                Picker("Library Section", selection: $selectedSection) {
                    ForEach(LibrarySection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.top, 6)

                sectionContent
            }
            .background(AppTheme.background)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettingsSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Playback Settings")
                }
            }
            .sheet(isPresented: $showSettingsSheet) {
                PlaybackSettingsSheet()
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
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .videos:
            if libraryStore.savedGifs.isEmpty {
                ContentUnavailableView(
                    "No Saved Clips",
                    systemImage: "heart.slash",
                    description: Text("Double-tap or tap the heart on any clip to bookmark it locally on this device.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    MediaGridView(
                        items: libraryStore.savedGifs,
                        savedIDs: Set(libraryStore.savedGifs.map(\.id)),
                        onSelect: { gif in
                            let usersMap = Dictionary(
                                uniqueKeysWithValues: libraryStore.followedCreators.map { ($0.username.lowercased(), $0) }
                            )
                            immersiveSelection = ImmersiveFeedSelection(
                                title: "Saved Clips",
                                items: libraryStore.savedGifs,
                                initialGifID: gif.id,
                                usersByUsername: usersMap
                            )
                        }
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 24)
                }
            }

        case .creators:
            if libraryStore.followedCreators.isEmpty {
                ContentUnavailableView(
                    "No Followed Creators",
                    systemImage: "person.2.slash",
                    description: Text("Follow creators from any video or profile to build your local feed list.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(libraryStore.followedCreators) { creator in
                            NavigationLink(value: AppRoute.creator(username: creator.username, initialUser: creator)) {
                                CreatorRowCard(creator: creator)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 24)
                }
            }

        case .niches:
            if libraryStore.savedNiches.isEmpty {
                ContentUnavailableView(
                    "No Saved Niches",
                    systemImage: "bookmark.slash",
                    description: Text("Save niches to jump straight into your favorite categories.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(libraryStore.savedNiches) { niche in
                            NavigationLink(value: AppRoute.niche(niche)) {
                                NicheListRow(preview: NichePreviewItem(niche: niche))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 24)
                }
            }
        }
    }
}

private struct PlaybackSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(VideoPlayerCoordinator.self) private var playerCoordinator
    @Environment(LocalLibraryStore.self) private var libraryStore
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    @State private var showClearConfirm = false
    @State private var deepLinkInput = ""
    @State private var invalidLinkMessage: String?

    var body: some View {
        @Bindable var coordinator = playerCoordinator

        NavigationStack {
            Form {
                Section("Video Playback") {
                    Toggle("Prefer HD Streams", isOn: $coordinator.preferHD)
                    Toggle("Auto-Loop Videos", isOn: $coordinator.autoLoop)
                    Toggle("Mute Audio by Default", isOn: $coordinator.isMuted)
                    Toggle("Fill Screen (Crop to Fit)", isOn: $coordinator.preferAspectFill)
                }

                Section {
                    TextField("redgifs://watch/..., users/..., or https://...", text: $deepLinkInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit {
                            openEnteredLink()
                        }

                    Button("Open Link") {
                        openEnteredLink()
                    }
                    .disabled(deepLinkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let invalidLinkMessage {
                        Text(invalidLinkMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    LabeledContent("URL Scheme", value: "redgifs://")
                } header: {
                    Text("Open redgifs:// or Web Link")
                } footer: {
                    Text("Examples: redgifs://watch/<id>, redgifs://users/<name>, redgifs://niches/<slug>, redgifs://tag/<tag>, or redgifs://https://www.redgifs.com/watch/<id>")
                }

                Section {
                    LabeledContent("Session Mode", value: "Unauthenticated Guest")
                    LabeledContent("Saved Clips", value: "\(libraryStore.savedGifs.count)")
                    LabeledContent("Followed Creators", value: "\(libraryStore.followedCreators.count)")
                    LabeledContent("Saved Niches", value: "\(libraryStore.savedNiches.count)")
                } header: {
                    Text("Local Storage")
                } footer: {
                    Text("All bookmarks and followed creators are stored strictly on-device without a RedGIFs account.")
                }

                Section {
                    Button("Clear Local Library", role: .destructive) {
                        showClearConfirm = true
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Clear all saved clips, creators, and niches?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear Everything", role: .destructive) {
                    libraryStore.clearAll()
                }
                Button("Cancel", role: .cancel) { }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func openEnteredLink() {
        invalidLinkMessage = nil
        if deepLinkRouter.open(rawURLString: deepLinkInput, playerCoordinator: playerCoordinator) {
            dismiss()
        } else {
            invalidLinkMessage = "Enter a valid redgifs:// path or redgifs.com URL."
        }
    }
}
