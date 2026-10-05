import AVKit
import Photos
import SwiftUI

extension ReviewDecision {
    var color: Color {
        switch self {
        case .skipped: Color(red: 0.20, green: 0.65, blue: 0.43)
        case .resized: Color(red: 0.96, green: 0.75, blue: 0.22)
        case .deleted: Color(red: 0.88, green: 0.27, blue: 0.31)
        }
    }
}

struct SwipeReviewView: View {
    var onReturnToLibrary: (Bool) -> Void = { _ in }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var review: SwipeReviewModel
    @State private var drag = CGSize.zero
    @State private var mediaSize = CGSize.zero
    @State private var isAnimatingDecision = false
    @State private var outgoingDecision: ReviewDecision?
    @State private var transitionToken = UUID()
    @State private var cardOpacity = 1.0
    @State private var showingBulkActions = false
    @State private var showingResetConfirmation = false
    @State private var holdingUndo = false
    @State private var undoHoldProgress: CGFloat = 0
    @State private var actionPlan: ReviewActionPlan?
    @State private var actionPlanRevision: UUID?
    @State private var showingActionSettings = false
    @State private var directDeletion = ActionExecution()
    @State private var deletionError: String?
    @State private var offeredAllowance: FreeAllowance?
    @State private var deferredDecision: ReviewDecision?
    @State private var deferredBulk = false
    @State private var deferredAssetID: String?
    @State private var upgradeConfirmed = false
    @State private var upgradeToken = UUID()

    init(filters: [ReviewFilter] = [], onReturnToLibrary: @escaping (Bool) -> Void = { _ in }) {
        self.onReturnToLibrary = onReturnToLibrary
        _review = State(initialValue: SwipeReviewModel(filters: filters))
    }

