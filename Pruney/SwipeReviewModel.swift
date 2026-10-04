import AVFoundation
import Observation
import Photos
import UIKit

nonisolated enum ReviewDecision: CaseIterable {
    case skipped, resized, deleted

    var title: String {
        switch self {
        case .skipped: "Skipped"
        case .resized: "Resized"
        case .deleted: "Delete"
        }
    }
    var symbol: String {
        switch self {
        case .skipped: "checkmark"
        case .resized: "arrow.down.right.and.arrow.up.left"
        case .deleted: "trash"
        }
    }
}

struct ReviewShare: Identifiable {
    let id = UUID()
    let files: [URL]
    let directory: URL
}

nonisolated enum ReviewSortOrder: String, CaseIterable, Identifiable {
    case date, size
    var id: Self { self }
    var title: String { self == .date ? "By date" : "By size" }
}

private struct ReviewSelection {
    let asset: PHAsset
    let decision: ReviewDecision
}

@MainActor @Observable
final class SwipeReviewModel {
    private var pending: [PHAsset] = []
    private var pendingIndex = 0
    private var history: [ReviewSelection] = []
    private var decisionCounts: [ReviewDecision: Int] = [:]
    private(set) var selectionRevision = UUID()
    private(set) var total = 0
    private(set) var sortOrder: ReviewSortOrder = .date
    private(set) var isSorting = false
    private(set) var sortingProcessed = 0
    private(set) var sortingTotal = 0
    private(set) var image: UIImage?
    private(set) var nextImage: UIImage?
    private(set) var isLoadingNextImage = false
    private(set) var player: AVPlayer?
    private(set) var isLoading = false
    private(set) var mediaError: String?
    private(set) var measurement: MediaMeasurement?
    private(set) var hasAccess = true
    private(set) var isPreparingShare = false
    var share: ReviewShare?
    var shareError: String?

    private var loaded = false
    private var generation = UUID()
    private var requests: [PHImageRequestID] = []
    private var nextImageAssetID: String?
    private var sizeTask: Task<Void, Never>?
    private var shareTask: Task<Void, Never>?
    private var sortTask: Task<Void, Never>?
    private var sortToken = UUID()
    private var shareDirectory: URL?
    private let scanner = LibraryScanner()
    private let sortScanner = LibraryScanner()
    private let exporter = ReviewExporter()
    private var measurements: [String: MediaMeasurement] = [:]

    var reviewed: Int { history.count }
    var remaining: Int { pending.count - pendingIndex }
    var currentAsset: PHAsset? {
        guard pendingIndex < pending.count else { return nil }
        return pending[pendingIndex]
    }
    var nextAsset: PHAsset? {
        guard pendingIndex + 1 < pending.count else { return nil }
        return pending[pendingIndex + 1]
    }
    var isLivePhoto: Bool { currentAsset?.mediaSubtypes.contains(.photoLive) == true }
    var isVideo: Bool { currentAsset?.mediaType == .video }
    var isComplete: Bool { loaded && total > 0 && reviewed == total }
    var canDecide: Bool { hasAccess && currentAsset != nil && !isPreparingShare && !isSorting }
    var canShare: Bool { canDecide && !isLoading && mediaError == nil }
    var canUndo: Bool { hasAccess && !history.isEmpty && !isPreparingShare && !isSorting }
    var canSort: Bool { hasAccess && remaining > 1 && !isPreparingShare }
    func count(_ decision: ReviewDecision) -> Int { decisionCounts[decision, default: 0] }

