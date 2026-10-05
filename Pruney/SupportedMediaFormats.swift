import AVFoundation
import ImageIO
import Photos
import UniformTypeIdentifiers

nonisolated struct SupportedMediaFormats: Sendable {
    private let imageReaders: Set<String>
    private let imageWriters: Set<String>
    private let videoReaders: Set<String>

    init() {
        imageReaders = Set(CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])
        imageWriters = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
        if #available(iOS 26, *) {
            videoReaders = Set(AVURLAsset.audiovisualContentTypes.map(\.identifier))
        } else {
            videoReaders = Set(AVURLAsset.audiovisualTypes().map(\.rawValue))
        }
    }

    func canEncodePhoto(_ format: UTType) -> Bool {
        format.conforms(to: .image) && !format.conforms(to: .rawImage)
            && imageReaders.contains(format.identifier) && imageWriters.contains(format.identifier)
            && format.preferredFilenameExtension != nil
    }

    func photoResource(in resources: [PHAssetResource]) -> PHAssetResource? {
        guard !resources.contains(where: { UTType($0.uniformTypeIdentifier)?.conforms(to: .rawImage) == true }),
              let original = resources.first(where: { $0.type == .photo }) ?? resources.first(where: { $0.type == .fullSizePhoto }),
              let format = UTType(original.uniformTypeIdentifier), canEncodePhoto(format) else { return nil }
        return original
    }

    func includesInReview(_ asset: PHAsset) -> Bool {
        let resources = PHAssetResource.assetResources(for: asset)
        if asset.mediaType == .image { return photoResource(in: resources) != nil }
        if asset.mediaType == .video {
            guard let resource = resources.first(where: { $0.type == .fullSizeVideo }) ?? resources.first(where: { $0.type == .video }),
                  let format = UTType(resource.uniformTypeIdentifier), format.conforms(to: .movie) else { return false }
            return videoReaders.contains(format.identifier)
        }
        return false
    }
}

nonisolated struct ReviewLibrarySnapshot {
    let assets: [PHAsset]
    let excludedCount: Int
    let sizeUnavailableCount: Int
    let measurements: [String: MediaMeasurement]
}

actor ReviewLibraryLoader {
    private let scanner = LibraryScanner()

    func load(filters: [ReviewFilter] = [], progress: @escaping @MainActor @Sendable (Int, Int) -> Void) async throws -> ReviewLibrarySnapshot {
        let formats = SupportedMediaFormats()
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: options)
        var supported: [PHAsset] = []
        var excluded = 0
        var sizeUnavailable = 0
        var measurements: [String: MediaMeasurement] = [:]
        await progress(0, assets.count)
        for index in 0..<assets.count {
            try Task.checkCancellation()
            let asset = assets.object(at: index)
            if !formats.includesInReview(asset) {
                excluded += 1
            } else if filters.isEmpty {
                supported.append(asset)
            } else {
                let candidates = filters.filter { $0.matchesMetadata(asset) }
                if candidates.contains(where: { $0.sizeMegabytes == nil }) {
                    supported.append(asset)
                } else if !candidates.isEmpty {
                    let measurement = try await scanner.measure(asset)
                    measurements[asset.localIdentifier] = measurement
                    if candidates.contains(where: { $0.matchesSize(measurement) }) {
                        supported.append(asset)
                    } else if !measurement.isComplete {
                        sizeUnavailable += 1
                    }
                }
            }
            if !filters.isEmpty || (index + 1).isMultiple(of: 50) || index + 1 == assets.count {
                await progress(index + 1, assets.count)
            }
        }
        try Task.checkCancellation()
        return ReviewLibrarySnapshot(assets: supported, excludedCount: excluded,
                                     sizeUnavailableCount: sizeUnavailable, measurements: measurements)
    }
}
