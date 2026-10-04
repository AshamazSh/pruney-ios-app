import Testing
@testable import Pruney

struct PruneyTests {
    @Test func livePhotosDoNotOverlapWithPhotosOrVideos() {
        #expect(MediaCategory.classify(isVideo: false, isLivePhoto: false) == .photo)
        #expect(MediaCategory.classify(isVideo: false, isLivePhoto: true) == .livePhoto)
        #expect(MediaCategory.classify(isVideo: true, isLivePhoto: false) == .video)
    }

    @Test func summaryTracksPartialResourcesAndProgress() {
        var summary = LibrarySummary(assetCount: 3)
        summary.record(category: .photo, bytes: 100, complete: true)
        summary.record(category: .livePhoto, bytes: 300, complete: true)
        summary.record(category: .video, bytes: 50, complete: false)
        #expect(summary.totalBytes == 450)
        #expect(summary.usage[.photo]?.count == 1)
        #expect(summary.usage[.livePhoto]?.bytes == 300)
        #expect(summary.unavailableCount == 1)
        #expect(summary.progress == 1)
    }

    @Test func emptyLibraryHasNoBytesAndCompletedProgress() {
        let summary = LibrarySummary()
        #expect(summary.totalBytes == 0)
        #expect(summary.progress == 1)
    }
}