    func start() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        hasAccess = status == .authorized || status == .limited
        guard hasAccess else { stop(); return }
        if !loaded {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let assets = PHAsset.fetchAssets(with: options)
            pending = (0..<assets.count).map { assets.object(at: $0) }
            total = pending.count
            loaded = true
            loadCurrent()
        } else if currentAsset != nil && image == nil && player == nil && !isLoading {
            loadCurrent()
        }
    }

    func decide(_ decision: ReviewDecision) {
        guard canDecide, let asset = currentAsset else { return }
        // Decisions are session-only selections. No assets are modified here.
        history.append(ReviewSelection(asset: asset, decision: decision))
        decisionCounts[decision, default: 0] += 1
        pendingIndex += 1
        selectionRevision = UUID()
        loadCurrent()
    }

    func undo() {
        guard canUndo else { return }
        guard let selection = history.popLast() else { return }
        decisionCounts[selection.decision, default: 0] -= 1
        selectionRevision = UUID()
        // Undo always puts the selected asset above the current queue, even after sorting.
        if pendingIndex > 0 && pending[pendingIndex - 1].localIdentifier == selection.asset.localIdentifier {
            pendingIndex -= 1
        } else {
            pending.insert(selection.asset, at: pendingIndex)
        }
        loadCurrent()
    }

    func resetSelections() {
        guard canUndo else { return }
        let previousSort = sortOrder
        let allAssets = history.map(\.asset) + Array(pending[pendingIndex...])
        cancelSorting()
        pending = allAssets.sorted { lhs, rhs in
            let leftDate = lhs.creationDate ?? .distantPast
            let rightDate = rhs.creationDate ?? .distantPast
            return leftDate == rightDate ? lhs.localIdentifier < rhs.localIdentifier : leftDate > rightDate
        }
        pendingIndex = 0
        history.removeAll()
        decisionCounts.removeAll()
        selectionRevision = UUID()
        sortOrder = .date
        loadCurrent()
        if previousSort == .size { setSortOrder(.size) }
    }

    func decideAll(_ decision: ReviewDecision) {
        guard canDecide else { return }
        for asset in pending[pendingIndex...] {
            history.append(ReviewSelection(asset: asset, decision: decision))
        }
        decisionCounts[decision, default: 0] += remaining
        pendingIndex = pending.count
        selectionRevision = UUID()
        loadCurrent()
    }

    func makeActionPlan() -> ReviewActionPlan {
        ReviewActionPlan(
            resizeAssets: history.filter { $0.decision == .resized }.map(\.asset),
            deleteAssets: history.filter { $0.decision == .deleted }.map(\.asset)
        )
    }

    func setSortOrder(_ order: ReviewSortOrder) {
        guard canSort, order != sortOrder || isSorting else { return }
        cancelSorting()
        pause()
        let remainingAssets = Array(pending[pendingIndex...])
        if order == .date {
            pending = remainingAssets.sorted { lhs, rhs in
                let leftDate = lhs.creationDate ?? .distantPast
                let rightDate = rhs.creationDate ?? .distantPast
                return leftDate == rightDate ? lhs.localIdentifier < rhs.localIdentifier : leftDate > rightDate
            }
            pendingIndex = 0
            sortOrder = .date
            loadCurrent()
            return
        }

        isSorting = true
        sortingTotal = remainingAssets.count
        sortingProcessed = 0
        let token = sortToken
        sortTask = Task { [weak self, sortScanner] in
            do {
                var sizes: [String: MediaMeasurement] = [:]
                for asset in remainingAssets {
                    try Task.checkCancellation()
                    let cached = self?.measurements[asset.localIdentifier]
                    let size: MediaMeasurement
                    if let cached { size = cached }
                    else { size = try await sortScanner.measure(asset) }
                    guard let self, self.sortToken == token else { return }
                    sizes[asset.localIdentifier] = size
                    self.measurements[asset.localIdentifier] = size
                    self.sortingProcessed += 1
                }
                guard let self, self.sortToken == token else { return }
                self.pending = remainingAssets.sorted { lhs, rhs in
                    let left = sizes[lhs.localIdentifier]!
                    let right = sizes[rhs.localIdentifier]!
                    if left.isComplete != right.isComplete { return left.isComplete }
                    if left.bytes != right.bytes { return left.bytes > right.bytes }
                    let leftDate = lhs.creationDate ?? .distantPast
                    let rightDate = rhs.creationDate ?? .distantPast
                    return leftDate == rightDate ? lhs.localIdentifier < rhs.localIdentifier : leftDate > rightDate
                }
                self.pendingIndex = 0
                self.sortOrder = .size
                self.isSorting = false
                self.sortTask = nil
                self.loadCurrent()
            } catch {
                guard let self, self.sortToken == token else { return }
                self.isSorting = false
                self.sortTask = nil
            }
        }
    }

    private func cancelSorting() {
        sortToken = UUID()
        sortTask?.cancel()
        sortTask = nil
        isSorting = false
    }

    func cancelSort() { cancelSorting() }

    func pause() { player?.pause() }

    private func cancelMedia() {
        generation = UUID()
        requests.forEach { PHImageManager.default().cancelImageRequest($0) }
        requests.removeAll()
        sizeTask?.cancel()
        sizeTask = nil
        player?.pause()
    }

    func stop() {
        cancelSorting()
        cancelMedia()
        player = nil
        image = nil
        nextImage = nil
        nextImageAssetID = nil
        isLoadingNextImage = false
        isLoading = false
        shareTask?.cancel()
        shareTask = nil
        clearShare()
    }

    private func loadCurrent() {
        let prefetchedImage = nextImageAssetID == currentAsset?.localIdentifier ? nextImage : nil
        cancelMedia()
        image = prefetchedImage
        nextImage = nil
        nextImageAssetID = nil
        isLoadingNextImage = false
        player = nil
        mediaError = nil
        measurement = nil
        guard let asset = currentAsset else { isLoading = false; return }
        isLoading = true
        let token = generation
        loadNextImage(token: token)

        if asset.mediaType == .video {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .automatic
            let id = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { [weak self] item, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.isLoading = false
                    if let item { self.player = AVPlayer(playerItem: item) }
                    else { self.mediaError = "This video isn’t available on this device. It may be stored in iCloud." }
                }
            }
            requests.append(id)
        } else {
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            let id = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 1800, height: 1800), contentMode: .aspectFit, options: options) { [weak self] image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    if let image { self.image = image }
                    if !degraded {
                        self.isLoading = false
                        if image == nil { self.mediaError = "This photo isn’t available on this device. It may be stored in iCloud." }
                    }
                }
            }
            requests.append(id)
        }

        if let cached = measurements[asset.localIdentifier] {
            measurement = cached
        } else {
            sizeTask = Task { [weak self, scanner] in
                do {
                    let result = try await scanner.measure(asset)
                    guard let self, self.generation == token else { return }
                    self.measurements[asset.localIdentifier] = result
                    self.measurement = result
                } catch {
                    // A cancelled measurement belongs to an item no longer being displayed.
                }
            }
        }
    }

    private func loadNextImage(token: UUID) {
        guard let asset = nextAsset else { return }
        nextImageAssetID = asset.localIdentifier
        isLoadingNextImage = true
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        // Keep only one upcoming image or video poster ready beneath the current card.
        let id = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 1800, height: 1800), contentMode: .aspectFit, options: options) { [weak self] image, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                if let image { self.nextImage = image }
                if !degraded { self.isLoadingNextImage = false }
            }
        }
        requests.append(id)
    }

    func prepareShare() {
        guard canShare, let asset = currentAsset else { return }
        pause()
        isPreparingShare = true
        shareError = nil
        let token = generation
        shareTask = Task { [weak self, exporter] in
            do {
                let result = try await exporter.export(asset)
                guard let self, self.generation == token, !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: result.directory)
                    return
                }
                self.shareDirectory = result.directory
                self.share = result
                self.isPreparingShare = false
            } catch {
                guard let self, self.generation == token else { return }
                self.isPreparingShare = false
                if !(error is CancellationError) {
                    self.shareError = "The original file couldn’t be prepared for sharing. It may only be available in iCloud."
                }
            }
        }
    }

    func clearShare() {
        share = nil
        if let shareDirectory { try? FileManager.default.removeItem(at: shareDirectory) }
        shareDirectory = nil
        isPreparingShare = false
    }

    isolated deinit {
        requests.forEach { PHImageManager.default().cancelImageRequest($0) }
        sizeTask?.cancel()
        shareTask?.cancel()
        player?.pause()
        sortTask?.cancel()
        if let shareDirectory { try? FileManager.default.removeItem(at: shareDirectory) }
    }
}