    var body: some View {
        VStack(spacing: 20) {
            counters
            if !review.hasAccess {
                ContentUnavailableView(String(localized: "Photo access needed"), systemImage: "photo.badge.exclamationmark", description: Text(String(localized: "Return to your library to update Photos access.")))
            } else if review.isPreparingReview {
                VStack(spacing: 16) {
                    ProgressView(review.isFiltered ? String(localized: "Preparing filtered review…") : String(localized: "Checking formats…"))
                    ProgressView(value: Double(review.preparationProcessed), total: Double(max(1, review.preparationTotal)))
                    Text(String(localized: "\(review.preparationProcessed) of \(review.preparationTotal) checked"))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
                .accessibilityIdentifier("review.checkingFormats")
            } else if review.isComplete {
                completion
            } else if review.currentAsset != nil {
                media
                metadata
            } else {
                ContentUnavailableView(review.isFiltered ? String(localized: "No matching items") : review.excludedFormatCount > 0 ? String(localized: "No supported items") : String(localized: "Your library is empty"), systemImage: "photo.on.rectangle", description: Text(review.isFiltered ? String(localized: "No supported local items match your filters. Go back to adjust the conditions.") : review.excludedFormatCount > 0 ? String(localized: "The available items use formats Pruney cannot process on this device. Your originals are unchanged.") : String(localized: "There are no photos or videos available to review.")))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !directDeletion.isRunning { actions }
        }
        .navigationTitle(String(localized: "Swipe your library"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(directDeletion.isRunning)
        .background {
            ReviewNavigationGestureGuard()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .navigationDestination(isPresented: $showingActionSettings) {
            if let actionPlan {
                ReviewActionSettingsView(plan: actionPlan, onReturnToLibrary: onReturnToLibrary)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "Choose for all remaining items"), systemImage: "forward") {
                    review.pause()
                    showingBulkActions = true
                }
                .labelStyle(.iconOnly)
                .disabled(!review.canDecide || isAnimatingDecision)
                .accessibilityIdentifier("review.bulkActions")
            }
        }
        .confirmationDialog(String(localized: "Choose an action for all \(review.remaining) remaining items"), isPresented: $showingBulkActions, titleVisibility: .visible) {
            Button(String(localized: "Keep all")) { selectAll(.skipped) }
            Button(String(localized: "Resize / Make static")) { selectAll(.resized) }
            Button(String(localized: "Delete all"), role: .destructive) { selectAll(.deleted) }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This only selects actions. Final changes happen later."))
        }
        .onAppear { review.start() }
        .onChange(of: holdingUndo) { _, holding in
            if holding {
                withAnimation(.linear(duration: 1.5)) { undoHoldProgress = 1 }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { undoHoldProgress = 0 }
            }
        }
        .onDisappear {
            transitionToken = UUID()
            isAnimatingDecision = false
            outgoingDecision = nil
            drag = .zero
            cardOpacity = 1
            undoHoldProgress = 0
            holdingUndo = false
            review.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            directDeletion.isActive = phase == .active
            if phase == .active { review.start() }
            else { review.pause() }
        }
        .onChange(of: directDeletion.isFinished) { _, finished in
            guard finished else { return }
            if directDeletion.deletedCount > 0 {
                onReturnToLibrary(true)
            } else if !directDeletion.issues.isEmpty {
                deletionError = directDeletion.issues.map(\.message).joined(separator: "\n")
            }
        }
        .alert(String(localized: "Deletion did not complete"), isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
            Button(String(localized: "OK"), role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "")
        }
        .sheet(item: $review.share, onDismiss: { review.clearShare() }) { share in
            ReviewShareSheet(files: share.files)
        }
        .sheet(item: $offeredAllowance, onDismiss: resolveUpgrade) { allowance in
            let token = upgradeToken
            ProPurchaseView(allowance: allowance,
                            remainingSelections: max(0, allowance.limit - review.count(allowance == .deletions ? .deleted : .resized)),
                            onUnlock: {
                                if upgradeToken == token && offeredAllowance != nil { upgradeConfirmed = true }
                            })
        }
        .alert(String(localized: "Unable to share"), isPresented: Binding(get: { review.shareError != nil }, set: { if !$0 { review.shareError = nil } })) {
            Button(String(localized: "OK"), role: .cancel) { review.shareError = nil }
        } message: {
            Text(review.shareError ?? "")
        }
        .alert(String(localized: "Reset all selections?"), isPresented: $showingResetConfirmation) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Reset"), role: .destructive) {
                drag = .zero
                review.resetSelections()
            }
        } message: {
            Text(String(localized: "Clear your choices and start again from the beginning? Your photos and videos won’t be changed."))
        }
    }

    private var counters: some View {
        HStack(spacing: 14) {
            ForEach([ReviewDecision.deleted, .resized, .skipped], id: \.self) { decision in
                Label("\(review.count(decision))", systemImage: decision.symbol)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(decision.color)
                    .accessibilityLabel(String(localized: "\(decision == .resized ? String(localized: "Resize or make static") : decision.title): \(review.count(decision))"))
            }
            Spacer(minLength: 8)
            Menu {
                Picker(String(localized: "Sort remaining items"), selection: Binding(
                    get: { review.isSorting ? ReviewSortOrder.size : review.sortOrder },
                    set: { order in
                        drag = .zero
                        review.setSortOrder(order)
                    }
                )) {
                    ForEach(ReviewSortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
            } label: {
                Label(review.isSorting ? ReviewSortOrder.size.title : review.sortOrder.title, systemImage: "arrow.up.arrow.down")
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
            }
            .disabled(!review.canSort || isAnimatingDecision)
            .accessibilityLabel(String(localized: "Sort remaining items"))
            .accessibilityValue(review.isSorting ? String(localized: "Sorting by size") : review.sortOrder.title)
            .accessibilityIdentifier("review.sort")
        }
        .accessibilityIdentifier("review.counters")
    }

    private var media: some View {
        GeometryReader { geometry in
            ZStack {
                if review.nextAsset != nil {
                    nextCard
                        .scaleEffect(0.96 + revealProgress * 0.04)
                        .offset(y: (1 - revealProgress) * 8)
                        .opacity(0.7 + revealProgress * 0.3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                currentCard
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 6)
                    .overlay(alignment: (outgoingDecision ?? dragDecision) == .skipped ? .topTrailing : .topLeading) {
                        if review.isLivePhoto { liveBadge }
                    }
                    .overlay(alignment: decisionBadgeAlignment) {
                        if let decision = outgoingDecision ?? dragDecision {
                            Label(decision == .resized && review.isLivePhoto ? String(localized: "Make static") : decision.title,
                                  systemImage: decision == .resized && review.isLivePhoto ? "livephoto.slash" : decision.symbol)
                                .font(.subheadline.bold())
                                .padding(12)
                                .foregroundStyle(decision == .resized ? Color.black : Color.white)
                                .background(decision.color, in: Capsule())
                                .padding(14)
                        }
                    }
                    .rotationEffect(.degrees(reduceMotion ? 0 : max(-12, min(12, Double(drag.width / 35)))))
                    .offset(x: drag.width, y: drag.height)
                    .opacity(cardOpacity)
                    .modifier(ReviewCardDrag(enabled: review.player == nil && review.canDecide && !isAnimatingDecision,
                                             drag: $drag, onDragStarted: review.pause, onDecision: record))
            }
            .coordinateSpace(name: "review.media.drag")
            .onAppear { mediaSize = geometry.size }
            .onChange(of: geometry.size) { _, size in mediaSize = size }
        }
        .frame(maxHeight: .infinity)
        .overlay {
            if review.isSorting {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(String(localized: "Measuring sizes…")).font(.subheadline.weight(.semibold))
                    Text("\(review.sortingProcessed)/\(review.sortingTotal)")
                        .font(.caption).monospacedDigit()
                    Button(String(localized: "Cancel")) { review.cancelSort() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            }
        }
        .accessibilityIdentifier("review.media")
    }

    private var currentCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
            if let player = review.player {
                ReviewVideoCard(player: player,
                                dragSurface: ReviewCardDrag(enabled: review.canDecide && !isAnimatingDecision,
                                                            drag: $drag, onDragStarted: review.pause, onDecision: record),
                                controlsEnabled: review.canDecide && !isAnimatingDecision && drag == .zero)
            } else if let image = review.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(review.isVideo ? String(localized: "Current video preview") : review.isLivePhoto ? String(localized: "Current Live Photo") : String(localized: "Current photo"))
            } else if review.isLoading {
                ProgressView(String(localized: "Loading…"))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "icloud.slash").font(.largeTitle)
                    Text(review.mediaError ?? String(localized: "This item is unavailable."))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding(24)
            }
        }
    }

    private var nextCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
            if let image = review.nextImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if review.isLoadingNextImage {
                ProgressView()
            } else {
                Label(String(localized: "Preview unavailable"), systemImage: "icloud.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .topLeading) {
            if review.nextAsset?.mediaSubtypes.contains(.photoLive) == true {
                liveBadge
            } else if review.nextAsset?.mediaType == .video {
                Image(systemName: "video.fill")
                    .font(.caption.weight(.semibold))
                    .padding(10)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.55), in: Circle())
                    .padding(14)
            }
        }
    }

    private var liveBadge: some View {
        Label(String(localized: "LIVE"), systemImage: "livephoto")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(.white)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(14)
            .accessibilityLabel(String(localized: "Live Photo"))
    }

    private var revealProgress: CGFloat {
        min(1, max(abs(drag.width) / max(mediaSize.width, 1), abs(drag.height) / max(mediaSize.height, 1)))
    }

    private var dragDecision: ReviewDecision? {
        if drag.height < -50 && abs(drag.height) > abs(drag.width) { return .resized }
        if drag.width > 50 { return .skipped }
        if drag.width < -50 { return .deleted }
        return nil
    }

    private var decisionBadgeAlignment: Alignment {
        switch outgoingDecision ?? dragDecision {
        case .skipped: .topLeading
        case .resized: .top
        case .deleted, nil: .topTrailing
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    if let date = review.currentAsset?.creationDate {
                        Text(date, format: .dateTime.month(.abbreviated).day().year())
                    } else {
                        Text(String(localized: "Date unavailable"))
                    }
                    Text("·")
                    Text(sizeText)
                }
                Spacer(minLength: 8)
                Text(String(localized: "\(review.remaining) left"))
                    .monospacedDigit()
                    .fixedSize()
                    .accessibilityLabel(String(localized: "\(review.remaining) of \(review.total) items remaining"))
                    .accessibilityIdentifier("review.remaining")
            }
            if let measurement = review.measurement, !measurement.isComplete {
                Text(String(localized: "Some resources aren’t available locally"))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .accessibilityIdentifier("review.metadata")
    }

    private var sizeText: String {
        guard let measurement = review.measurement else { return String(localized: "Measuring size…") }
        if measurement.bytes == 0 && !measurement.isComplete { return String(localized: "Size unavailable") }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        let size = formatter.string(fromByteCount: measurement.bytes)
        return measurement.isComplete ? size : String(localized: "\(size) (partial)")
    }

    private var actions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                undoControl

                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    actionButton(.deleted)
                    actionButton(.resized)
                    actionButton(.skipped)
                }
                Spacer(minLength: 0)

                Button { review.prepareShare() } label: {
                    ZStack {
                        if review.isPreparingShare { ProgressView() }
                        else { Image(systemName: "square.and.arrow.up").font(.system(size: 18, weight: .medium)) }
                    }
                    .frame(width: 44, height: 44)
                }
                .foregroundStyle(.secondary)
                .disabled(!review.canShare || isAnimatingDecision)
                .accessibilityLabel(String(localized: "Share current item"))
                .accessibilityIdentifier("review.share")
            }
            .buttonStyle(.plain)
            if !ProAccess.shared.isPro {
                Text(String(localized: "This run: \(max(0, FreeAllowance.deletions.limit - review.count(.deleted))) deletes · \(max(0, FreeAllowance.replacements.limit - review.count(.resized))) conversions left"))
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("review.freeAllowance")
            }
            if review.excludedFormatCount > 0 {
                Text(String(localized: "\(review.excludedFormatCount) unsupported items excluded"))
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("review.excludedFormats")
            }
            if review.sizeUnavailableFilterCount > 0 {
                Text(String(localized: "\(review.sizeUnavailableFilterCount) items excluded: size unavailable"))
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("review.unavailableFilterSizes")
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var undoControl: some View {
        let enabled = review.canUndo && !isAnimatingDecision && !directDeletion.isRunning
        return UndoHoldButton(
            enabled: enabled,
            onPressChanged: { holdingUndo = $0 },
            onTap: undoLastDecision,
            onHold: requestReset
        )
            .frame(width: 44, height: 44)
            .overlay {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: undoHoldProgress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .padding(3)
                .opacity(holdingUndo ? 1 : 0)
                .allowsHitTesting(false)
            }
            .contentShape(Circle())
            .opacity(enabled ? 1 : 0.4)

    }

    private func undoLastDecision() {
        withAnimation(.snappy) { review.undo(); drag = .zero }
    }

    private func requestReset() {
        review.pause()
        showingResetConfirmation = true
    }

    private func actionButton(_ decision: ReviewDecision) -> some View {
        Button { record(decision) } label: {
            Image(systemName: decision == .resized && review.isLivePhoto ? "livephoto.slash" : decision.symbol)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(decision == .resized ? Color.black.opacity(0.8) : Color.white)
                .frame(width: 64, height: 64)
                .background(decision.color, in: Circle())
        }
        .disabled(!review.canDecide || isAnimatingDecision)
        .opacity(review.canDecide ? 1 : 0.4)
        .accessibilityLabel(decision == .skipped ? String(localized: "Keep current item") : decision == .resized ? (review.isLivePhoto ? String(localized: "Make current Live Photo static") : String(localized: "Mark current item for resizing")) : String(localized: "Mark current item for deletion"))
        .accessibilityIdentifier("review.\(decision)")
    }

    private func record(_ decision: ReviewDecision) {
        guard review.canDecide, !isAnimatingDecision else { return }
        guard allowDecision(decision, adding: 1, bulk: false) else { return }
        review.pause()
        isAnimatingDecision = true
        outgoingDecision = decision
        let token = UUID()
        transitionToken = token
        let destination: CGSize
        switch decision {
        case .skipped: destination = CGSize(width: max(mediaSize.width, 320) * 1.5, height: drag.height)
        case .resized: destination = CGSize(width: 0, height: -max(mediaSize.height, 400) * 1.5)
        case .deleted: destination = CGSize(width: -max(mediaSize.width, 320) * 1.5, height: drag.height)
        }
        withAnimation(.easeIn(duration: reduceMotion ? 0.12 : 0.28), completionCriteria: .logicallyComplete) {
            drag = reduceMotion ? .zero : destination
            cardOpacity = reduceMotion ? 0 : 1
        } completion: {
            guard transitionToken == token else { return }
            // Advance only after the outgoing card leaves; promote the prefetched preview instantly.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                review.decide(decision)
                drag = .zero
                cardOpacity = 1
                outgoingDecision = nil
                isAnimatingDecision = false
            }
        }
    }

    private func selectAll(_ decision: ReviewDecision) {
        guard review.canDecide, !isAnimatingDecision else { return }
        guard allowDecision(decision, adding: review.remaining, bulk: true) else { return }
        drag = .zero
        withAnimation(.easeInOut(duration: 0.2)) { review.decideAll(decision) }
    }

    private func allowDecision(_ decision: ReviewDecision, adding: Int, bulk: Bool) -> Bool {
        guard decision != .skipped else { return true }
        let access = ProAccess.shared
        guard !access.isPro else { return true }
        let allowance: FreeAllowance = decision == .deleted ? .deletions : .replacements
        guard review.count(decision) + adding > allowance.limit else { return true }
        review.pause()
        withAnimation(.snappy) { drag = .zero }
        deferredDecision = decision
        deferredBulk = bulk
        deferredAssetID = review.currentAsset?.localIdentifier
        upgradeConfirmed = false
        upgradeToken = UUID()
        offeredAllowance = allowance
        return false
    }

    private func resolveUpgrade() {
        let decision = deferredDecision
        let bulk = deferredBulk
        let assetID = deferredAssetID
        let confirmed = upgradeConfirmed
        deferredDecision = nil
        deferredBulk = false
        deferredAssetID = nil
        upgradeConfirmed = false
        upgradeToken = UUID()
        // Cancel never selects an item. Resume only after a verified unlock in the same queue position.
        guard confirmed, ProAccess.shared.isPro, let decision,
              review.currentAsset?.localIdentifier == assetID else { return }
        // A rejected bulk action stays cancelled; the user can explicitly choose it again after unlocking.
        if !bulk { record(decision) }
    }

    private var completion: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(ReviewDecision.skipped.color)
            Text(String(localized: "All reviewed")).font(.title.bold())
            Text(review.count(.resized) > 0 ? String(localized: "Review your selected changes next. Your originals are unchanged.") : String(localized: "Your choices are ready. Your originals are unchanged."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if directDeletion.isRunning {
                ProgressView(String(localized: "Deleting items…"))
                Text(String(localized: "Keep Pruney open until this finishes."))
                    .font(.footnote).foregroundStyle(.secondary)
            } else if review.count(.resized) > 0 {
                Button(String(localized: "Continue")) {
                    if actionPlanRevision != review.selectionRevision {
                        actionPlan = review.makeActionPlan()
                        actionPlanRevision = review.selectionRevision
                    }
                    showingActionSettings = true
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(PruneyStyle.onAccent)
                .accessibilityIdentifier("review.continueToActions")
            } else if review.count(.deleted) > 0 {
                Button(String(localized: "Delete \(review.count(.deleted))"), role: .destructive) {
                    directDeletion = ActionExecution()
                    directDeletion.isActive = scenePhase == .active
                    directDeletion.start(review.makeActionPlan())
                }
                .buttonStyle(.borderedProminent)
                .tint(ReviewDecision.deleted.color)
                .accessibilityIdentifier("review.deleteSelected")
            } else {
                Button(String(localized: "Back to library")) { onReturnToLibrary(false) }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(PruneyStyle.onAccent)
                    .accessibilityIdentifier("review.backToLibrary")
            }
            Spacer()
        }
        .padding(24)
    }
}

private struct ReviewCardDrag: ViewModifier {
    let enabled: Bool
    @Binding var drag: CGSize
    let onDragStarted: () -> Void
    let onDecision: (ReviewDecision) -> Void

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .named("review.media.drag"))
                .onChanged { value in
                    guard enabled else { return }
                    if drag == .zero { onDragStarted() }
                    // Follow the finger in the stationary container, without return-animation lag.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { drag = value.translation }
                }
                .onEnded { value in
                    guard enabled else { return }
                    let movement = value.translation
                    if movement.height < -100 && abs(movement.height) > abs(movement.width) {
                        onDecision(.resized)
                    } else if movement.width > 100 {
                        onDecision(.skipped)
                    } else if movement.width < -100 {
                        onDecision(.deleted)
                    } else {
                        withAnimation(.snappy) { drag = .zero }
                    }
                },
            // A video surface owns its drag; playback controls remain outside that gesture area.
            including: enabled ? .all : .subviews
        )
    }
}

private struct ReviewShareSheet: UIViewControllerRepresentable {
    let files: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: files, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
