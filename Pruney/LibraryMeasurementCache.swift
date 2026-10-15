import Foundation
import Photos

// Resource descriptors and public asset metadata identify the bytes a measurement describes.
nonisolated struct MeasurementFingerprint: Codable, Equatable, Sendable {
    struct Resource: Codable, Equatable, Sendable {
        let type: Int
        let format: String
        let filename: String
    }

    let modified: Date?
    let mediaType: Int
    let subtypes: UInt
    let width: Int
    let height: Int
    let duration: Double
    let resources: [Resource]

    func matchesMetadata(of asset: PHAsset) -> Bool {
        modified == asset.modificationDate && mediaType == asset.mediaType.rawValue
            && subtypes == asset.mediaSubtypes.rawValue && width == asset.pixelWidth
            && height == asset.pixelHeight && duration == (asset.duration.isFinite ? asset.duration : 0)
    }

    init(asset: PHAsset, resources: [PHAssetResource]) {
        modified = asset.modificationDate
        mediaType = asset.mediaType.rawValue
        subtypes = asset.mediaSubtypes.rawValue
        width = asset.pixelWidth
        height = asset.pixelHeight
        duration = asset.duration.isFinite ? asset.duration : 0
        self.resources = resources.map { Resource(type: $0.type.rawValue, format: $0.uniformTypeIdentifier,
                                                  filename: $0.originalFilename) }
    }
}

nonisolated struct LibraryMeasurementCache: Codable, Sendable {
    struct Entry: Codable, Sendable {
        let fingerprint: MeasurementFingerprint
        let bytes: Int64
    }

    // Increment when resource-selection or measurement semantics change.
    private var version = 1
    var changeToken: Data?
    private(set) var entries: [String: Entry] = [:]

    static var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PruneyMeasurements", isDirectory: true)
            .appendingPathComponent("measurements-v1.json")
    }

    static func load(from url: URL) -> Self {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let cache = try? JSONDecoder().decode(Self.self, from: data), cache.version == 1,
              cache.entries.values.allSatisfy({ $0.bytes >= 0 }) else { return Self() }
        var total: Int64 = 0
        for entry in cache.entries.values {
            let sum = total.addingReportingOverflow(entry.bytes)
            guard !sum.overflow else { return Self() }
            total = sum.partialValue
        }
        return cache
    }

    func measurement(for asset: PHAsset) -> MediaMeasurement? {
        guard let entry = entries[asset.localIdentifier], entry.fingerprint.matchesMetadata(of: asset) else { return nil }
        return MediaMeasurement(bytes: entry.bytes, isComplete: true, isCached: true)
    }

    mutating func record(_ measurement: MediaMeasurement, for identifier: String, fingerprint: MeasurementFingerprint) {
        // Partial/cloud-unavailable results must be retried rather than frozen across launches.
        if measurement.isComplete {
            entries[identifier] = Entry(fingerprint: fingerprint, bytes: measurement.bytes)
        } else {
            entries.removeValue(forKey: identifier)
        }
    }

    mutating func invalidate(_ identifiers: Set<String>) {
        for identifier in identifiers { entries.removeValue(forKey: identifier) }
    }

    mutating func retainAccessible(_ identifiers: Set<String>) {
        entries = entries.filter { identifiers.contains($0.key) }
    }

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
