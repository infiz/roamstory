import AVKit
import Photos
import SwiftUI

private enum PhotoThumbnailCache {
    static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
}

struct PhotoAssetView: View {
    let reference: MediaReference
    var showVideoBadge = false
    var fitEntireImage = false

    @State private var image: UIImage?
    @State private var isMissing = false

    var body: some View {
        ZStack {
            if let image {
                if fitEntireImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                }
            } else if isMissing {
                ContentUnavailableView(
                    "Media Unavailable",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("Allow Photos access or relink this item.")
                )
            } else {
                ProgressView("Loading from Photos…")
            }

            if showVideoBadge && image != nil {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.white, .black.opacity(0.35))
                    .shadow(radius: 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(fitEntireImage ? Color.white : Color.secondary.opacity(0.08))
        .task(id: reference.localIdentifier) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        let cacheKey = reference.localIdentifier as NSString
        if let cachedImage = PhotoThumbnailCache.images.object(forKey: cacheKey) {
            image = cachedImage
            isMissing = false
            return
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            isMissing = true
            return
        }

        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: [reference.localIdentifier],
            options: nil
        )
        guard let asset = result.firstObject else {
            isMissing = true
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        image = await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1200, height: 800),
                contentMode: .aspectFill,
                options: options
            ) { requestedImage, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded, !resumed {
                    resumed = true
                    continuation.resume(returning: requestedImage)
                }
            }
        }
        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            PhotoThumbnailCache.images.setObject(image, forKey: cacheKey, cost: cost)
        }
        isMissing = image == nil
    }
}

struct VideoAssetView: View {
    let reference: MediaReference

    @State private var player: AVPlayer?
    @State private var isMissing = false
    @State private var isLoadingVideo = false

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
            } else if isMissing {
                ContentUnavailableView(
                    "Video Unavailable",
                    systemImage: "video.badge.exclamationmark",
                    description: Text("Allow Photos access or relink this video.")
                )
                .foregroundStyle(.white)
            } else if isLoadingVideo {
                ProgressView("Preparing video…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else {
                Button {
                    Task {
                        await loadVideoAndPlay()
                    }
                } label: {
                    PhotoAssetView(reference: reference, showVideoBadge: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play video")
                .accessibilityHint("Loads the video from Photos and starts playback")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: reference.localIdentifier) {
            player?.pause()
            player = nil
            isMissing = false
            isLoadingVideo = false
        }
        .onDisappear {
            player?.pause()
        }
    }

    @MainActor
    private func loadVideoAndPlay() async {
        guard !isLoadingVideo else { return }
        player?.pause()
        player = nil
        isMissing = false
        isLoadingVideo = true
        defer { isLoadingVideo = false }

        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            isMissing = true
            return
        }

        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: [reference.localIdentifier],
            options: nil
        )
        guard let photoAsset = result.firstObject, photoAsset.mediaType == .video else {
            isMissing = true
            return
        }

        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true

        let avAsset: AVAsset? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(
                forVideo: photoAsset,
                options: options
            ) { asset, _, _ in
                continuation.resume(returning: asset)
            }
        }

        guard let avAsset else {
            isMissing = true
            return
        }
        let preparedPlayer = AVPlayer(playerItem: AVPlayerItem(asset: avAsset))
        player = preparedPlayer
        preparedPlayer.play()
    }
}
