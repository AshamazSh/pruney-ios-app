import Foundation
import AVFoundation
import ImageIO
import Photos
import Testing
@testable import Pruney

// Opt-in integration coverage reads only generated fixtures and never commits replacements.
@Suite(.serialized)
struct PhotoPreparationIntegrationTests {
    private func fixture(_ filename: String) async throws -> PHAsset {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        try #require(status == .authorized)
        let result = PHAsset.fetchAssets(with: nil)
        let assets = (0..<result.count).map { result.object(at: $0) }
        return try #require(assets.first {
            PHAssetResource.assetResources(for: $0).contains { $0.originalFilename == filename }
        }, "Import the generated QA fixture into the dedicated simulator first: \(filename)")
    }

    private func directories() throws -> Set<URL> {
        Set(try FileManager.default.contentsOfDirectory(at: FileManager.default.temporaryDirectory,
                                                        includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("PruneyResize-") })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PRUNEY_PHOTO_INTEGRATION"] == "1"),
          arguments: ["QA-transparent.png", "QA-animation.gif", "QA-photo.jpg", "QA-photo.heic"])
    func preparedPhotosRetainFormatFramesDimensionsAndCleanup(_ filename: String) async throws {
        let asset = try await fixture(filename)
        let before = try directories()
        let processor = PhotoActionProcessor()
        do {
            try await processor.prepareResize(asset, scale: 0.5, quality: 0.95) { _ in }
            let newDirectories = try directories().subtracting(before)
            #expect(newDirectories.count == 1)
            let directory = try #require(newDirectories.first)
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("source").path))
            let output = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
            let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            #expect((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == 600)
            #expect((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == 450)
            #expect(CGImageSourceCreateImageAtIndex(source, 0, nil) != nil)
            let expectedTypes = ["png": "public.png", "gif": "com.compuserve.gif", "jpg": "public.jpeg", "heic": "public.heic"]
            #expect(CGImageSourceGetType(source) as String? == expectedTypes[URL(fileURLWithPath: filename).pathExtension])
            if filename.hasSuffix("png") { #expect((properties[kCGImagePropertyHasAlpha] as? NSNumber)?.boolValue == true) }
            if filename.hasSuffix("gif") {
                #expect(CGImageSourceGetCount(source) == 2)
                for index in 0..<2 {
                    let frame = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                    let timing = frame?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                    #expect(abs(((timing?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue ?? 0) - 0.15) < 0.001)
                }
            }
            await processor.discardPreparedResizes()
            #expect(try directories() == before)
            #expect(PHAsset.fetchAssets(withLocalIdentifiers: [asset.localIdentifier], options: nil).count == 1)
        } catch {
            await processor.discardPreparedResizes()
            throw error
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PRUNEY_PHOTO_INTEGRATION"] == "1"))
    func videoPreparationProducesSmallerReadableOutputWithoutDeletingOriginal() async throws {
        let asset = try await fixture("QA-video-0.mov")
        let before = try directories()
        let processor = PhotoActionProcessor()
        do {
            try await processor.prepareResize(asset, scale: 0.5, quality: 0.95) { _ in }
            let generated = try directories().subtracting(before)
            #expect(generated.count == 1)
            let directory = try #require(generated.first)
            let output = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
            let movie = AVURLAsset(url: output)
            let duration = try await movie.load(.duration)
            #expect(duration.seconds > 2.5 && duration.seconds < 3.5)
            let track = try #require(try await movie.loadTracks(withMediaType: .video).first)
            let size = try await track.load(.naturalSize)
            #expect(size.width > 0 && size.height > 0)
            #expect(size.width < CGFloat(asset.pixelWidth) && size.height < CGFloat(asset.pixelHeight))
            let generator = AVAssetImageGenerator(asset: movie)
            let frame = try await generator.image(at: .zero)
            #expect(frame.image.width > 0 && frame.image.height > 0)
            await processor.discardPreparedResizes()
            #expect(try directories() == before)
            #expect(PHAsset.fetchAssets(withLocalIdentifiers: [asset.localIdentifier], options: nil).count == 1)
        } catch { await processor.discardPreparedResizes(); throw error }
    }
}
