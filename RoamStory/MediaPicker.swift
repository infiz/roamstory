import Photos
import PhotosUI
import SwiftUI

enum MediaPickerMode: String, Identifiable {
    case photos
    case singlePhoto
    case gallery
    case videos

    var id: String { rawValue }
}

struct PickedMedia {
    let localIdentifier: String
    let kind: MediaKind
    let originalFilename: String
}

struct MediaPickerView: UIViewControllerRepresentable {
    let mode: MediaPickerMode
    let onComplete: ([PickedMedia]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = mode == .gallery ? 0 : (mode == .singlePhoto ? 1 : 20)
        configuration.filter = mode == .videos ? .videos : .images
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: MediaPickerView

        init(parent: MediaPickerView) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let identifiers = results.compactMap(\.assetIdentifier)
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            var assetsByIdentifier: [String: PHAsset] = [:]
            fetchResult.enumerateObjects { asset, _, _ in
                assetsByIdentifier[asset.localIdentifier] = asset
            }

            let selections = identifiers.compactMap { identifier -> PickedMedia? in
                guard let asset = assetsByIdentifier[identifier] else { return nil }
                let kind: MediaKind = asset.mediaType == .video ? .video : .image
                let filename = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""
                return PickedMedia(localIdentifier: identifier, kind: kind, originalFilename: filename)
            }

            parent.onComplete(selections)
            parent.dismiss()
        }
    }
}
