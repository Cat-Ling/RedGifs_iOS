import Foundation
import SwiftUI
import UIKit

enum AppTheme {
    static let background = Color.black
    static let surface = Color(red: 0.08, green: 0.08, blue: 0.10)
    static let surfaceElevated = Color(red: 0.14, green: 0.14, blue: 0.17)
    static let accent = Color(red: 0.99, green: 0.23, blue: 0.43)
    static let accentSecondary = Color(red: 1.0, green: 0.46, blue: 0.32)
    static let hairline = Color.white.opacity(0.12)
    static let textSecondary = Color.white.opacity(0.68)
    static let textTertiary = Color.white.opacity(0.45)

    static let accentGradient = LinearGradient(
        colors: [accent, accentSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum AppRoute: Hashable {
    case creator(username: String, initialUser: CreatorUser? = nil)
    case niche(NicheSummary)
    case tagSearch(String)
}

struct ImmersiveFeedSelection: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let items: [GifItem]
    let initialGifID: String
    let usersByUsername: [String: CreatorUser]

    init(
        title: String,
        items: [GifItem],
        initialGifID: String,
        usersByUsername: [String: CreatorUser] = [:]
    ) {
        self.title = title
        self.items = items
        self.initialGifID = initialGifID
        self.usersByUsername = usersByUsername
    }
}

enum MetricFormatter {
    static func compactCount(_ value: Int) -> String {
        let absValue = Double(abs(value))
        let sign = value < 0 ? "-" : ""
        switch absValue {
        case 1_000_000_000...:
            return "\(sign)\(formatDecimal(absValue / 1_000_000_000))B"
        case 1_000_000...:
            return "\(sign)\(formatDecimal(absValue / 1_000_000))M"
        case 1_000...:
            return "\(sign)\(formatDecimal(absValue / 1_000))K"
        default:
            return "\(value)"
        }
    }

    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "" }
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    static func relativeDate(_ timestamp: TimeInterval?) -> String {
        guard let timestamp, timestamp > 0 else { return "" }
        let date = Date(timeIntervalSince1970: timestamp)
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3_600 { return "\(Int(interval / 60))m" }
        if interval < 86_400 { return "\(Int(interval / 3_600))h" }
        if interval < 2_592_000 { return "\(Int(interval / 86_400))d" }
        if interval < 31_536_000 { return "\(Int(interval / 2_592_000))mo" }
        return "\(Int(interval / 31_536_000))y"
    }

    private static func formatDecimal(_ value: Double) -> String {
        if value >= 10 {
            return String(format: "%.0f", value)
        }
        let formatted = String(format: "%.1f", value)
        return formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
    }
}

extension Color {
    init(hex: String?) {
        guard let hex else {
            self = AppTheme.surface
            return
        }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let int = UInt64(cleaned, radix: 16) else {
            self = AppTheme.surface
            return
        }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Cached Remote Image

@MainActor
final class RemoteImageCache {
    static let shared = RemoteImageCache()

    private let cache: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 240
        c.totalCostLimit = 90 * 1024 * 1024
        return c
    }()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 30 * 1024 * 1024, diskCapacity: 150 * 1024 * 1024)
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config)
    }()

    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func loadImage(from url: URL) async -> UIImage? {
        if let existing = cache.object(forKey: url as NSURL) {
            return existing
        }
        var request = URLRequest(url: url)
        for (header, value) in RedGifsAPIClient.shared.mediaHeaders() {
            request.setValue(value, forHTTPHeaderField: header)
        }
        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let image = UIImage(data: data) else {
            return nil
        }
        let pixelCost = Int(image.size.width * image.size.height * image.scale * 4)
        cache.setObject(image, forKey: url as NSURL, cost: max(1, pixelCost))
        return image
    }
}

struct CachedRemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var placeholderColor: Color = AppTheme.surface

    @State private var loadedImage: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                placeholderColor

                if let loadedImage {
                    Image(uiImage: loadedImage)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .task(id: url) {
            guard let url else {
                loadedImage = nil
                return
            }
            if let cached = RemoteImageCache.shared.cachedImage(for: url) {
                loadedImage = cached
                return
            }
            loadedImage = nil
            let fetched = await RemoteImageCache.shared.loadImage(from: url)
            if !Task.isCancelled {
                loadedImage = fetched
            }
        }
    }
}

struct AvatarView: View {
    let url: URL?
    let name: String
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let url {
                CachedRemoteImage(url: url, contentMode: .fill, placeholderColor: AppTheme.surfaceElevated)
            } else {
                ZStack {
                    AppTheme.accentGradient
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private struct GlassPillModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.hairline, lineWidth: 0.75)
            }
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassPillModifier(cornerRadius: cornerRadius))
    }
}
