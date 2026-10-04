import Photos
import SwiftUI

struct ReviewActionSettingsView: View {
    let plan: ReviewActionPlan
    let stage: ReviewActionStage
    @State private var showingDeleteSettings = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(stage == .resize ? "Choose the items to resize and set compression for each one." : "Choose the items to delete. Uncheck anything you want to keep.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if plan.items(for: stage).isEmpty {
                    ContentUnavailableView("No items selected", systemImage: stage == .resize ? "photo.on.rectangle" : "trash", description: Text(stage == .resize ? "No items were marked for resizing." : "No items were marked for deletion."))
                }
                ForEach(MediaCategory.allCases) { category in
                    let items = plan.items(for: stage).filter { $0.category == category }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(category.title).font(.title3.bold())
                                Spacer()
                                Text("\(items.filter(\.isSelected).count)/\(items.count)")
                                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(items) { item in
                                    itemTile(item)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(stage.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if stage == .resize {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Apply all") {
                        ForEach(CompressionLevel.allCases) { level in
                            Button(level.title) { plan.setCompressionForAll(level) }
                        }
                    }
                    .disabled(plan.resizeItems.isEmpty)
                    .accessibilityLabel("Apply compression to all items")
                    .accessibilityIdentifier("resize.applyAll")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Text("\(plan.selectedCount(for: stage)) selected")
                    .font(.subheadline.weight(.medium)).monospacedDigit()
                if stage == .resize {
                    Button("Continue to deletion") { showingDeleteSettings = true }
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("resize.continueToDeletion")
                }
                Text("No changes applied yet.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
        }
        .navigationDestination(isPresented: $showingDeleteSettings) {
            ReviewActionSettingsView(plan: plan, stage: .delete)
        }
    }

    private var selectionColor: Color {
        stage == .resize ? ReviewDecision.resized.color : ReviewDecision.deleted.color
    }

    private func itemTile(_ item: ReviewActionItem) -> some View {
        ZStack {
            Button {
                plan.toggleSelection(id: item.id, stage: stage)
            } label: {
                ActionAssetThumbnail(asset: item.asset)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .opacity(item.isSelected ? 1 : 0.35)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.category.title) item")
            .accessibilityValue(item.isSelected ? "Selected" : "Not selected")
            .accessibilityHint("Double tap to change selection")
            .accessibilityIdentifier("actions.item.\(item.id)")
        }
        .overlay(alignment: .topTrailing) {
            Button { plan.toggleSelection(id: item.id, stage: stage) } label: {
                Image(systemName: item.isSelected ? "checkmark" : "circle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(item.isSelected && stage == .resize ? Color.black : Color.white)
                    .frame(width: 24, height: 24)
                    .background(item.isSelected ? selectionColor : Color.black.opacity(0.5), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isSelected ? "Deselect item" : "Select item")
        }
        .overlay(alignment: .bottomTrailing) {
            if stage == .resize && item.isSelected {
                Menu {
                    Picker("Compression", selection: Binding(
                        get: { item.compressionLevel },
                        set: { plan.setCompression($0, id: item.id) }
                    )) {
                        ForEach(CompressionLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                } label: {
                    Text(item.compressionLevel.title)
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(selectionColor, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .accessibilityLabel("Compression")
                .accessibilityValue(item.compressionLevel.title)
            }
        }
    }
}

private struct ActionAssetThumbnail: View {
    let asset: PHAsset
    @State private var loader = ActionThumbnailLoader()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .secondarySystemGroupedBackground)
                if let image = loader.image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if loader.isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "icloud.slash").foregroundStyle(.secondary)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .overlay(alignment: .topLeading) {
                if asset.mediaSubtypes.contains(.photoLive) {
                    Image(systemName: "livephoto")
                        .font(.caption.weight(.semibold))
                        .padding(6)
                        .foregroundStyle(.white)
                        .background(.black.opacity(0.5), in: Circle())
                        .padding(8)
                }
            }
            .overlay(alignment: .topLeading) {
                if asset.mediaType == .video {
                    Text(videoDuration)
                        .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        .padding(4)
                        .foregroundStyle(.white)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(6)
                }
            }
        }
        .onAppear { loader.load(asset) }
        .onDisappear { loader.cancel() }
        .accessibilityHidden(true)
    }

    private var videoDuration: String {
        let seconds = Int(asset.duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

@MainActor @Observable
private final class ActionThumbnailLoader {
    var image: UIImage?
    var isLoading = false
    private var requestID: PHImageRequestID?
    private var generation = UUID()

    func load(_ asset: PHAsset) {
        cancel()
        isLoading = true
        let token = generation
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        requestID = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 512, height: 512), contentMode: .aspectFill, options: options) { [weak self] image, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                if let image { self.image = image }
                if !degraded { self.isLoading = false }
            }
        }
    }

    func cancel() {
        generation = UUID()
        if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
        requestID = nil
        isLoading = false
    }

    isolated deinit {
        if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
    }
}
