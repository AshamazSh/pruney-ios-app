import Foundation
import Photos

nonisolated enum FilterDateRule: String, CaseIterable, Identifiable, Sendable {
    case from, through
    var id: Self { self }
    var title: String { self == .from ? "From" : "To" }
}

nonisolated enum FilterSizeRule: String, CaseIterable, Identifiable, Sendable {
    case less, greater
    var id: Self { self }
    var title: String { self == .less ? "Less than" : "Greater than" }
}

nonisolated struct ReviewFilter: Identifiable, Sendable {
    let id = UUID()
    var category: MediaCategory?
    var dateRule: FilterDateRule = .from
    var date: Date?
    var sizeRule: FilterSizeRule = .greater
    var sizeMegabytes: Int?

    var summary: String {
        var parts: [String] = []
        if let category { parts.append(category.title) }
        if let date {
            let formatted = date.formatted(date: .abbreviated, time: .omitted)
            parts.append(dateRule == .from ? "Created on or after \(formatted)" : "Created on or before \(formatted)")
        }
        if let sizeMegabytes {
            parts.append("\(sizeRule.title) \(Self.sizeLabel(sizeMegabytes))")
        }
        return parts.joined(separator: " · ")
    }

    static func sizeLabel(_ megabytes: Int) -> String {
        megabytes == 1_000 ? "1 GB" : "\(megabytes) MB"
    }

    func matchesMetadata(_ asset: PHAsset) -> Bool {
        if let category {
            let actual = MediaCategory.classify(isVideo: asset.mediaType == .video, isLivePhoto: asset.mediaSubtypes.contains(.photoLive))
            guard actual == category else { return false }
        }
        if let date {
            guard let created = asset.creationDate else { return false }
            let day = Calendar.current.startOfDay(for: date)
            if dateRule == .from {
                guard created >= day else { return false }
            } else {
                guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day), created < nextDay else { return false }
            }
        }
        return true
    }

    func matchesSize(_ measurement: MediaMeasurement?) -> Bool {
        guard let sizeMegabytes else { return true }
        guard let measurement, measurement.isComplete else { return false }
        let threshold = Int64(sizeMegabytes) * 1_000_000
        return sizeRule == .less ? measurement.bytes < threshold : measurement.bytes > threshold
    }
}
