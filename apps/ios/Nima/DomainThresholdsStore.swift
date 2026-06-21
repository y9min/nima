import Foundation

@available(*, deprecated, message: "Legacy per-domain thresholds are removed. Use featurePolicyV1 toggles.")
final class DomainThresholdsStore {
    static let shared = DomainThresholdsStore()
    private init() {}
}
