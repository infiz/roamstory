import Photos
import PhotosUI
import SwiftUI

enum MediaPickerMode: String, Identifiable {
    case photos
    case singlePhoto
    case singleVideo
    case gallery
    case videos

    var id: String { rawValue }
}

struct PickedMedia {
    let localIdentifier: String
    let kind: MediaKind
    let originalFilename: String
    let creationDate: Date?
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
        configuration.selectionLimit = mode == .gallery ? 0 : ([.singlePhoto, .singleVideo].contains(mode) ? 1 : 20)
        configuration.filter = [.videos, .singleVideo].contains(mode) ? .videos : .images
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
                return PickedMedia(
                    localIdentifier: identifier,
                    kind: kind,
                    originalFilename: filename,
                    creationDate: asset.creationDate
                )
            }

            let chronologicallyOrderedSelections: [PickedMedia]
            if parent.mode == .photos || parent.mode == .gallery {
                chronologicallyOrderedSelections = selections.enumerated().sorted { lhs, rhs in
                    switch (lhs.element.creationDate, rhs.element.creationDate) {
                    case let (lhsDate?, rhsDate?):
                        if lhsDate == rhsDate { return lhs.offset < rhs.offset }
                        return lhsDate < rhsDate
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    case (nil, nil):
                        return lhs.offset < rhs.offset
                    }
                }.map(\.element)
            } else {
                chronologicallyOrderedSelections = selections
            }

            parent.onComplete(chronologicallyOrderedSelections)
            parent.dismiss()
        }
    }
}
