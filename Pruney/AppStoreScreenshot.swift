#if DEBUG
import Photos
import SwiftUI

// Read-only fixture presentation for reproducible App Store artwork. Excluded from Release.
@MainActor enum AppStoreScreenshot {
    static var scene: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-appStoreScreenshot"), arguments.indices.contains(index + 1) else { return nil }
        let value = arguments[index + 1]
        return ["overview", "swipe", "filters", "resize", "final"].contains(value) ? value : nil
    }

    static var assets: [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        return (0..<result.count).map { result.object(at: $0) }.filter { asset in
            PHAssetResource.assetResources(for: asset).contains { resource in
                let name = resource.originalFilename
                return name.hasPrefix("video-") || (name.count == 6 && name.hasSuffix(".png") && Int(name.prefix(2)) != nil)
            }
        }
    }

    static func plan() -> ReviewActionPlan {
        let photos = assets.filter { $0.mediaType == .image }
        let videos = assets.filter { $0.mediaType == .video }
        let plan = ReviewActionPlan(resizeAssets: Array(photos.prefix(6)) + Array(videos.prefix(3)),
                                    deleteAssets: Array(photos.suffix(4)))
        for (index, item) in plan.resizeItems.enumerated() {
            plan.setCompression(CompressionLevel.allCases[index % 4], id: item.id)
        }
        if let item = plan.resizeItems.dropFirst(4).first {
            plan.toggleSelection(id: item.id, stage: .resize)
        }
        return plan
    }
}

@MainActor struct AppStoreScreenshotView: View {
    let scene: String
    @State private var path: [String] = []
    @State private var plan = AppStoreScreenshot.plan()

    var body: some View {
        Group {
            if scene == "overview" {
                ContentView()
            } else {
                NavigationStack(path: $path) {
                    Color(uiColor: .systemGroupedBackground)
                        .navigationTitle("Pruney")
                        .navigationDestination(for: String.self) { _ in
                            switch scene {
                            case "swipe": SwipeReviewView()
                            case "filters": ReviewFiltersView()
                            case "resize": ReviewActionSettingsView(plan: plan)
                            default: FinalActionView(plan: plan, onReturnToLibrary: { _ in })
                            }
                        }
                        .task { if path.isEmpty { path = [scene] } }
                }
                .tint(PruneyStyle.plum)
            }
        }
        .allowsHitTesting(false)
    }
}
#endif
