import Observation
import Photos
import UIKit

struct ActionExecutionIssue: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor @Observable
final class ActionExecution {
    private(set) var hasStarted = false
    private(set) var isRunning = false
    private(set) var isFinished = false
    private(set) var deletedCount = 0
    private(set) var resizedCount = 0
    private(set) var madeStaticCount = 0
    private(set) var processed = 0
    private(set) var total = 0
    private(set) var itemProgress = 0.0
    private(set) var isSavingReplacements = false
    private(set) var status = String(localized: "Preparing…")
    private(set) var issues: [ActionExecutionIssue] = []
    var isActive = true
    private let processor = PhotoActionProcessor()
    private var executionTask: Task<Void, Never>?
    private var hasResizeCandidates = false

    var progress: Double {
        guard total > 0 else { return 0 }
        let completed = min(1, (Double(processed) + itemProgress) / Double(total))
        return hasResizeCandidates && !isFinished ? completed * 0.9 : completed
    }

    func start(_ plan: ReviewActionPlan) {
        guard !hasStarted else { return }
        let deletes = plan.deleteItems.filter(\.isSelected).map(\.asset)
        let resizes = plan.resizeItems.filter(\.isSelected)
        guard !deletes.isEmpty || !resizes.isEmpty else { return }
        let access = ProAccess.shared
        guard access.permits(deletions: deletes.count, replacements: resizes.count) else {
            hasStarted = true
            isFinished = true
            issues.append(ActionExecutionIssue(title: String(localized: "Free allowance exceeded"), message: String(localized: "Your selection exceeds the free per-run limit. Return to review and reduce your choices or unlock Pruney Pro. No actions were applied.")))
            return
        }
        hasStarted = true
        isRunning = true
        total = deletes.count + resizes.count
        hasResizeCandidates = !resizes.isEmpty
        executionTask = Task {
            let previousIdleSetting = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            defer {
                UIApplication.shared.isIdleTimerDisabled = previousIdleSetting
                isRunning = false
                isSavingReplacements = false
                isFinished = true
                executionTask = nil
            }
            let authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard authorization == .authorized || authorization == .limited else {
                issues.append(ActionExecutionIssue(title: String(localized: "Photo access needed"), message: String(localized: "Allow Photos access in Settings, then start a new review.")))
                return
            }
            if !deletes.isEmpty {
                await waitForForeground()
                status = String(localized: "Deleting \(deletes.count) items…")
                do {
                    try await processor.delete(deletes)
                    deletedCount = deletes.count
                    processed = deletes.count
                } catch {
                    issues.append(ActionExecutionIssue(title: String(localized: "Deletion did not complete"), message: resizes.isEmpty ? error.localizedDescription : String(localized: "Replacement actions were not started. \(error.localizedDescription)")))
                    return
                }
            }
            var preparedCount = 0
            var preparedStaticCount = 0
            for (index, item) in resizes.enumerated() {
                await waitForForeground()
                status = item.makesStatic ? String(localized: "Making Live Photo static — \(index + 1) of \(resizes.count)…") : String(localized: "Resizing item \(index + 1) of \(resizes.count)…")
                itemProgress = 0
                let completedBeforeItem = processed
                do {
                    try await processor.prepareResize(item.asset, scale: item.compressionLevel.dimensionScale, quality: 0.95) { [weak self] progress in
                        guard let self, self.processed == completedBeforeItem else { return }
                        self.itemProgress = progress
                    }
                    preparedCount += 1
                    if item.makesStatic { preparedStaticCount += 1 }
                } catch {
                    issues.append(ActionExecutionIssue(title: String(localized: "\(item.makesStatic ? String(localized: "Make static") : String(localized: "Resize")) item \(index + 1) — \(item.category.title)"), message: error.localizedDescription))
                }
                processed += 1
                itemProgress = 0
            }
            if preparedCount > 0 {
                await waitForForeground()
                isSavingReplacements = true
                status = String(localized: "Saving \(preparedCount) replacements…")
                do {
                    let committedCount = try await processor.commitPreparedResizes()
                    madeStaticCount = preparedStaticCount
                    resizedCount = committedCount - preparedStaticCount
                } catch {
                    issues.append(ActionExecutionIssue(title: String(localized: "Replacements were not saved"), message: String(localized: "No replacement originals were removed. Any earlier deletions remain applied. \(error.localizedDescription)")))
                }
            }
            await processor.discardPreparedResizes()
        }
    }

    private func waitForForeground() async {
        while !isActive {
            status = String(localized: "Waiting for the app to return…")
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}
