import AVKit
import ImageIO
import Photos
import SwiftUI

enum PhotoLibraryAccess {
    static func isAuthorized() async -> Bool {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let status: PHAuthorizationStatus
        if currentStatus == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else {
            status = currentStatus
        }
        return status == .authorized || status == .limited
    }
}

struct PhotoAssetMetadata: Equatable {
    let takenAt: Date?
    let timeZone: TimeZone
    let byteCount: Int64?
    let pixelWidth: Int
    let pixelHeight: Int

    var takenAtText: String? {
        guard let takenAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.timeZone = timeZone
        return formatter.string(from: takenAt)
    }

    var sizeText: String? {
        byteCount.map(DataSizeFormatting.string(fromByteCount:))
    }

    var dimensionsText: String {
        "\(pixelWidth) × \(pixelHeight) px"
    }
}

enum PhotoAssetMetadataLoader {
    static func load(reference: MediaReference) async -> PhotoAssetMetadata? {
        guard await PhotoLibraryAccess.isAuthorized() else { return nil }
        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: [reference.localIdentifier],
            options: nil
        )
        guard let asset = result.firstObject else { return nil }

        let input = await contentEditingInput(for: asset)
        let originalMetadata = input?.fullSizeImageURL.flatMap(readOriginalMetadata)
        let byteCount: Int64?
        if let url = input?.fullSizeImageURL,
           let localFileSize = fileSize(at: url) {
            byteCount = localFileSize
        } else {
            byteCount = await resourceSize(for: asset)
        }
        let takenAt = originalMetadata?.date ?? asset.creationDate

        return PhotoAssetMetadata(
            takenAt: takenAt,
            timeZone: .autoupdatingCurrent,
            byteCount: byteCount,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight
        )
    }

    private static func contentEditingInput(for asset: PHAsset) async -> PHContentEditingInput? {
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, _ in
                continuation.resume(returning: input)
            }
        }
    }

    private static func readOriginalMetadata(
        from url: URL
    ) -> (date: Date, timeZone: TimeZone)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let dateText = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
              let offsetText = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String,
              let timeZone = timeZone(from: offsetText)
        else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = timeZone
        guard let date = formatter.date(from: dateText) else { return nil }
        return (date, timeZone)
    }

    private static func timeZone(from offset: String) -> TimeZone? {
        let normalized = offset.replacingOccurrences(of: ":", with: "")
        guard normalized.count == 5,
              let sign = normalized.first,
              sign == "+" || sign == "-",
              let hours = Int(normalized.dropFirst().prefix(2)),
              let minutes = Int(normalized.suffix(2)),
              hours <= 23,
              minutes <= 59
        else {
            return nil
        }
        let multiplier = sign == "-" ? -1 : 1
        return TimeZone(secondsFromGMT: multiplier * (hours * 3_600 + minutes * 60))
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize
        else {
            return nil
        }
        return Int64(size)
    }

    private static func resourceSize(for asset: PHAsset) async -> Int64? {
        guard let resource = PHAssetResource.assetResources(for: asset).first else {
            return nil
        }
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            var byteCount: Int64 = 0
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options
            ) { data in
                byteCount += Int64(data.count)
            } completionHandler: { error in
                continuation.resume(returning: error == nil ? byteCount : nil)
            }
        }
    }
}

struct PhotoInformationView: View {
    let metadata: PhotoAssetMetadata?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let metadata {
                if let takenAtText = metadata.takenAtText {
                    Label(takenAtText, systemImage: "calendar")
                }
                if let sizeText = metadata.sizeText {
                    Label(sizeText, systemImage: "externaldrive")
                }
                Label(metadata.dimensionsText, systemImage: "aspectratio")
            } else {
                Label("Loading photo details…", systemImage: "calendar")
                    .foregroundStyle(.white.opacity(0.72))
                Label("—", systemImage: "externaldrive")
                    .foregroundStyle(.white.opacity(0.45))
                Label("—", systemImage: "aspectratio")
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(height: 60, alignment: .topLeading)
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
    }
}

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
    var backgroundColor: Color?
    var onAvailabilityChange: ((Bool) -> Void)?

    @State private var image: UIImage?
    @State private var isMissing = false

    var body: some View {
        ZStack {
            resolvedBackgroundColor

            if let image {
                Color.clear.overlay {
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
                }
            } else if isMissing {
                Color.clear.overlay {
                    MissingPhotoReferenceView()
                }
            } else {
                Color.clear.overlay {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Loading from Photos…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
        .transaction { transaction in
            transaction.animation = nil
        }
        .task(id: reference.localIdentifier) {
            await loadImage()
        }
    }

    private var resolvedBackgroundColor: Color {
        backgroundColor
            ?? (fitEntireImage ? Color.white : Color.secondary.opacity(0.08))
    }

    @MainActor
    private func loadImage() async {
        let cacheKey = "\(reference.localIdentifier)|\(fitEntireImage ? "fit" : "fill")" as NSString
        guard await PhotoLibraryAccess.isAuthorized() else {
            isMissing = true
            onAvailabilityChange?(false)
            return
        }

        if let cachedImage = PhotoThumbnailCache.images.object(forKey: cacheKey) {
            image = cachedImage
            isMissing = false
            onAvailabilityChange?(true)
            return
        }

        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: [reference.localIdentifier],
            options: nil
        )
        guard let asset = result.firstObject else {
            isMissing = true
            onAvailabilityChange?(false)
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
                targetSize: CGSize(width: 1200, height: 1200),
                contentMode: fitEntireImage ? .aspectFit : .aspectFill,
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
        onAvailabilityChange?(image != nil)
    }
}

struct VideoAssetView: View {
    let reference: MediaReference
    var onAvailabilityChange: ((Bool) -> Void)?

    @State private var player: AVPlayer?
    @State private var isMissing = false
    @State private var isLoadingVideo = false
    @State private var isMuted = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black
            if let player {
                VideoPlayer(player: player)

                Button {
                    isMuted.toggle()
                    player.isMuted = isMuted
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                }
                .padding(12)
                .accessibilityLabel(isMuted ? "Unmute video sound" : "Mute video sound")
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
                    PhotoAssetView(
                        reference: reference,
                        showVideoBadge: true,
                        onAvailabilityChange: onAvailabilityChange
                    )
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

        guard await PhotoLibraryAccess.isAuthorized() else {
            isMissing = true
            onAvailabilityChange?(false)
            return
        }

        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: [reference.localIdentifier],
            options: nil
        )
        guard let photoAsset = result.firstObject, photoAsset.mediaType == .video else {
            isMissing = true
            onAvailabilityChange?(false)
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
            onAvailabilityChange?(false)
            return
        }
        onAvailabilityChange?(true)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let preparedPlayer = AVPlayer(playerItem: AVPlayerItem(asset: avAsset))
        preparedPlayer.isMuted = isMuted
        player = preparedPlayer
        preparedPlayer.play()
    }
}

private struct MissingPhotoReferenceView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.red)
            Text("Media Unavailable")
                .font(.headline)
            Text("Allow Photos access or replace this item.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: media unavailable. Allow Photos access or replace this item.")
    }
}
