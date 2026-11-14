import AVFoundation
import SwiftUI
import UIKit

struct VideoFeedCell: View {
    let gif: GifItem
    let creator: CreatorUser?
    let isActive: Bool
    let player: AVPlayer?
    let preferAspectFill: Bool
    let isMuted: Bool
    let isSaved: Bool
    let isPausedByUser: Bool
    let isBuffering: Bool
    let hasPlaybackError: Bool
    let progress: Double
    let currentTime: Double
    let duration: Double
    let bottomPadding: CGFloat
    let onTogglePlayPause: () -> Void
    let onDoubleTapSave: () -> Void
    let onToggleSave: () -> Void
    let onToggleMute: () -> Void
    let onToggleAspect: () -> Void
    let onRetryPlayback: () -> Void
    let onSeek: (Double) -> Void
    let onSelectCreator: (String, CreatorUser?) -> Void
    let onSelectTag: (String) -> Void
    let onSelectNiche: (String) -> Void

    @State private var isCaptionExpanded = false
    @State private var showHeartBurst = false
    @State private var heartBurstTrigger = 0
    @State private var isScrubbing = false
    @State private var scrubFraction: Double = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(hex: gif.avgColor)

                mediaCanvas
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                centerFeedbackOverlay

                scrimOverlay
                    .frame(width: proxy.size.width, height: proxy.size.height)

                contentOverlay
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: heartBurstTrigger)
    }

    // MARK: - Media Layer

    @ViewBuilder
    private var mediaCanvas: some View {
        if gif.isVideo {
            ZStack {
                CachedRemoteImage(
                    url: gif.previewImageURL,
                    contentMode: preferAspectFill ? .fill : .fit,
                    placeholderColor: Color(hex: gif.avgColor)
                )

                if let player {
                    CustomVideoPlayerView(
                        player: player,
                        videoGravity: preferAspectFill ? .resizeAspectFill : .resizeAspect
                    )
                }
            }
        } else {
            CachedRemoteImage(
                url: gif.fullImageURL,
                contentMode: preferAspectFill ? .fill : .fit,
                placeholderColor: Color(hex: gif.avgColor)
            )
        }
    }

    private var gestureSurface: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                triggerHeartBurst()
                onDoubleTapSave()
            }
            .onTapGesture(count: 1) {
                if gif.isVideo {
                    onTogglePlayPause()
                }
            }
    }

    // MARK: - Center State Overlay

    @ViewBuilder
    private var centerFeedbackOverlay: some View {
        if hasPlaybackError && gif.isVideo {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                Text("Video unavailable")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Button("Retry", action: onRetryPlayback)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
            }
            .padding(20)
            .glassSurface(cornerRadius: 20)
        } else {
            ZStack {
                if isActive && isPausedByUser && gif.isVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(22)
                        .background(.black.opacity(0.45), in: Circle())
                        .allowsHitTesting(false)
                }

                if isActive && isBuffering && !isPausedByUser && gif.isVideo {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .padding(16)
                        .background(.black.opacity(0.35), in: Circle())
                        .allowsHitTesting(false)
                }

                if showHeartBurst {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 86, weight: .bold))
                        .foregroundStyle(AppTheme.accentGradient)
                        .shadow(color: .black.opacity(0.4), radius: 12)
                        .transition(.scale.combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Scrim & Overlay Chrome

    private var scrimOverlay: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.55), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 140)

            Spacer()

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.84)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 300)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var contentOverlay: some View {
        VStack(spacing: 10) {
            gestureSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    gestureSurface
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    FeedInfoColumn(
                        gif: gif,
                        isCaptionExpanded: $isCaptionExpanded,
                        onSelectCreator: {
                            if let userName = gif.userName {
                                onSelectCreator(userName, creator)
                            }
                        },
                        onSelectTag: onSelectTag,
                        onSelectNiche: onSelectNiche
                    )
                    .background(Color.black.opacity(0.001))
                }
                .frame(maxWidth: .infinity, alignment: .bottomLeading)

                FeedActionRail(
                    gif: gif,
                    creator: creator,
                    isSaved: isSaved,
                    isMuted: isMuted,
                    preferAspectFill: preferAspectFill,
                    onSelectCreator: {
                        if let userName = gif.userName {
                            onSelectCreator(userName, creator)
                        }
                    },
                    onToggleSave: onToggleSave,
                    onToggleMute: onToggleMute,
                    onToggleAspect: onToggleAspect
                )
                .background(Color.black.opacity(0.001))
            }
            .padding(.horizontal, 14)

            if gif.isVideo {
                VideoScrubberBar(
                    progress: isScrubbing ? scrubFraction : progress,
                    currentTime: isScrubbing ? scrubFraction * duration : currentTime,
                    duration: duration,
                    isScrubbing: $isScrubbing,
                    scrubFraction: $scrubFraction,
                    onSeek: onSeek
                )
                .background(Color.black.opacity(0.001))
                .padding(.horizontal, 12)
            }
        }
        .padding(.top, 96)
        .padding(.bottom, bottomPadding)
    }

    private func triggerHeartBurst() {
        heartBurstTrigger += 1
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
            showHeartBurst = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.25)) {
                showHeartBurst = false
            }
        }
    }
}

// MARK: - Subviews

