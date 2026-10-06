import StoreKit
import StoreKitTest
import XCTest
@testable import Pruney

final class StoreKitReadinessTests: XCTestCase {
    @MainActor private func configuredSession() async throws -> SKTestSession {
        guard ProcessInfo.processInfo.environment["PRUNEY_STOREKIT_INTEGRATION"] == "1" else {
            throw XCTSkip("Enable explicitly for local StoreKit simulation.")
        }
        continueAfterFailure = false
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Pruney-QA.storekit")
        let config: [String: Any] = [
            "identifier": "9DB0CB24-02C1-4D96-AB57-21C3E2BE16D9",
            "nonRenewingSubscriptions": [], "subscriptionGroups": [],
            "products": [["displayPrice": "4.99", "familyShareable": false,
                          "internalID": "194170001", "productID": ProAccess.productID,
                          "referenceName": "Pruney QA Lifetime", "type": "NonConsumable",
                          "localizations": [["description": "Local test purchase only.", "displayName": "Pruney QA Lifetime", "locale": "en_US"]]]],
            "settings": ["_locale": "en_US", "_storefront": "USA"],
            "version": ["major": 3, "minor": 0]
        ]
        try JSONSerialization.data(withJSONObject: config).write(to: url)
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        await ProAccess.shared.start()
        await ProAccess.shared.loadProduct()
        // Never attempt purchase unless the local simulation's distinct product name is loaded.
        guard ProAccess.shared.product?.displayName == "Pruney QA Lifetime" else {
            XCTFail("Local StoreKit product was not loaded; purchase was not attempted.")
            throw XCTSkip("Local StoreKit configuration unavailable.")
        }
        XCTAssertFalse(ProAccess.shared.isPro)
        return session
    }

    @MainActor private func waitForEntitlement(_ expected: Bool) async throws {
        for _ in 0..<100 {
            if ProAccess.shared.isPro == expected { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(ProAccess.shared.isPro, expected)
    }

    @MainActor private func clean(_ session: SKTestSession) async {
        session.clearTransactions()
        await ProAccess.shared.start()
    }

    @MainActor func testLocalPurchaseRestoreAndRefund() async throws {
        let session = try await configuredSession()
        await ProAccess.shared.purchase()
        XCTAssertTrue(ProAccess.shared.isPro)
        XCTAssertTrue(ProAccess.shared.permits(deletions: 500, replacements: 100))
        await ProAccess.shared.restore()
        XCTAssertTrue(ProAccess.shared.isPro)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        try await waitForEntitlement(false)
        XCTAssertFalse(ProAccess.shared.permits(deletions: 51, replacements: 0))
        await clean(session)
    }

    @MainActor func testPendingApprovalDoesNotUnlockUntilApproved() async throws {
        let session = try await configuredSession()
        session.askToBuyEnabled = true
        await ProAccess.shared.purchase()
        XCTAssertFalse(ProAccess.shared.isPro)
        XCTAssertTrue(ProAccess.shared.message?.contains("pending") == true)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: transaction.identifier)
        try await waitForEntitlement(true)
        await clean(session)
    }

    @MainActor func testProductLoadFailureAndRetry() async throws {
        let session = try await configuredSession()
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
        await ProAccess.shared.loadProduct()
        XCTAssertNotNil(ProAccess.shared.message)
        XCTAssertFalse(ProAccess.shared.isLoading)
        XCTAssertFalse(ProAccess.shared.isPro)
        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        await ProAccess.shared.loadProduct()
        XCTAssertNil(ProAccess.shared.message)
        XCTAssertNotNil(ProAccess.shared.product)
        await clean(session)
    }
}
