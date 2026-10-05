import AVFoundation
import ImageIO
import Photos
import UniformTypeIdentifiers

nonisolated enum PhotoActionError: LocalizedError {
    case unavailable, unsupported, unsupportedPhotoFormat, noSavings, writeFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: "The current original is not available locally."
        case .unsupported: "This item cannot be processed in this format."
        case .unsupportedPhotoFormat: "This photo format cannot be preserved. The original was kept."
        case .noSavings: "Compression would not produce a smaller file. The original was kept."
        case .writeFailed: "Photos could not save the changes."
        }
    }
}

nonisolated private struct PreparedReplacement {
    let asset: PHAsset
    let output: URL
    let directory: URL
}

nonisolated private struct ReplacementCommit {
    let replacement: PreparedReplacement
    let albums: [PHAssetCollection]
}

actor PhotoActionProcessor {
    private var activeExporter: AVAssetExportSession?
    private let formats = SupportedMediaFormats()
    private var preparedReplacements: [PreparedReplacement] = []
    func delete(_ assets: [PHAsset]) async throws {
        guard assets.allSatisfy({ $0.canPerform(.delete) }) else { throw PhotoActionError.unsupported }
        try await changeLibrary {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    func prepareResize(_ asset: PHAsset, scale: Double, quality: Double,
                progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        guard asset.canPerform(.delete) else { throw PhotoActionError.unsupported }
        guard formats.includesInReview(asset) else {
            throw asset.mediaType == .image ? PhotoActionError.unsupportedPhotoFormat : PhotoActionError.unsupported
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PruneyResize-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var retainedForCommit = false
        defer {
            if !retainedForCommit { try? FileManager.default.removeItem(at: directory) }
        }
        let output: URL
        let originalBytes: Int64?
        if asset.mediaSubtypes.contains(.photoLive) {
            // Copy only the current still resource, without re-encoding or reducing dimensions.
            let resources = PHAssetResource.assetResources(for: asset)
            guard let still = resources.first(where: { $0.type == .fullSizePhoto }) ?? resources.first(where: { $0.type == .photo }),
                  let format = UTType(still.uniformTypeIdentifier),
                  let fileExtension = format.preferredFilenameExtension else { throw PhotoActionError.unsupportedPhotoFormat }
            output = directory.appendingPathComponent("static.\(fileExtension)")
            try await writePhotoResource(still, to: output)
            guard let source = CGImageSourceCreateWithURL(output as CFURL, nil),
                  CGImageSourceGetCount(source) > 0,
                  CGImageSourceGetType(source) as String? == format.identifier else { throw PhotoActionError.writeFailed }
            originalBytes = nil
        } else if asset.mediaType == .video {
            let video = try await currentVideo(asset)
            // Edited compositions have no single current file to compare against safely.
            guard let file = video as? AVURLAsset else { throw PhotoActionError.unsupported }
            originalBytes = try fileSize(file.url)
            output = directory.appendingPathComponent("compressed.mov")
            try await exportVideo(video, scale: scale, to: output, progress: progress)
        } else {
            let resources = PHAssetResource.assetResources(for: asset)
            guard let original = formats.photoResource(in: resources),
                  let format = UTType(original.uniformTypeIdentifier) else {
                throw PhotoActionError.unsupportedPhotoFormat
            }
            let source: URL
            if resources.contains(where: { $0.type == .adjustmentData }) {
                let input = try await currentPhoto(asset)
                guard let current = input.fullSizeImageURL else { throw PhotoActionError.unavailable }
                source = current
            } else {
                // Use the actual resource so Photos does not render animations or HDR as a plain still.
                source = directory.appendingPathComponent("source")
                try await writePhotoResource(original, to: source)
            }
            originalBytes = try fileSize(source)
            output = try encodePhoto(source, format: format, scale: scale, quality: quality, in: directory)
        }
        let outputBytes = try fileSize(output)
        if let originalBytes, outputBytes >= originalBytes { throw PhotoActionError.noSavings }
        // Keep only the smaller output while waiting for the single replacement transaction.
        let sourceCopy = directory.appendingPathComponent("source")
        if FileManager.default.fileExists(atPath: sourceCopy.path) { try FileManager.default.removeItem(at: sourceCopy) }
        preparedReplacements.append(PreparedReplacement(asset: asset, output: output, directory: directory))
        retainedForCommit = true
        await progress(1)
    }

    private func writePhotoResource(_ resource: PHAssetResource, to output: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = false
            PHAssetResourceManager.default().writeData(for: resource, toFile: output, options: options) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func currentPhoto(_ asset: PHAsset) async throws -> PHContentEditingInput {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHContentEditingInputRequestOptions()
            options.isNetworkAccessAllowed = false
            options.canHandleAdjustmentData = { _ in false }
            asset.requestContentEditingInput(with: options) { input, _ in
                if let input { continuation.resume(returning: input) }
                else { continuation.resume(throwing: PhotoActionError.unavailable) }
            }
        }
    }

    private func currentVideo(_ asset: PHAsset) async throws -> AVAsset {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            options.version = .current
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { video, _, _ in
                if let video { continuation.resume(returning: video) }
                else { continuation.resume(throwing: PhotoActionError.unavailable) }
            }
        }
    }

    private func encodePhoto(_ input: URL, format: UTType, scale: Double, quality: Double, in directory: URL) throws -> URL {
        try autoreleasepool {
            guard formats.canEncodePhoto(format),
                  let fileExtension = format.preferredFilenameExtension else {
                throw PhotoActionError.unsupportedPhotoFormat
            }
            let output = directory.appendingPathComponent("compressed.\(fileExtension)")
            guard let source = CGImageSourceCreateWithURL(input as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
                throw PhotoActionError.unavailable
            }
            let count = CGImageSourceGetCount(source)
            guard count > 0,
                  !(format == .gif && CGImageSourceGetType(source) as String? != format.identifier),
                  let destination = CGImageDestinationCreateWithURL(output as CFURL, format.identifier as CFString, count, nil) else {
                throw PhotoActionError.unsupportedPhotoFormat
            }
            if let properties = CGImageSourceCopyProperties(source, nil) {
                CGImageDestinationSetProperties(destination, properties)
            }
            for index in 0..<count {
                try autoreleasepool {
                    let maximum = try maximumPixelSize(source, index: index, scale: scale)
                    var options: [CFString: Any] = [
                        kCGImageDestinationImageMaxPixelSize: maximum,
                        kCGImageDestinationPreserveGainMap: true
                    ]
                    if format == .jpeg || format == .heic || format == .heif || format.identifier == "public.jpeg-2000" || format == .webP {
                        options[kCGImageDestinationLossyCompressionQuality] = quality
                    }
                    // Image I/O copies each frame's metadata, orientation, and animation timing.
                    CGImageDestinationAddImageFromSource(destination, source, index, options as CFDictionary)
                }
            }
            guard CGImageDestinationFinalize(destination) else { throw PhotoActionError.writeFailed }
            try validatePhoto(output, original: source, format: format, scale: scale)
            return output
        }
    }

    private func maximumPixelSize(_ source: CGImageSource, index: Int, scale: Double) throws -> Int {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0, height.intValue > 0 else { throw PhotoActionError.unsupported }
        return max(1, Int(Double(max(width.intValue, height.intValue)) * scale))
    }

    private func validatePhoto(_ output: URL, original: CGImageSource, format: UTType, scale: Double) throws {
        guard let result = CGImageSourceCreateWithURL(output as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(result) as String? == format.identifier,
              CGImageSourceGetCount(result) == CGImageSourceGetCount(original) else {
            throw PhotoActionError.writeFailed
        }
        try validateAnimationProperties(CGImageSourceCopyProperties(original, nil), result: CGImageSourceCopyProperties(result, nil), isFrame: false)
        for index in 0..<CGImageSourceGetCount(original) {
            try autoreleasepool {
                let target = try maximumPixelSize(original, index: index, scale: scale)
                guard try maximumPixelSize(result, index: index, scale: 1) <= target else { throw PhotoActionError.writeFailed }
                let originalProperties = CGImageSourceCopyPropertiesAtIndex(original, index, nil)
                let resultProperties = CGImageSourceCopyPropertiesAtIndex(result, index, nil)
                let originalValues = originalProperties as? [CFString: Any] ?? [:]
                let resultValues = resultProperties as? [CFString: Any] ?? [:]
                if (originalValues[kCGImagePropertyHasAlpha] as? NSNumber)?.boolValue == true,
                   (resultValues[kCGImagePropertyHasAlpha] as? NSNumber)?.boolValue != true {
                    throw PhotoActionError.writeFailed
                }
                try validateAnimationProperties(originalProperties, result: resultProperties, isFrame: true)
                var gainMapTypes = [kCGImageAuxiliaryDataTypeHDRGainMap]
                if #available(iOS 18, *) { gainMapTypes.append(kCGImageAuxiliaryDataTypeISOGainMap) }
                for type in gainMapTypes {
                    if CGImageSourceCopyAuxiliaryDataInfoAtIndex(original, index, type) != nil,
                       CGImageSourceCopyAuxiliaryDataInfoAtIndex(result, index, type) == nil {
                        throw PhotoActionError.writeFailed
                    }
                }
            }
        }
    }

    private func validateAnimationProperties(_ original: CFDictionary?, result: CFDictionary?, isFrame: Bool) throws {
        let originalValues = original as? [CFString: Any] ?? [:]
        let resultValues = result as? [CFString: Any] ?? [:]
        let namespaces: [(CFString, [CFString])] = [
            (kCGImagePropertyGIFDictionary, isFrame ? [kCGImagePropertyGIFDelayTime, kCGImagePropertyGIFUnclampedDelayTime] : [kCGImagePropertyGIFLoopCount]),
            (kCGImagePropertyPNGDictionary, isFrame ? [kCGImagePropertyAPNGDelayTime, kCGImagePropertyAPNGUnclampedDelayTime] : [kCGImagePropertyAPNGLoopCount])
        ]
        for (namespace, keys) in namespaces {
            let source = originalValues[namespace] as? [CFString: Any] ?? [:]
            let output = resultValues[namespace] as? [CFString: Any] ?? [:]
            for key in keys {
                if let expected = source[key] as? NSNumber {
                    guard let actual = output[key] as? NSNumber,
                          abs(expected.doubleValue - actual.doubleValue) < 0.0001 else {
                        throw PhotoActionError.writeFailed
                    }
                }
            }
        }
    }

    private func exportVideo(_ asset: AVAsset, scale: Double, to output: URL,
                             progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw PhotoActionError.unsupported }
        let size = try await track.load(.naturalSize)
        let longSide = max(abs(size.width), abs(size.height))
        let shortSide = min(abs(size.width), abs(size.height))
        let presets: [(String, Double, Double)] = [
            (AVAssetExportPreset3840x2160, 3840, 2160),
            (AVAssetExportPreset1920x1080, 1920, 1080),
            (AVAssetExportPreset1280x720, 1280, 720),
            (AVAssetExportPreset960x540, 960, 540),
            (AVAssetExportPreset640x480, 640, 480)
        ]
        guard longSide > 0, shortSide > 0 else { throw PhotoActionError.unsupported }
        var selectedPreset: String?
        for preset in presets {
            let factor = min(preset.1 / longSide, preset.2 / shortSide)
            if factor <= scale, await AVAssetExportSession.compatibility(ofExportPreset: preset.0, with: asset, outputFileType: .mov) {
                selectedPreset = preset.0
                break
            }
        }
        guard let selectedPreset, let exporter = AVAssetExportSession(asset: asset, presetName: selectedPreset),
              exporter.supportedFileTypes.contains(.mov) else { throw PhotoActionError.unsupported }
        activeExporter = exporter
        exporter.outputURL = output
        exporter.outputFileType = .mov
        let monitor = Task {
            while !Task.isCancelled {
                await progress(Double(exporter.progress) * 0.9)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer {
            monitor.cancel()
            activeExporter = nil
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                Task { await self.completeExport(continuation) }
            }
        }
    }

    private func completeExport(_ continuation: CheckedContinuation<Void, Error>) {
        if let activeExporter, activeExporter.status == .completed { continuation.resume() }
        else { continuation.resume(throwing: activeExporter?.error ?? PhotoActionError.writeFailed) }
    }

    func commitPreparedResizes() async throws -> Int {
        guard !preparedReplacements.isEmpty else { return 0 }
        defer { discardPreparedResizes() }
        var commits: [ReplacementCommit] = []
        for replacement in preparedReplacements {
            guard replacement.asset.canPerform(.delete) else { throw PhotoActionError.unsupported }
            _ = try fileSize(replacement.output)
            let albums = PHAssetCollection.fetchAssetCollectionsContaining(replacement.asset, with: .album, options: nil)
            var editableAlbums: [PHAssetCollection] = []
            albums.enumerateObjects { album, _, _ in
                if album.canPerform(.addContent) { editableAlbums.append(album) }
            }
            commits.append(ReplacementCommit(replacement: replacement, albums: editableAlbums))
        }
        let changes = commits
        // All replacements and removals share one transaction and one system confirmation batch.
        try await changeLibrary {
            var albumUpdates: [String: (collection: PHAssetCollection, assets: [PHObjectPlaceholder])] = [:]
            for commit in changes {
                let asset = commit.replacement.asset
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                // Outputs are closed and app-owned; Photos can move them without an intermediary copy.
                options.shouldMoveFile = true
                request.addResource(with: asset.mediaType == .video ? .video : .photo, fileURL: commit.replacement.output, options: options)
                request.creationDate = asset.creationDate
                request.location = asset.location
                request.isFavorite = asset.isFavorite
                if let placeholder = request.placeholderForCreatedAsset {
                    for album in commit.albums {
                        var update = albumUpdates[album.localIdentifier] ?? (collection: album, assets: [])
                        update.assets.append(placeholder)
                        albumUpdates[album.localIdentifier] = update
                    }
                }
            }
            for update in albumUpdates.values {
                PHAssetCollectionChangeRequest(for: update.collection)?.addAssets(update.assets as NSArray)
            }
            PHAssetChangeRequest.deleteAssets(changes.map { $0.replacement.asset } as NSArray)
        }
        return changes.count
    }

    func discardPreparedResizes() {
        for replacement in preparedReplacements {
            try? FileManager.default.removeItem(at: replacement.directory)
        }
        preparedReplacements.removeAll()
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard let size, size > 0 else { throw PhotoActionError.unavailable }
        return Int64(size)
    }

    private func changeLibrary(_ changes: @escaping @Sendable () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changes) { success, error in
                if success { continuation.resume() }
                else { continuation.resume(throwing: error ?? PhotoActionError.writeFailed) }
            }
        }
    }
}
