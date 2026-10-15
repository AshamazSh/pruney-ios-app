import Foundation
import Photos
import Testing
@testable import Pruney

struct LibraryMeasurementCacheTests {
    @Test func persistedMeasurementsRoundTripWithTheirToken() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("cache.json")
        let asset = CacheFixtureAsset()
        var cache = LibraryMeasurementCache()
        cache.changeToken = Data([1, 2, 3])
        cache.record(MediaMeasurement(bytes: 4_000_000, isComplete: true), for: asset.localIdentifier,
                     fingerprint: MeasurementFingerprint(asset: asset, resources: []))
        try cache.save(to: url)
        let loaded = LibraryMeasurementCache.load(from: url)
        #expect(loaded.changeToken == cache.changeToken)
        #expect(loaded.measurement(for: asset)?.bytes == 4_000_000)
        #expect(loaded.measurement(for: asset)?.isCached == true)
    }

    @Test func editsAndPartialMeasurementsCannotReuseCompleteSizes() {
        let asset = CacheFixtureAsset()
        var cache = LibraryMeasurementCache()
        cache.record(MediaMeasurement(bytes: 400, isComplete: true), for: asset.localIdentifier,
                     fingerprint: MeasurementFingerprint(asset: asset, resources: []))
        asset.modified = Date(timeIntervalSince1970: 200)
        #expect(cache.measurement(for: asset) == nil)
        cache.record(MediaMeasurement(bytes: 100, isComplete: false), for: asset.localIdentifier,
                     fingerprint: MeasurementFingerprint(asset: asset, resources: []))
        #expect(cache.measurement(for: asset) == nil)
        #expect(cache.entries.isEmpty)
    }

    @Test func historyInvalidationAndLimitedScopeRemoveEntries() {
        let first = CacheFixtureAsset()
        let second = CacheFixtureAsset(identifier: "second")
        var cache = LibraryMeasurementCache()
        for asset in [first, second] {
            cache.record(MediaMeasurement(bytes: 400, isComplete: true), for: asset.localIdentifier,
                         fingerprint: MeasurementFingerprint(asset: asset, resources: []))
        }
        cache.invalidate([first.localIdentifier])
        #expect(cache.measurement(for: first) == nil)
        #expect(cache.measurement(for: second) != nil)
        cache.retainAccessible([])
        #expect(cache.entries.isEmpty)
    }

    @Test func missingCorruptAndIncompatibleCacheRebuildSafely() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(LibraryMeasurementCache.load(from: url).entries.isEmpty)
        try Data("not a cache".utf8).write(to: url)
        #expect(LibraryMeasurementCache.load(from: url).entries.isEmpty)
        try Data(#"{"version":2,"entries":{},"changeToken":"AQID"}"#.utf8).write(to: url)
        #expect(LibraryMeasurementCache.load(from: url).changeToken == nil)
    }

    @Test func summaryDistinguishesSavedMeasurementsFromIncompleteReads() {
        var summary = LibrarySummary(assetCount: 2)
        summary.record(category: .photo, bytes: 100, complete: true, cached: true)
        summary.record(category: .video, bytes: 50, complete: false)
        #expect(summary.cachedCount == 1)
        #expect(summary.unavailableCount == 1)
        #expect(summary.totalBytes == 150)
    }
}

// Pure metadata fixture: never accesses Photos resources or mutates a photo library.
private final class CacheFixtureAsset: PHAsset {
    private let identifier: String
    var modified = Date(timeIntervalSince1970: 100)
    init(identifier: String = "first") { self.identifier = identifier; super.init() }
    override var localIdentifier: String { identifier }
    override var modificationDate: Date? { modified }
    override var mediaType: PHAssetMediaType { .image }
    override var mediaSubtypes: PHAssetMediaSubtype { [] }
    override var pixelWidth: Int { 1200 }
    override var pixelHeight: Int { 900 }
    override var duration: TimeInterval { 0 }
}
