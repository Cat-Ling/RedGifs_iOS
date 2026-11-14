import Foundation
import Observation

@Observable
@MainActor
final class LocalLibraryStore {
    private(set) var savedGifs: [GifItem] = []
    private(set) var followedCreators: [CreatorUser] = []
    private(set) var savedNiches: [NicheSummary] = []

    private var savedGifIDs: Set<String> = []
    private var followedUsernames: Set<String> = []
    private var savedNicheIDs: Set<String> = []

    private let storageURL: URL

    private struct Snapshot: Codable {
        var gifs: [GifItem]
        var creators: [CreatorUser]
        var niches: [NicheSummary]
    }

    init(fileManager: FileManager = .default) {
        let baseDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let appDir = baseDir.appendingPathComponent("RedGIFsPulse", isDirectory: true)
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.storageURL = appDir.appendingPathComponent("local_library.json")
        load()
    }

    func isGifSaved(_ id: String) -> Bool {
        savedGifIDs.contains(id)
    }

    func isCreatorFollowed(_ username: String) -> Bool {
        followedUsernames.contains(username.lowercased())
    }

    func isNicheSaved(_ id: String) -> Bool {
        savedNicheIDs.contains(id)
    }

    func toggleSave(gif: GifItem) {
        if savedGifIDs.contains(gif.id) {
            savedGifIDs.remove(gif.id)
            savedGifs.removeAll { $0.id == gif.id }
        } else {
            savedGifIDs.insert(gif.id)
            savedGifs.insert(gif, at: 0)
        }
        persist()
    }

    func ensureSaved(gif: GifItem) {
        guard !savedGifIDs.contains(gif.id) else { return }
        savedGifIDs.insert(gif.id)
        savedGifs.insert(gif, at: 0)
        persist()
    }

    func toggleFollow(creator: CreatorUser) {
        let key = creator.username.lowercased()
        if followedUsernames.contains(key) {
            followedUsernames.remove(key)
            followedCreators.removeAll { $0.username.lowercased() == key }
        } else {
            followedUsernames.insert(key)
            followedCreators.insert(creator, at: 0)
        }
        persist()
    }

    func toggleSave(niche: NicheSummary) {
        if savedNicheIDs.contains(niche.id) {
            savedNicheIDs.remove(niche.id)
            savedNiches.removeAll { $0.id == niche.id }
        } else {
            savedNicheIDs.insert(niche.id)
            savedNiches.insert(niche, at: 0)
        }
        persist()
    }

    func clearAll() {
        savedGifs = []
        followedCreators = []
        savedNiches = []
        savedGifIDs = []
        followedUsernames = []
        savedNicheIDs = []
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return
        }
        savedGifs = snapshot.gifs
        followedCreators = snapshot.creators
        savedNiches = snapshot.niches
        savedGifIDs = Set(snapshot.gifs.map(\.id))
        followedUsernames = Set(snapshot.creators.map { $0.username.lowercased() })
        savedNicheIDs = Set(snapshot.niches.map(\.id))
    }

    private func persist() {
        let snapshot = Snapshot(
            gifs: savedGifs,
            creators: followedCreators,
            niches: savedNiches
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: storageURL, options: [.atomic])
    }
}
