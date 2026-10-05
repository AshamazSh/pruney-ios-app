    import SwiftUI
import Photos

extension MediaCategory {
    var color: Color {
        switch self {
        case .photo: Color(red: 0.55, green: 0.38, blue: 0.75)
        case .livePhoto: Color(red: 0.25, green: 0.66, blue: 0.57)
        case .video: Color(red: 0.94, green: 0.61, blue: 0.35)
        }
    }
    var symbol: String {
        switch self {
        case .photo: "photo"
        case .livePhoto: "livephoto"
        case .video: "video"
        }
    }
}

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var analysis = LibraryAnalysis()
    @State private var requestingAccess = false
    @State private var showingSizeInformation = false
    @State private var showingSwipeReview = false
    @State private var showingFilters = false
    @State private var showingRecentlyDeletedNotice = false
    @State private var pendingRecentlyDeletedNotice = false

    var body: some View {
        Group {
            if hasCompletedOnboarding { overview } else { onboarding }
        }
        .tint(PruneyStyle.plum)
        .task { if hasCompletedOnboarding { analysis.refresh() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, hasCompletedOnboarding { analysis.refresh() }
            if phase == .background { analysis.suspend() }
        }
    }

    private var onboarding: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 48)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(PruneyStyle.plum)
                    .frame(width: 140, height: 140)
                    .background(PruneyStyle.plum.opacity(0.09), in: RoundedRectangle(cornerRadius: 44))
                VStack(spacing: 16) {
                    Text("Welcome to Pruney")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("Make room for more")
                        .font(.title3.weight(.medium))
                    Text("Let’s start with your photo library. Pruney shows how much space your photos, Live Photos, and videos take up, so you can start clearing room.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                Label("You decide what to keep", systemImage: "checkmark.shield")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 40)
                Button {
                    requestingAccess = true
                    Task {
                        await analysis.requestAccess()
                        hasCompletedOnboarding = true
                        requestingAccess = false
                    }
                } label: {
                    HStack {
                        if requestingAccess { ProgressView().tint(PruneyStyle.onAccent) }
                        Text("Continue").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(PruneyStyle.onAccent)
                .disabled(requestingAccess)
                .accessibilityIdentifier("onboarding.continue")
                Text("Next, allow access to your photo library.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(PruneyStyle.background)
    }

    private var overview: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your library").font(.largeTitle.bold())
                        Text("See what’s taking up space")
                            .foregroundStyle(.secondary)
                    }
                    if analysis.canRead {
                        if analysis.authorization == .limited {
                            notice(title: "Access to selected photos", message: "These totals include only the photos and videos you’ve shared. Allow full access in Settings to analyze your entire library.", symbol: "photo.badge.checkmark") {
                                settingsButton
                            }
                        }
                        storageCard
                        if analysis.isAnalyzing {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    ProgressView()
                                    Text("Analyzing your library…").font(.subheadline.weight(.medium))
                                }
                                ProgressView(value: analysis.summary.progress)
                                Text("Processed \(analysis.summary.processed) of \(analysis.summary.assetCount)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else if analysis.hasAnalyzed && analysis.summary.assetCount == 0 {
                            notice(title: "Your library is empty", message: analysis.authorization == .limited ? "There are no photos or videos in the shared part of your library. Update access in Settings or add new files." : "Your library has no photos or videos yet. Pruney will update the totals when you add some.", symbol: "photo.on.rectangle") { EmptyView() }
                        }
                        if analysis.hasAnalyzed && !analysis.isAnalyzing {
                            reviewOptions
                        }
                    } else {
                        accessError
                    }
                }
                .padding(24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(PruneyStyle.background)
            .navigationTitle("Pruney")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showingSwipeReview) {
                SwipeReviewView(onReturnToLibrary: { didRemoveAssets in
                    pendingRecentlyDeletedNotice = didRemoveAssets
                    showingSwipeReview = false
                    analysis.analyze()
                })
            }
            .navigationDestination(isPresented: $showingFilters) {
                ReviewFiltersView(onReturnToLibrary: { didRemoveAssets in
                    pendingRecentlyDeletedNotice = didRemoveAssets
                    showingFilters = false
                    analysis.analyze()
                })
            }
            .toolbar {
                if analysis.canRead {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Refresh totals", systemImage: "arrow.clockwise") {
                            analysis.analyze()
                        }
                        .labelStyle(.iconOnly)
                        .disabled(analysis.isAnalyzing)
                        .accessibilityIdentifier("library.refresh")
                    }
                }
            }
            .alert("Recently Deleted", isPresented: $showingRecentlyDeletedNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Deleted files remain in Recently Deleted for up to 30 days. To free up space now, open Photos and empty Recently Deleted yourself.")
            }
            .onAppear {
                if pendingRecentlyDeletedNotice {
                    pendingRecentlyDeletedNotice = false
                    showingRecentlyDeletedNotice = true
                }
            }
        }
    }

    private var reviewOptions: some View {
        VStack(spacing: 12) {
            ReviewOptionTile(
                title: "Start swiping",
                description: analysis.authorization == .limited
                    ? "Review supported photos and videos you’ve shared with Pruney, one swipe at a time."
                    : "Review supported photos and videos in your library, one swipe at a time.",
                symbol: "rectangle.stack",
                isPrimary: true,
                action: { showingSwipeReview = true }
            )
            .accessibilityIdentifier("library.startSwiping")

            ReviewOptionTile(
                title: "Set up filters",
                description: "Choose which photos and videos to review before you start swiping.",
                symbol: "slider.horizontal.3",
                isPrimary: false,
                action: { showingFilters = true }
            )
            .accessibilityIdentifier("library.setUpFilters")
        }
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(analysis.isAnalyzing ? "Measured so far" : "Accessible file size")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .hidden()
                        .overlay {
                            Button {
                                showingSizeInformation = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.subheadline)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(PruneyStyle.plum)
                            .accessibilityLabel("How we calculate size")
                            .accessibilityIdentifier("library.sizeInformation")
                            .popover(isPresented: $showingSizeInformation) {
                                sizeInformation
                                    .presentationCompactAdaptation(.popover)
                            }
                        }
                }
                Text(formattedBytes(analysis.summary.totalBytes))
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .contentTransition(.numericText())
                Text("\(analysis.summary.assetCount) photos and videos")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            StorageBar(summary: analysis.summary)
            if analysis.summary.unavailableCount > 0 {
                Text("Some items couldn’t be fully measured. Tap ⓘ for details.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 20) {
                ForEach(MediaCategory.allCases) { category in
                    let usage = analysis.summary.usage[category, default: MediaUsage()]
                    HStack(spacing: 12) {
                        Image(systemName: category.symbol)
                            .foregroundStyle(category.color)
                            .frame(width: 36, height: 36)
                            .background(category.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.title).font(.subheadline.weight(.medium))
                            Text("\(usage.count) items").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formattedBytes(usage.bytes))
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                }
            }
        }
        .padding(24)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
    }

    private var sizeInformation: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("How we calculate size")
                    .font(.headline)
                Spacer(minLength: 8)
                Button("Done") { showingSizeInformation = false }
                    .font(.subheadline.weight(.semibold))
            }
            Text("We measure accessible local files, including the photo and motion in Live Photos. This may differ from the storage shown in iPhone Settings. Files in iCloud aren’t downloaded.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if analysis.summary.unavailableCount > 0 {
                Text("Couldn’t fully measure \(analysis.summary.unavailableCount) items. They may be stored in iCloud. The total size is incomplete.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
        .frame(idealWidth: 340, maxWidth: 360)
        .tint(PruneyStyle.plum)
    }

    private var accessError: some View {
        notice(title: "Photo access needed", message: accessExplanation, symbol: "photo.badge.exclamationmark") {
            if analysis.authorization == .notDetermined {
                Button("Allow access") { Task { await analysis.requestAccess() } }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(PruneyStyle.onAccent)
            } else if analysis.authorization != .restricted {
                settingsButton
            }
        }
        .accessibilityIdentifier("library.accessError")
    }

    private var accessExplanation: String {
        if analysis.authorization == .restricted {
            return "Photo access is restricted by the system. Check your Screen Time restrictions or contact your device administrator."
        }
        return "Pruney needs photo access to show the size of your photos and videos. Open Settings → Photos and allow full access or select specific photos."
    }

    private var settingsButton: some View {
        Button("Open Settings", systemImage: "gearshape") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        .buttonStyle(.borderedProminent)
        .foregroundStyle(PruneyStyle.onAccent)
    }

    private func notice<Actions: View>(title: String, message: String, symbol: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol).font(.title).foregroundStyle(PruneyStyle.plum)
            Text(title).font(.title3.bold())
            Text(message).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            actions()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct ReviewOptionTile: View {
    let title: String
    let description: String
    let symbol: String
    let isPrimary: Bool
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(isPrimary ? PruneyStyle.onAccent : PruneyStyle.plum)
                    .frame(width: 44, height: 44)
                    .background(
                        isPrimary ? PruneyStyle.onAccent.opacity(0.15) : PruneyStyle.plum.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(isPrimary ? PruneyStyle.onAccent : Color.primary)
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(isPrimary ? PruneyStyle.onAccent.opacity(0.85) : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isPrimary ? PruneyStyle.plum : Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 24)
            )
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }
}

private struct StorageBar: View {
    let summary: LibrarySummary
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(MediaCategory.allCases) { category in
                    let bytes = summary.usage[category]?.bytes ?? 0
                    if bytes > 0, summary.totalBytes > 0 {
                        category.color.frame(width: geometry.size.width * CGFloat(bytes) / CGFloat(summary.totalBytes))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Storage breakdown for photos, Live Photos, and videos")
        .accessibilityValue(MediaCategory.allCases.map { "\($0.title): \(formattedBytes(summary.usage[$0]?.bytes ?? 0))" }.joined(separator: ", "))
    }
}

#Preview { ContentView() }

private func formattedBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: bytes)
}