private struct FeedInfoColumn: View {
    let gif: GifItem
    @Binding var isCaptionExpanded: Bool
    let onSelectCreator: () -> Void
    let onSelectTag: (String) -> Void
    let onSelectNiche: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let userName = gif.userName, !userName.isEmpty {
                HStack(spacing: 6) {
                    Button(action: onSelectCreator) {
                        HStack(spacing: 5) {
                            Text("@\(userName)")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if gif.verified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.cyan)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    let dateText = MetricFormatter.relativeDate(gif.createDate)
                    if !dateText.isEmpty {
                        Text("• \(dateText)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    if !gif.isVideo {
                        Text("PHOTO")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.2), in: Capsule())
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }

            if let description = gif.description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCaptionExpanded.toggle()
                    }
                } label: {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(isCaptionExpanded ? 6 : 2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            if !gif.niches.isEmpty || !gif.tags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(gif.niches, id: \.self) { niche in
                            Button {
                                onSelectNiche(niche)
                            } label: {
                                Label(niche, systemImage: "square.grid.2x2")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 8)
                                    .background(AppTheme.accent.opacity(0.32), in: Capsule())
                                    .overlay {
                                        Capsule().strokeBorder(AppTheme.accent.opacity(0.6), lineWidth: 0.75)
                                    }
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(gif.tags, id: \.self) { tag in
                            Button {
                                onSelectTag(tag)
                            } label: {
                                Text("#\(tag)")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 8)
                                    .background(.white.opacity(0.14), in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FeedActionRail: View {
    let gif: GifItem
    let creator: CreatorUser?
    let isSaved: Bool
    let isMuted: Bool
    let preferAspectFill: Bool
    let onSelectCreator: () -> Void
    let onToggleSave: () -> Void
    let onToggleMute: () -> Void
    let onToggleAspect: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let userName = gif.userName, !userName.isEmpty {
                Button(action: onSelectCreator) {
                    ZStack(alignment: .bottom) {
                        AvatarView(url: creator?.avatarURL, name: userName, size: 42)
                            .overlay {
                                Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5)
                            }

                        Image(systemName: "person.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(AppTheme.accent, in: Circle())
                            .offset(y: 7)
                    }
                    .frame(width: 56, height: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open creator \(userName)")
            }

            RailIconButton(
                systemImage: isSaved ? "heart.fill" : "heart",
                tint: isSaved ? AppTheme.accent : .white,
                label: MetricFormatter.compactCount(gif.likes + (isSaved ? 1 : 0)),
                accessibilityName: isSaved ? "Remove bookmark" : "Bookmark",
                action: onToggleSave
            )
            .sensoryFeedback(.selection, trigger: isSaved)

            RailIconLabel(
                systemImage: "eye.fill",
                tint: .white.opacity(0.92),
                label: MetricFormatter.compactCount(gif.views)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(gif.views) views")

            if gif.isVideo {
                RailIconButton(
                    systemImage: (!gif.hasAudio || isMuted) ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    tint: gif.hasAudio ? .white : .white.opacity(0.55),
                    label: gif.hasAudio ? (isMuted ? "Muted" : "Sound") : "Silent",
                    accessibilityName: isMuted ? "Unmute" : "Mute",
                    action: onToggleMute
                )
            }

            RailIconButton(
                systemImage: preferAspectFill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                tint: .white,
                label: preferAspectFill ? "Fit" : "Fill",
                accessibilityName: "Toggle video aspect ratio",
                action: onToggleAspect
            )

            Menu {
                ShareLink(item: gif.watchPageURL) {
                    Label("Share Web Link", systemImage: "safari")
                }
                ShareLink(item: gif.deepLinkURL) {
                    Label("Share redgifs:// Link", systemImage: "app.badge")
                }
                Button {
                    UIPasteboard.general.string = gif.deepLinkURL.absoluteString
                } label: {
                    Label("Copy redgifs:// Link", systemImage: "doc.on.doc")
                }
            } label: {
                RailIconLabel(
                    systemImage: "arrowshape.turn.up.right.fill",
                    tint: .white,
                    label: "Share"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share or copy link")
        }
        .frame(width: 58)
    }
}

private struct RailIconLabel: View {
    let systemImage: String
    let tint: Color
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.38), in: Circle())
                .shadow(color: .black.opacity(0.45), radius: 4)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(width: 56, height: 50)
        .contentShape(Rectangle())
    }
}

private struct RailIconButton: View {
    let systemImage: String
    let tint: Color
    let label: String
    let accessibilityName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RailIconLabel(systemImage: systemImage, tint: tint, label: label)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName)
    }
}

private struct VideoScrubberBar: View {
    let progress: Double
    let currentTime: Double
    let duration: Double
    @Binding var isScrubbing: Bool
    @Binding var scrubFraction: Double
    let onSeek: (Double) -> Void

    var body: some View {
        VStack(spacing: 4) {
            if isScrubbing && duration > 0 {
                Text("\(MetricFormatter.duration(currentTime)) / \(MetricFormatter.duration(duration))")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.65), in: Capsule())
            }

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let clamped = min(max(progress, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.26))
                        .frame(height: isScrubbing ? 6 : 3)

                    Capsule()
                        .fill(.white)
                        .frame(width: width * clamped, height: isScrubbing ? 6 : 3)

                    if isScrubbing {
                        Circle()
                            .fill(.white)
                            .frame(width: 12, height: 12)
                            .offset(x: max(0, min(width - 12, width * clamped - 6)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            scrubFraction = min(max(value.location.x / width, 0), 1)
                        }
                        .onEnded { value in
                            let finalFraction = min(max(value.location.x / width, 0), 1)
                            scrubFraction = finalFraction
                            isScrubbing = false
                            onSeek(finalFraction)
                        }
                )
            }
            .frame(height: 20)
        }
    }
}
