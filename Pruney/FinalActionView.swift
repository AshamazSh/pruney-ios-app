import SwiftUI

struct FinalActionView: View {
    let plan: ReviewActionPlan
    let onReturnToLibrary: (Bool) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var execution = ActionExecution()
    @State private var showingConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if execution.isFinished {
                    result
                } else if execution.isRunning {
                    processing
                } else {
                    overview
                }
            }
            .padding(24)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(execution.isFinished ? "Results" : (execution.hasStarted ? "Applying actions" : "Review actions"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(execution.hasStarted)
        .safeAreaInset(edge: .bottom) {
            if !execution.isRunning {
                Button(execution.isFinished ? "Back to library" : "Start") {
                    if execution.isFinished { onReturnToLibrary(execution.deletedCount > 0 || execution.resizedCount > 0 || execution.madeStaticCount > 0) }
                    else { showingConfirmation = true }
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .buttonStyle(.borderedProminent)
                .foregroundStyle(PruneyStyle.onAccent)
                .disabled(!execution.isFinished && selectedTotal == 0)
                .accessibilityIdentifier(execution.isFinished ? "actions.backToLibrary" : "actions.start")
                .padding(20)
                .background(.regularMaterial)
            }
        }
        .alert("Apply these actions?", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Start", role: .destructive) { execution.start(plan) }
        } message: {
            Text("Delete \(plan.selectedCount(for: .delete)) items, resize \(plan.selectedResizeCount) items, and make \(plan.selectedStaticCount) Live Photos static. Replacements remove their originals. Static photos keep the original still image and lose motion. Pruney cannot undo these changes. Photos may ask for additional confirmation.")
        }
        .onAppear { execution.isActive = scenePhase == .active }
        .onChange(of: scenePhase) { _, phase in execution.isActive = phase == .active }
    }

    private var selectedTotal: Int {
        plan.selectedCount(for: .delete) + plan.selectedCount(for: .resize)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Ready to make room?").font(.title2.bold())
            Text("\(selectedTotal) items selected").foregroundStyle(.secondary)
            summaryCard(stage: .delete, title: "Delete", symbol: "trash", color: ReviewDecision.deleted.color)
            if plan.selectedResizeCount > 0 {
                summaryCard(stage: .resize, title: "Resize", symbol: "arrow.down.right.and.arrow.up.left", color: ReviewDecision.resized.color, staticOnly: false)
            }
            if plan.selectedStaticCount > 0 {
                summaryCard(stage: .resize, title: "Make static", symbol: "livephoto.slash", color: ReviewDecision.resized.color, staticOnly: true)
            }
            if selectedTotal == 0 {
                Text("Go back and select items to apply actions.").foregroundStyle(.secondary)
            }
            if plan.selectedCount(for: .resize) > 0 {
                Text("Replacements remove the originals. Live Photos keep their original still image without resizing or motion.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func summaryCard(stage: ReviewActionStage, title: String, symbol: String, color: Color, staticOnly: Bool? = nil) -> some View {
        let items = plan.items(for: stage).filter { $0.isSelected && (staticOnly == nil || $0.makesStatic == staticOnly) }
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(title, systemImage: symbol).font(.headline).foregroundStyle(color)
                Spacer()
                Text("\(items.count)").font(.title3.bold()).monospacedDigit()
            }
            ForEach(MediaCategory.allCases.filter { staticOnly == nil || ($0 == .livePhoto) == staticOnly }) { category in
                HStack {
                    Label(category.title, systemImage: category.symbol)
                    Spacer()
                    Text("\(items.filter { $0.category == category }.count)").monospacedDigit()
                }
                .font(.subheadline)
            }
            if stage == .resize && staticOnly != true && !items.isEmpty {
                Divider()
                ForEach(CompressionLevel.allCases) { level in
                    let count = items.filter { $0.compressionLevel == level }.count
                    if count > 0 {
                        HStack {
                            Text(level.title)
                            Spacer()
                            Text("\(count)").monospacedDigit()
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private var processing: some View {
        VStack(spacing: 24) {
            ProgressView().controlSize(.large)
            Text(execution.status).font(.title3.bold()).multilineTextAlignment(.center)
            ProgressView(value: execution.progress)
                .accessibilityIdentifier("actions.progress")
            Text(execution.isSavingReplacements ? "Waiting for Photos to save replacements…" : "\(execution.processed) of \(execution.total) processed")
                .monospacedDigit().multilineTextAlignment(.center)
            Text("Keep Pruney open until this finishes.").font(.headline)
            Text("Deleting first, then preparing replacements. Some changes may already be applied.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 48)
    }

    private var result: some View {
        VStack(spacing: 20) {
            Image(systemName: execution.issues.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(execution.issues.isEmpty ? ReviewDecision.skipped.color : Color.orange)
            Text(execution.issues.isEmpty ? "All done!" : "Finished with issues")
                .font(.title.bold())
            Text("\(execution.deletedCount) deleted · \(execution.resizedCount) resized · \(execution.madeStaticCount) made static")
                .font(.headline).monospacedDigit()
            ForEach(execution.issues) { issue in
                VStack(alignment: .leading, spacing: 8) {
                    Text(issue.title).font(.subheadline.bold())
                    Text(issue.message).font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(.vertical, 24)
        .accessibilityIdentifier("actions.result")
    }
}
