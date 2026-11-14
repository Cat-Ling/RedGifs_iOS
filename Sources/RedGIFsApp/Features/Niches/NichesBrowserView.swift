import SwiftUI

struct NichesBrowserView: View {
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    @State private var viewModel = NichesViewModel()

    var body: some View {
        @Bindable var router = deepLinkRouter

        NavigationStack(path: $router.nichesNavigationPath) {
            VStack(spacing: 0) {
                sortBar

                content
            }
            .background(AppTheme.background)
            .navigationTitle("Niches")
            .searchable(
                text: $viewModel.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search niches"
            )
            .onSubmit(of: .search) {
                Task { await viewModel.reload() }
            }
            .onChange(of: viewModel.query) { _, newValue in
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Task { await viewModel.reload() }
                }
            }
            .onChange(of: viewModel.sortOrder) { _, _ in
                Task { await viewModel.reload() }
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
        }
        .task {
            applyPendingNicheSortIfNeeded()
            await viewModel.loadInitialIfNeeded()
        }
        .onChange(of: deepLinkRouter.pendingNicheSort) { _, _ in
            applyPendingNicheSortIfNeeded()
        }
    }

    private func applyPendingNicheSortIfNeeded() {
        guard let sort = deepLinkRouter.pendingNicheSort else { return }
        deepLinkRouter.pendingNicheSort = nil
        if viewModel.sortOrder != sort {
            viewModel.sortOrder = sort
        }
    }

    private var sortBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(NicheSortOrder.allCases) { order in
                    let isSelected = viewModel.sortOrder == order
                    Button {
                        viewModel.sortOrder = order
                    } label: {
                        Text(order.title)
                            .font(.caption.weight(isSelected ? .bold : .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? AnyShapeStyle(AppTheme.accentGradient) : AnyShapeStyle(AppTheme.surfaceElevated),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.previews.isEmpty {
            ProgressView()
                .tint(AppTheme.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage, viewModel.previews.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Niches", systemImage: "square.grid.2x2")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") {
                    Task { await viewModel.reload() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.previews.isEmpty {
            ContentUnavailableView.search(text: viewModel.query)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.previews) { preview in
                        NavigationLink(value: AppRoute.niche(preview.niche)) {
                            NicheListRow(preview: preview)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            Task { await viewModel.loadMoreIfNeeded(currentID: preview.id) }
                        }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .tint(AppTheme.accent)
                            .padding(.vertical, 16)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .refreshable {
                await viewModel.reload()
            }
        }
    }
}
