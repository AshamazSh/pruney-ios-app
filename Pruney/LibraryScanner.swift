import Foundation
import Photos
#if DEBUG
import OSLog
#endif

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
    private let cacheURL: URL?
    private var cache = LibraryMeasurementCache()
    private var loadedCache = false
    private var cachePrepared = false
    private var cacheGeneration = UUID()
    private var dirty = false
    private var newMeasurements = 0

    // Review/filter scanners remain fresh; only overview scans use persisted measurements.
    init(cacheURL: URL? = nil) { self.cacheURL = cacheURL }

    func scan(_ assets: PHFetchResult<PHAsset>, changeToken: PHPersistentChangeToken,
              forceRemeasure: Bool = false,
              update: @escaping @MainActor @Sendable (LibrarySummary) -> Void) async throws -> LibrarySummary {
        let clock = ContinuousClock()
        let started = clock.now
        try Task.checkCancellation()
        try prepareCache(for: assets, changeToken: changeToken, forceRemeasure: forceRemeasure)
        let generation = cacheGeneration
        var summary = LibrarySummary(assetCount: assets.count)
        await update(summary)
        var lastUpdate = clock.now
        do {
            for index in 0..<assets.count {
                try Task.checkCancellation()
                guard generation == cacheGeneration else { throw CancellationError() }
                let asset = assets.object(at: index)
                let category = MediaCategory.classify(isVideo: asset.mediaType == .video,
                                                     isLivePhoto: asset.mediaSubtypes.contains(.photoLive))
                let measurement = try await measure(asset)
                try Task.checkCancellation()
                guard generation == cacheGeneration else { throw CancellationError() }
                summary.record(category: category, bytes: measurement.bytes, complete: measurement.isComplete,
                               cached: measurement.isCached)
                // Avoid a main-actor hop for every cached item on large libraries.
                if summary.processed.isMultiple(of: 100) || summary.processed == summary.assetCount
                    || lastUpdate.duration(to: clock.now) >= .milliseconds(200) {
                    lastUpdate = clock.now
                    await update(summary)
                }
            }
            try Task.checkCancellation()
            guard generation == cacheGeneration else { throw CancellationError() }
            saveCache()
            #if DEBUG
            Logger(subsystem: "com.ashamazsh.pruney", category: "LibraryAnalysis")
                .notice("Overview complete: \(summary.cachedCount) cached, \(summary.assetCount - summary.cachedCount) read, \(started.duration(to: clock.now).description, privacy: .public) total")
            #endif
            return summary
        } catch {
            // Keep completed measurements when scanning is interrupted; never commit an obsolete scan.
            if generation == cacheGeneration { saveCache() }
            throw error
        }
    }

    private func prepareCache(for assets: PHFetchResult<PHAsset>, changeToken: PHPersistentChangeToken,
                              forceRemeasure: Bool) throws {
        cacheGeneration = UUID()
        guard let cacheURL else { return }
        if !loadedCache {
            cache = LibraryMeasurementCache.load(from: cacheURL)
            loadedCache = true
        }
        if forceRemeasure {
            cache = LibraryMeasurementCache()
        } else if !cache.entries.isEmpty {
            do {
                guard let data = cache.changeToken,
                      let previousToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self,
                                                                                from: data) else {
                    throw CocoaError(.coderReadCorrupt)
                }
                let changes = try PHPhotoLibrary.shared().fetchPersistentChanges(since: previousToken)
                for change in changes {
                    try Task.checkCancellation()
                    let details = try change.changeDetails(for: .asset)
                    cache.invalidate(details.insertedLocalIdentifiers.union(details.updatedLocalIdentifiers)
                        .union(details.deletedLocalIdentifiers))
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // An expired/unavailable history cannot establish that cached bytes are still valid.
                cache = LibraryMeasurementCache()
            }
        }
        var accessible = Set<String>()
        for index in 0..<assets.count {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            accessible.insert(assets.object(at: index).localIdentifier)
        }
        try Task.checkCancellation()
        cache.retainAccessible(accessible)
        // Save the conservative pre-snapshot token, never a token obtained after reading the files.
        cache.changeToken = try? NSKeyedArchiver.archivedData(withRootObject: changeToken, requiringSecureCoding: true)
        cachePrepared = true
        dirty = true
        newMeasurements = 0
        saveCache()
    }

    func removeCacheIfAccessDenied() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status != .authorized && status != .limited else { return }
        cacheGeneration = UUID()
        cache = LibraryMeasurementCache()
        cachePrepared = false
        loadedCache = true
        dirty = false
        if let cacheURL { try? FileManager.default.removeItem(at: cacheURL) }
    }

    private func saveCache() {
        guard dirty, let cacheURL else { return }
        do {
            try cache.save(to: cacheURL)
            dirty = false
        } catch {
            // Caching is optional; storage failures must not fail a library analysis.
        }
    }

    func measure(_ asset: PHAsset) async throws -> MediaMeasurement {
        try Task.checkCancellation()
        let generation = cacheGeneration
        // Change history invalidates resource edits, so hits need no per-asset resource lookup or byte read.
        if cachePrepared, let cached = cache.measurement(for: asset) { return cached }
        let resources = PHAssetResource.assetResources(for: asset).filter { $0.type != .adjustmentData }
        let fingerprint = MeasurementFingerprint(asset: asset, resources: resources)
        var bytes: Int64 = 0
        var complete = !resources.isEmpty
        for resource in resources {
            try Task.checkCancellation()
            if let size = await read(resource) { bytes += size } else { complete = false }
        }
        try Task.checkCancellation()
        let result = MediaMeasurement(bytes: bytes, isComplete: complete)
        if cachePrepared, generation == cacheGeneration {
            cache.record(result, for: asset.localIdentifier, fingerprint: fingerprint)
            dirty = true
            newMeasurements += 1
            if newMeasurements.isMultiple(of: 200) { saveCache() }
        }
        return result
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