actor ReviewExporter {
    func export(_ asset: PHAsset) async throws -> ReviewShare {
        let resources = PHAssetResource.assetResources(for: asset)
        var selected: [PHAssetResource] = []
        if asset.mediaType == .video {
            if let video = resources.first(where: { $0.type == .fullSizeVideo }) ?? resources.first(where: { $0.type == .video }) { selected.append(video) }
        } else {
            if let photo = resources.first(where: { $0.type == .fullSizePhoto }) ?? resources.first(where: { $0.type == .photo }) { selected.append(photo) }
            if asset.mediaSubtypes.contains(.photoLive), let motion = resources.first(where: { $0.type == .fullSizePairedVideo }) ?? resources.first(where: { $0.type == .pairedVideo }) { selected.append(motion) }
        }
        guard !selected.isEmpty else { throw CocoaError(.fileReadNoSuchFile) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PruneyShare-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            var files: [URL] = []
            for (index, resource) in selected.enumerated() {
                try Task.checkCancellation()
                let file = directory.appendingPathComponent("\(index)-\(URL(fileURLWithPath: resource.originalFilename).lastPathComponent)")
                try await write(resource, to: file)
                files.append(file)
            }
            try Task.checkCancellation()
            return ReviewShare(files: files, directory: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private func write(_ resource: PHAssetResource, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = false
            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}
