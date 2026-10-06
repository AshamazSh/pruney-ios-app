import Foundation
import ImageIO
import Photos
import Testing
import UniformTypeIdentifiers
@testable import Pruney

// Metadata-only doubles never read or change a real Photos asset.
private final class MetadataAsset: PHAsset, @unchecked Sendable {
    private let identifier: String
    private let kind: PHAssetMediaType
    private let subtypes: PHAssetMediaSubtype
    private let created: Date?
    override var localIdentifier: String { identifier }
    override var mediaType: PHAssetMediaType { kind }
    override var mediaSubtypes: PHAssetMediaSubtype { subtypes }
    override var creationDate: Date? { created }

    init(_ identifier: String, kind: PHAssetMediaType = .image,
         live: Bool = false, date: Date? = nil) {
        self.identifier = identifier
        self.kind = kind
        subtypes = live ? .photoLive : []
        created = date
        super.init()
    }
}

struct ReleaseFilterTests {
    @Test(arguments: [FilterSizeRule.less, .greater])
    func sizeBoundsAreStrictDecimalBytes(_ rule: FilterSizeRule) {
        let filter = ReviewFilter(sizeRule: rule, sizeMegabytes: 1)
        #expect(!filter.matchesSize(MediaMeasurement(bytes: 1_000_000, isComplete: true)))
        #expect(filter.matchesSize(MediaMeasurement(bytes: rule == .less ? 999_999 : 1_000_001, isComplete: true)))
        #expect(!filter.matchesSize(MediaMeasurement(bytes: rule == .less ? 1_000_001 : 999_999, isComplete: true)))
        #expect(!filter.matchesSize(MediaMeasurement(bytes: 999_999, isComplete: false)))
        #expect(!filter.matchesSize(nil))
    }

    @Test func disabledSizeConditionAcceptsMissingOrPartialMeasurement() {
        let filter = ReviewFilter()
        #expect(filter.matchesSize(nil))
        #expect(filter.matchesSize(MediaMeasurement(bytes: 0, isComplete: false)))
    }

    @Test func oneGigabyteUsesDecimalBytes() {
        let filter = ReviewFilter(sizeRule: .greater, sizeMegabytes: 1_000)
        #expect(!filter.matchesSize(MediaMeasurement(bytes: 1_000_000_000, isComplete: true)))
        #expect(filter.matchesSize(MediaMeasurement(bytes: 1_000_000_001, isComplete: true)))
    }

    @Test func categoryFiltersAreMutuallyExclusive() {
        let photo = MetadataAsset("photo")
        let live = MetadataAsset("live", live: true)
        let video = MetadataAsset("video", kind: .video)
        for (category, matching) in [(MediaCategory.photo, photo), (.livePhoto, live), (.video, video)] {
            let filter = ReviewFilter(category: category)
            for asset in [photo, live, video] {
                #expect(filter.matchesMetadata(asset) == (asset === matching))
            }
        }
    }

    @Test func dateBoundsIncludeTheEntireSelectedCalendarDay() throws {
        let calendar = Calendar.current
        let selected = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))
        let start = calendar.startOfDay(for: selected)
        let next = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        let from = ReviewFilter(dateRule: .from, date: selected)
        let through = ReviewFilter(dateRule: .through, date: selected)
        #expect(!from.matchesMetadata(MetadataAsset("before", date: start.addingTimeInterval(-1))))
        #expect(from.matchesMetadata(MetadataAsset("start", date: start)))
        #expect(through.matchesMetadata(MetadataAsset("end", date: next.addingTimeInterval(-1))))
        #expect(!through.matchesMetadata(MetadataAsset("next", date: next)))
        #expect(!from.matchesMetadata(MetadataAsset("missing")))
        #expect(ReviewFilter().matchesMetadata(MetadataAsset("missing")))
    }

    @Test func enabledCategoryAndDateMustBothMatch() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let filter = ReviewFilter(category: .video, date: date)
        #expect(!filter.matchesMetadata(MetadataAsset("photo", date: date)))
        #expect(!filter.matchesMetadata(MetadataAsset("old-video", kind: .video, date: date.addingTimeInterval(-172_800))))
        #expect(filter.matchesMetadata(MetadataAsset("video", kind: .video, date: date)))
    }
}

@MainActor struct ReleaseActionPlanTests {
    @Test func applyAllIgnoresLivePhotosAndPreservesDeselection() {
        let photo = MetadataAsset("photo")
        let live = MetadataAsset("live", live: true)
        let video = MetadataAsset("video", kind: .video)
        let plan = ReviewActionPlan(resizeAssets: [photo, live, video], deleteAssets: [])
        plan.toggleSelection(id: photo.localIdentifier, stage: .resize)
        plan.setCompressionForAll(.light)
        #expect(plan.resizeItems.map(\.id) == ["photo", "live", "video"])
        #expect(!plan.resizeItems[0].isSelected)
        #expect(plan.resizeItems[0].compressionLevel == .light)
        #expect(plan.resizeItems[1].compressionLevel == .maximum)
        #expect(plan.resizeItems[2].compressionLevel == .light)
        #expect(plan.selectedStaticCount == 1)
        #expect(plan.selectedResizeCount == 1)
        plan.setCompression(.high, id: live.localIdentifier)
        #expect(plan.resizeItems[1].compressionLevel == .maximum)
        plan.toggleSelection(id: photo.localIdentifier, stage: .resize)
        #expect(plan.resizeItems[0].compressionLevel == .light)
        #expect(plan.selectedResizeCount == 2)
    }

    @Test(arguments: [(50, 10, true), (51, 10, false), (50, 11, false), (0, 0, true), (0, 11, false), (51, 0, false)])
    func freeLimitsAreIndependentAndInclusive(_ values: (Int, Int, Bool)) {
        #expect(!ProAccess.shared.isPro)
        #expect(ProAccess.shared.permits(deletions: values.0, replacements: values.1) == values.2)
    }

    @Test func capacityIsNotConsumedByValidation() {
        for _ in 0..<3 { #expect(ProAccess.shared.permits(deletions: 50, replacements: 10)) }
    }

    @Test func overLimitExecutionStopsBeforeTouchingPhotos() {
        let assets = (0..<51).map { MetadataAsset("delete-\($0)") }
        let execution = ActionExecution()
        execution.start(ReviewActionPlan(resizeAssets: [], deleteAssets: assets))
        #expect(execution.isFinished)
        #expect(!execution.isRunning)
        #expect(execution.deletedCount == 0)
        #expect(execution.resizedCount == 0)
        #expect(execution.madeStaticCount == 0)
        #expect(execution.issues.count == 1)
    }

    @Test func emptyExecutionDoesNotStart() {
        let execution = ActionExecution()
        execution.start(ReviewActionPlan(resizeAssets: [], deleteAssets: []))
        #expect(!execution.hasStarted)
        #expect(!execution.isRunning)
        #expect(execution.issues.isEmpty)
    }
}

struct ReleaseFormatTests {
    @Test func commonImageFormatsFollowDeviceCapabilitiesAndRawIsExcluded() {
        let formats = SupportedMediaFormats()
        let readers = Set(CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])
        let writers = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
        for type in [UTType.jpeg, .png, .heic, .gif, .tiff, .bmp] {
            #expect(formats.canEncodePhoto(type) == (readers.contains(type.identifier) && writers.contains(type.identifier)))
        }
        #expect(!formats.canEncodePhoto(.rawImage))
        #expect(!formats.canEncodePhoto(.plainText))
        #expect(!formats.canEncodePhoto(.movie))
    }
}
