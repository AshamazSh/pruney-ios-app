import SwiftUI
import StoreKit

struct ProPurchaseView: View {
    let allowance: FreeAllowance
    let remainingSelections: Int
    let onUnlock: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private let access = ProAccess.shared
    @State private var cancelled = false
    @State private var completed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 16) {
                        Image("PruneyPro")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 128, height: 128)
                            .clipShape(RoundedRectangle(cornerRadius: 28))
                            .accessibilityHidden(true)
                        Text(access.product?.displayName ?? String(localized: "Pruney Pro Lifetime"))
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text(productDescription)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text(String(localized: "One-time purchase · No subscription"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(PruneyStyle.plum)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        benefit(String(localized: "Unlimited deletions"), detail: String(localized: "Clear more in a single run."), symbol: "trash")
                        benefit(String(localized: "Unlimited resizing"), detail: String(localized: "Make photos and videos smaller."), symbol: "arrow.down.right.and.arrow.up.left")
                        benefit(String(localized: "Unlimited Make static"), detail: String(localized: "Remove motion from Live Photos."), symbol: "livephoto.slash")
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 24))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Your free allowance")).font(.subheadline.weight(.semibold))
                        Text(String(localized: "Up to 50 deletions and 10 resize or Make static actions per run."))
                        Text(String(localized: "You can select \(remainingSelections) more \(allowance.title) in this review."))
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(PruneyStyle.background)
            .safeAreaInset(edge: .bottom, spacing: 0) { purchaseControls }
            .navigationTitle("Pruney Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
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
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !access.isPurchasing, !access.isRestoring else { return }
            Task {
                await access.start()
                guard !Task.isCancelled, !access.isPro else { return }
                await access.loadProduct()
            }
        }
    }

    private var productDescription: String {
        guard let description = access.product?.description, !description.isEmpty else {
            return String(localized: "Remove cleanup limits. Lifetime access.")
        }
        return description
    }

    private var purchaseControls: some View {
        VStack(spacing: 12) {
            if let message = access.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task { await access.purchase() }
            } label: {
                HStack(spacing: 10) {
                    if access.isLoading || access.isPurchasing || access.isRestoring {
                        ProgressView().tint(PruneyStyle.onAccent)
                    }
                    Text(purchaseTitle).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .foregroundStyle(PruneyStyle.onAccent)
            .disabled(access.product == nil || access.isLoading || access.isPurchasing || access.isRestoring)
            .accessibilityIdentifier("pro.purchase")

            HStack {
                Button(String(localized: "Restore purchases")) { Task { await access.restore() } }
                    .accessibilityIdentifier("pro.restore")
                if access.product == nil {
                    Spacer()
                    Button(String(localized: "Retry")) { Task { await access.loadProduct() } }
                        .accessibilityIdentifier("pro.retry")
                }
            }
            .font(.subheadline)
            .disabled(access.isPurchasing || access.isRestoring || access.isLoading)
            Text(String(localized: "Cancel keeps your selections unchanged."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var purchaseTitle: String {
        if access.isPurchasing { return String(localized: "Purchasing…") }
        if access.isRestoring { return String(localized: "Restoring…") }
        if access.isLoading { return String(localized: "Loading purchase…") }
        return access.product.map { String(localized: "Unlock lifetime — \($0.displayPrice)") } ?? String(localized: "Purchase unavailable")
    }

    private func benefit(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(PruneyStyle.plum)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func finishUnlock() {
        guard !cancelled, !completed else { return }
        completed = true
        onUnlock()
        dismiss()
    }
}
