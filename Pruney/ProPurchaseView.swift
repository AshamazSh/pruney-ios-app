import SwiftUI
import StoreKit

struct ProPurchaseView: View {
    let allowance: FreeAllowance
    let remainingSelections: Int
    let onUnlock: () -> Void
    @Environment(\.dismiss) private var dismiss
    private let access = ProAccess.shared
    @State private var cancelled = false
    @State private var completed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(PruneyStyle.plum)
                    Text("Unlock Pruney Pro").font(.largeTitle.bold())
                    Text("The free plan allows up to \(allowance.limit) \(allowance.title) per run. You can select \(remainingSelections) more in this review without Pro.")
                    Text("Unlimited deletions, resizing, and Live Photo conversion.").font(.headline)
                    Text("One-time purchase. Lifetime access. No subscription.").foregroundStyle(.secondary)
                    Text("Cancel to keep your current item and choices unchanged.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let message = access.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    if access.isLoading { ProgressView("Loading purchase…") }
                    Button {
                        Task { await access.purchase() }
                    } label: {
                        Text(access.product.map { "Unlock lifetime — \($0.displayPrice)" } ?? "Purchase unavailable")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .foregroundStyle(PruneyStyle.onAccent)
                    .disabled(access.product == nil || access.isPurchasing || access.isRestoring)
                    .accessibilityIdentifier("pro.purchase")
                    if access.isPurchasing || access.isRestoring { ProgressView() }
                    HStack {
                        Button("Restore purchases") { Task { await access.restore() } }
                            .accessibilityIdentifier("pro.restore")
                        Spacer()
                        if access.product == nil {
                            Button("Retry") { Task { await access.loadProduct() } }
                        }
                    }
                    .disabled(access.isPurchasing || access.isRestoring || access.isLoading)
                }
                .padding(24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(PruneyStyle.background)
            .navigationTitle("Pruney Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelled = true
                        dismiss()
                    }
                        .accessibilityIdentifier("pro.cancel")
                }
            }
        }
        .tint(PruneyStyle.plum)
        .presentationDragIndicator(.visible)
        .task {
            await access.start()
            guard !Task.isCancelled else { return }
            if access.isPro { finishUnlock() }
            else { await access.loadProduct() }
        }
        .onChange(of: access.isPro) { _, unlocked in
            if unlocked { finishUnlock() }
        }
    }

    private func finishUnlock() {
        guard !cancelled, !completed else { return }
        completed = true
        onUnlock()
        dismiss()
    }
}
