import Foundation
import Photos
import Observation

// Live Photos are a separate category here so the overview never counts them twice.
nonisolated enum MediaCategory: String, CaseIterable, Identifiable, Sendable {
    case photo, livePhoto, video
    var id: Self { self }
    var title: String {
        switch self {
        case .photo: "Photos"
        case .livePhoto: "Live Photos"
        case .video: "Videos"
        }
    }
    static func classify(isVideo: Bool, isLivePhoto: Bool) -> Self {
        isVideo ? .video : (isLivePhoto ? .livePhoto : .photo)
    }
}

nonisolated struct MediaUsage: Sendable {
    var bytes: Int64 = 0
    var count = 0
}

nonisolated struct MediaMeasurement: Sendable {
    let bytes: Int64
    let isComplete: Bool
}

nonisolated struct LibrarySummary: Sendable {
    var usage: [MediaCategory: MediaUsage] = [:]
    var processed = 0
    var assetCount = 0
    var unavailableCount = 0
    var totalBytes: Int64 { usage.values.reduce(0) { $0 + $1.bytes } }
    var progress: Double { assetCount == 0 ? 1 : Double(processed) / Double(assetCount) }
    mutating func record(category: MediaCategory, bytes: Int64, complete: Bool) {
        var item = usage[category, default: MediaUsage()]
        item.count += 1
        item.bytes += bytes
        usage[category] = item
        processed += 1
        if !complete { unavailableCount += 1 }
    }
}

// Photos delivers data in chunks; count bytes without retaining photos or large videos.
nonisolated private final class ResourceRead: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Int64 = 0
    private var requestID: PHAssetResourceDataRequestID?
    private var cancelled = false
    func append(_ data: Data) { lock.withLock { bytes += Int64(data.count) } }
    func result() -> Int64 { lock.withLock { bytes } }
    func setRequest(_ id: PHAssetResourceDataRequestID) {
        let shouldCancel = lock.withLock { requestID = id; return cancelled }
        if shouldCancel { PHAssetResourceManager.default().cancelDataRequest(id) }
    }
    func cancel() {
        let id = lock.withLock { cancelled = true; return requestID }
        if let id { PHAssetResourceManager.default().cancelDataRequest(id) }
    }
}

actor LibraryScanner {
    func scan(_ assets: PHFetchResult<PHAsset>, update: @escaping @MainActor @Sendable (LibrarySummary) -> Void) async throws -> LibrarySummary {
        var summary = LibrarySummary(assetCount: assets.count)
        await update(summary)
        for index in 0..<assets.count {
            try Task.checkCancellation()
            let asset = assets.object(at: index)
            let category = MediaCategory.classify(isVideo: asset.mediaType == .video, isLivePhoto: asset.mediaSubtypes.contains(.photoLive))
            let measurement = try await measure(asset)
            try Task.checkCancellation()
            summary.record(category: category, bytes: measurement.bytes, complete: measurement.isComplete)
            // Limit UI updates while still showing progress on a large library.
            if summary.processed % 10 == 0 || summary.processed == summary.assetCount {
                await update(summary)
            }
        }
        return summary
    }

    func measure(_ asset: PHAsset) async throws -> MediaMeasurement {
        let resources = PHAssetResource.assetResources(for: asset).filter { $0.type != .adjustmentData }
        var bytes: Int64 = 0
        var complete = !resources.isEmpty
        for resource in resources {
            try Task.checkCancellation()
            if let size = await read(resource) { bytes += size } else { complete = false }
        }
        try Task.checkCancellation()
        return MediaMeasurement(bytes: bytes, isComplete: complete)
    }

    private func read(_ resource: PHAssetResource) async -> Int64? {
        let state = ResourceRead()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = false
                let id = PHAssetResourceManager.default().requestData(for: resource, options: options) { data in
                    state.append(data)
                } completionHandler: { error in
                    continuation.resume(returning: error == nil ? state.result() : nil)
                }
                state.setRequest(id)
            }
        } onCancel: {
            state.cancel()
        }
    }
}

@MainActor @Observable
final class LibraryAnalysis: NSObject, PHPhotoLibraryChangeObserver {
    private(set) var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var summary = LibrarySummary()
    private(set) var isAnalyzing = false
    private(set) var hasAnalyzed = false
    private let scanner = LibraryScanner()
    private var scanTask: Task<Void, Never>?
    private var generation = UUID()
    private var observing = false
    private var observedAssets: PHFetchResult<PHAsset>?
    private var isForeground = true
    var canRead: Bool { authorization == .authorized || authorization == .limited }

    func requestAccess() async {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        refresh()
    }

    func refresh() {
        isForeground = true
        let previous = authorization
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard canRead else {
            stop()
            summary = LibrarySummary()
            hasAnalyzed = false
            observedAssets = nil
            return
        }
        if !observing {
            PHPhotoLibrary.shared().register(self)
            observing = true
        }
        if previous != authorization || (!hasAnalyzed && !isAnalyzing) { analyze() }
    }

    func analyze() {
        guard canRead else { return }
        guard isForeground else {
            hasAnalyzed = false
            return
        }
        stop()
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        let assets = PHAsset.fetchAssets(with: options)
        observedAssets = assets
        let token = generation
        summary = LibrarySummary()
        hasAnalyzed = false
        isAnalyzing = true
        scanTask = Task { [weak self, scanner] in
            do {
                let result = try await scanner.scan(assets) { [weak self] partial in
                    guard let self, self.generation == token else { return }
                    self.summary = partial
                }
                guard let self, self.generation == token else { return }
                self.summary = result
                self.isAnalyzing = false
                self.hasAnalyzed = true
            } catch {
                guard let self, self.generation == token else { return }
                self.isAnalyzing = false
            }
        }
    }

    func stop() {
        generation = UUID()
        scanTask?.cancel()
        scanTask = nil
        isAnalyzing = false
    }

    func suspend() {
        isForeground = false
        stop()
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            self?.handleLibraryChange(changeInstance)
        }
    }

    private func handleLibraryChange(_ change: PHChange) {
        let previous = authorization
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard canRead else {
            stop()
            summary = LibrarySummary()
            hasAnalyzed = false
            observedAssets = nil
            return
        }
        if previous != authorization {
            analyze()
            return
        }
        guard let observedAssets, let details = change.changeDetails(for: observedAssets) else { return }
        self.observedAssets = details.fetchResultAfterChanges
        // Albums, favorites, and other metadata do not change the measured resource bytes.
        let needsAnalysis = !details.hasIncrementalChanges
            || !details.insertedObjects.isEmpty
            || !details.removedObjects.isEmpty
            || details.changedObjects.contains { asset in
                let index = observedAssets.index(of: asset)
                guard index != NSNotFound else { return true }
                let previousAsset = observedAssets.object(at: index)
                guard let objectChange = change.changeDetails(for: previousAsset) else { return false }
                return objectChange.assetContentChanged
                    || objectChange.objectBeforeChanges.mediaType != objectChange.objectAfterChanges?.mediaType
                    || objectChange.objectBeforeChanges.mediaSubtypes != objectChange.objectAfterChanges?.mediaSubtypes
            }
        if needsAnalysis { analyze() }
    }

    isolated deinit {
        scanTask?.cancel()
        if observing { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
    }
}
