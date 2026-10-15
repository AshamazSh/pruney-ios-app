import Foundation
import Photos
import Observation

// Live Photos are a separate category here so the overview never counts them twice.
nonisolated enum MediaCategory: String, CaseIterable, Identifiable, Sendable {
    case photo, livePhoto, video
    var id: Self { self }
    var title: String {
        switch self {
        case .photo: String(localized: "Photos")
        case .livePhoto: String(localized: "Live Photos")
        case .video: String(localized: "Videos")
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
    var isCached = false
}

nonisolated struct LibrarySummary: Sendable {
    var usage: [MediaCategory: MediaUsage] = [:]
    var processed = 0
    var assetCount = 0
    var unavailableCount = 0
    var cachedCount = 0
    var totalBytes: Int64 { usage.values.reduce(0) { $0 + $1.bytes } }
    var progress: Double { assetCount == 0 ? 1 : Double(processed) / Double(assetCount) }
    mutating func record(category: MediaCategory, bytes: Int64, complete: Bool, cached: Bool = false) {
        var item = usage[category, default: MediaUsage()]
        item.count += 1
        item.bytes += bytes
        usage[category] = item
        processed += 1
        if !complete { unavailableCount += 1 }
        if cached { cachedCount += 1 }
    }
}

@MainActor @Observable
final class LibraryAnalysis: NSObject, PHPhotoLibraryChangeObserver {
    private(set) var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var summary = LibrarySummary()
    private(set) var isAnalyzing = false
    private(set) var hasAnalyzed = false
    private let scanner = LibraryScanner(cacheURL: LibraryMeasurementCache.fileURL)
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
        #if DEBUG
        if AppStoreScreenshot.scene != nil {
            authorization = .authorized
            summary = LibrarySummary(usage: [
                .photo: MediaUsage(bytes: 1_840_000_000, count: 428),
                .livePhoto: MediaUsage(bytes: 940_000_000, count: 86),
                .video: MediaUsage(bytes: 8_020_000_000, count: 54)
            ], processed: 568, assetCount: 568)
            hasAnalyzed = true
            isAnalyzing = false
            return
        }
        #endif
        isForeground = true
        let previous = authorization
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard canRead else {
            stop()
            summary = LibrarySummary()
            hasAnalyzed = false
            observedAssets = nil
            Task { await scanner.removeCacheIfAccessDenied() }
            return
        }
        if !observing {
            PHPhotoLibrary.shared().register(self)
            observing = true
        }
        if previous != authorization || (!hasAnalyzed && !isAnalyzing) { analyze() }
    }

    func analyze(forceRemeasure: Bool = false) {
        guard canRead else { return }
        guard isForeground else {
            hasAnalyzed = false
            return
        }
        stop()
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        // Capture before the snapshot so concurrent edits remain in the next change-history replay.
        let changeToken = PHPhotoLibrary.shared().currentChangeToken
        let assets = PHAsset.fetchAssets(with: options)
        observedAssets = assets
        let token = generation
        summary = LibrarySummary()
        hasAnalyzed = false
        isAnalyzing = true
        scanTask = Task { [weak self, scanner] in
            do {
                let result = try await scanner.scan(assets, changeToken: changeToken, forceRemeasure: forceRemeasure) { [weak self] partial in
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
            Task { await scanner.removeCacheIfAccessDenied() }
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
        if needsAnalysis { analyze(forceRemeasure: !details.hasIncrementalChanges) }
    }

    isolated deinit {
        scanTask?.cancel()
        if observing { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
    }
}
