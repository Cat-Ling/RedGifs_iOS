import SwiftUI

@main
struct RedGIFsApp: App {
    @State private var playerCoordinator = VideoPlayerCoordinator()
    @State private var libraryStore = LocalLibraryStore()
    @State private var deepLinkRouter = DeepLinkRouter()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(playerCoordinator)
                .environment(libraryStore)
                .environment(deepLinkRouter)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    deepLinkRouter.open(url: url, playerCoordinator: playerCoordinator)
                }
        }
    }
}
