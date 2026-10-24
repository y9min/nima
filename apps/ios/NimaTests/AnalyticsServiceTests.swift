import Foundation
import XCTest
@testable import Nima

final class AnalyticsServiceTests: XCTestCase {
    func testPurchaseAttemptPropertiesKeepOneCorrelationIDAndProductDetails() {
        let id = UUID(uuidString: "AD5BD194-FF5C-42FD-A358-E4F97A869B13")!
        let startedAt = Date(timeIntervalSince1970: 100)
        let attempt = PurchaseAnalyticsAttempt(
            id: id,
            startedAt: startedAt,
            offeringID: "default",
            packageID: "$rc_annual",
            productID: "nima.pro.yearly",
            price: 29.99,
            currencyCode: "GBP",
            localizedPrice: "£29.99"
        )

        let properties = attempt.properties(now: Date(timeIntervalSince1970: 102.5))

        XCTAssertEqual(properties["purchase_attempt_id"] as? String, id.uuidString.lowercased())
        XCTAssertEqual(properties["offering_id"] as? String, "default")
        XCTAssertEqual(properties["package_id"] as? String, "$rc_annual")
        XCTAssertEqual(properties["product_id"] as? String, "nima.pro.yearly")
        XCTAssertEqual(properties["price"] as? Double, 29.99)
        XCTAssertEqual(properties["currency"] as? String, "GBP")
        XCTAssertEqual(properties["duration_ms"] as? Int, 2_500)
    }

    func testStoreKitErrorIncludesRevenueCatAndUnderlyingAppleCodes() {
        let storeError = NSError(domain: "SKErrorDomain", code: 2)
        let error = NSError(
            domain: "RevenueCat.ErrorCode",
            code: 2,
            userInfo: [
                NSUnderlyingErrorKey: storeError,
                "readable_error_code": "STORE_PROBLEM",
            ]
        )

        let properties = PurchaseAnalytics.errorProperties(error)

        XCTAssertEqual(properties["error_source"] as? String, "apple_storekit")
        XCTAssertEqual(properties["revenuecat_error_code"] as? Int, 2)
        XCTAssertEqual(properties["revenuecat_error_name"] as? String, "STORE_PROBLEM")
        XCTAssertEqual(properties["store_error_domain"] as? String, "SKErrorDomain")
        XCTAssertEqual(properties["store_error_code"] as? Int, 2)
    }

    func testBackendErrorIsSeparatedFromAppleCheckoutErrors() {
        let error = NSError(
            domain: "RevenueCat.ErrorCode",
            code: 12,
            userInfo: [
                "rc_backend_error_code": 7225,
                "rc_response_status_code": 500,
            ]
        )

        let properties = PurchaseAnalytics.errorProperties(error)

        XCTAssertEqual(properties["error_source"] as? String, "revenuecat_backend")
        XCTAssertEqual(properties["revenuecat_backend_error_code"] as? Int, 7225)
        XCTAssertEqual(properties["http_status_code"] as? Int, 500)
        XCTAssertNil(properties["store_error_code"])
    }

    func testNetworkErrorsHaveTheirOwnSource() {
        let error = NSError(domain: "RevenueCat.ErrorCode", code: 10)

        XCTAssertEqual(PurchaseAnalytics.errorSource(error), "network")
    }
}
