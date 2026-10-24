import StoreKit
import SwiftUI

@main
struct NimaStoreKitHarnessApp: App {
    var body: some Scene {
        WindowGroup {
            PurchaseHarnessView()
        }
    }
}

private struct PurchaseHarnessView: View {
    private static let monthlyProductID = "so.nima.app.pro.monthly"

    @State private var status = "Preparing a fresh local purchase…"
    @State private var hasRun = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: status.hasPrefix("PASS") ? "checkmark.seal.fill" : "cart.fill")
                .font(.system(size: 56))
                .foregroundStyle(status.hasPrefix("PASS") ? .green : .blue)

            Text("Nima StoreKit Test")
                .font(.title.bold())

            Text(status)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("purchase-test-status")
        }
        .padding(32)
        .task {
            guard !hasRun else { return }
            hasRun = true
            await runPurchaseTest()
        }
    }

    @MainActor
    private func runPurchaseTest() async {
        do {
            let before = await activeProductIDs()
            guard before.isEmpty else {
                status = "FAIL — the local receipt was not empty before checkout."
                print("NIMA_STOREKIT_AUTOMATION_FAIL preexisting_entitlement=\(before.sorted())")
                return
            }

            let products = try await Product.products(for: [Self.monthlyProductID])
            guard let product = products.first(where: { $0.id == Self.monthlyProductID }) else {
                status = "FAIL — monthly product was not loaded."
                print("NIMA_STOREKIT_AUTOMATION_FAIL product_not_loaded")
                return
            }

            status = "Completing local Apple checkout…"
            let result = try await product.purchase()
            guard case let .success(verification) = result else {
                status = "FAIL — checkout did not complete: \(String(describing: result))"
                print("NIMA_STOREKIT_AUTOMATION_FAIL purchase_result=\(String(describing: result))")
                return
            }

            let transaction = try verification.payloadValue
            guard transaction.productID == Self.monthlyProductID,
                  transaction.revocationDate == nil,
                  transaction.expirationDate.map({ $0 > Date() }) ?? false else {
                status = "FAIL — Apple returned an inactive transaction."
                print("NIMA_STOREKIT_AUTOMATION_FAIL inactive_transaction")
                return
            }
            await transaction.finish()

            let after = await waitForActiveProductIDs()
            guard after == [Self.monthlyProductID] else {
                status = "FAIL — active entitlement did not match the purchase."
                print("NIMA_STOREKIT_AUTOMATION_FAIL entitlements=\(after.sorted())")
                return
            }

            status = "PASS — fresh £4.99 monthly purchase created a verified active entitlement."
            print("NIMA_STOREKIT_AUTOMATION_PASS product=\(Self.monthlyProductID)")
        } catch {
            status = "FAIL — \(error.localizedDescription)"
            print("NIMA_STOREKIT_AUTOMATION_FAIL error=\(String(reflecting: error))")
        }
    }

    private func activeProductIDs() async -> Set<String> {
        var identifiers = Set<String>()

        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  transaction.revocationDate == nil,
                  transaction.expirationDate.map({ $0 > Date() }) ?? true else {
                continue
            }
            identifiers.insert(transaction.productID)
        }

        return identifiers
    }

    private func waitForActiveProductIDs() async -> Set<String> {
        for _ in 0..<40 {
            let identifiers = await activeProductIDs()
            if !identifiers.isEmpty {
                return identifiers
            }
            try? await Task.sleep(for: .milliseconds(250))
        }

        return await activeProductIDs()
    }
}
