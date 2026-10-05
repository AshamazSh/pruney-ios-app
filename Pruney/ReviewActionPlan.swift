import Observation
import Photos

nonisolated enum ReviewActionStage {
    case resize, delete
}

nonisolated enum CompressionLevel: String, CaseIterable, Identifiable {
    case light, balanced, high, maximum
    var id: Self { self }
    var dimensionScale: Double {
        switch self {
        case .light: 0.9
        case .balanced: 0.8
        case .high: 0.7
        case .maximum: 0.5
        }
    }
    var title: String {
        switch self {
        case .light: "Light"
        case .balanced: "Balanced"
        case .high: "High"
        case .maximum: "Maximum"
        }
    }
}

struct ReviewActionItem: Identifiable {
    let asset: PHAsset
    var isSelected = true
    var compressionLevel: CompressionLevel = .maximum
    var id: String { asset.localIdentifier }
    var category: MediaCategory {
        MediaCategory.classify(isVideo: asset.mediaType == .video, isLivePhoto: asset.mediaSubtypes.contains(.photoLive))
    }
    var makesStatic: Bool { category == .livePhoto }
}

@MainActor @Observable
final class ReviewActionPlan {
    private(set) var resizeItems: [ReviewActionItem]
    private(set) var deleteItems: [ReviewActionItem]

    init(resizeAssets: [PHAsset], deleteAssets: [PHAsset]) {
        resizeItems = resizeAssets.map { ReviewActionItem(asset: $0) }
        deleteItems = deleteAssets.map { ReviewActionItem(asset: $0) }
    }

    func items(for stage: ReviewActionStage) -> [ReviewActionItem] {
        stage == .resize ? resizeItems : deleteItems
    }

    func selectedCount(for stage: ReviewActionStage) -> Int {
        items(for: stage).filter(\.isSelected).count
    }

    func toggleSelection(id: String, stage: ReviewActionStage) {
        if stage == .resize, let index = resizeItems.firstIndex(where: { $0.id == id }) {
            resizeItems[index].isSelected.toggle()
        } else if stage == .delete, let index = deleteItems.firstIndex(where: { $0.id == id }) {
            deleteItems[index].isSelected.toggle()
        }
    }

    func setCompression(_ level: CompressionLevel, id: String) {
        guard let index = resizeItems.firstIndex(where: { $0.id == id }), !resizeItems[index].makesStatic else { return }
        resizeItems[index].compressionLevel = level
    }

    func setCompressionForAll(_ level: CompressionLevel) {
        for index in resizeItems.indices where !resizeItems[index].makesStatic {
            resizeItems[index].compressionLevel = level
        }
    }

    var selectedStaticCount: Int { resizeItems.filter { $0.isSelected && $0.makesStatic }.count }
    var selectedResizeCount: Int { resizeItems.filter { $0.isSelected && !$0.makesStatic }.count }
}
