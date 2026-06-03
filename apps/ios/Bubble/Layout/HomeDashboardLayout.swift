import SwiftUI

struct ScaledDesignSpace {
    let designSize: CGSize
    let actualSize: CGSize
    let scale: CGFloat
    let origin: CGPoint

    init(designSize: CGSize, actualSize: CGSize) {
        self.designSize = designSize
        self.actualSize = actualSize

        let widthScale = designSize.width > 0 ? actualSize.width / designSize.width : 1
        let heightScale = designSize.height > 0 ? actualSize.height / designSize.height : 1
        let resolvedScale = min(widthScale, heightScale)
        scale = resolvedScale.isFinite && resolvedScale > 0 ? resolvedScale : 1

        let fittedSize = CGSize(
            width: designSize.width * scale,
            height: designSize.height * scale
        )
        origin = CGPoint(
            x: (actualSize.width - fittedSize.width) / 2,
            y: (actualSize.height - fittedSize.height) / 2
        )
    }

    func x(_ value: CGFloat) -> CGFloat {
        origin.x + value * scale
    }

    func y(_ value: CGFloat) -> CGFloat {
        origin.y + value * scale
    }

    func size(_ value: CGFloat) -> CGFloat {
        value * scale
    }

    func point(x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(x: self.x(x), y: self.y(y))
    }

    func rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: self.x(x),
            y: self.y(y),
            width: size(width),
            height: size(height)
        )
    }
}

struct HomeDashboardLayout {
    let screenSize: CGSize
    let safeAreaInsets: EdgeInsets
    let contentSizeCategory: ContentSizeCategory

    let contentWidth: CGFloat
    let scale: CGFloat
    let availableHeight: CGFloat

    let logoSize: CGSize
    let greetingHeight: CGFloat
    let blockerHeight: CGFloat
    let insightsHeight: CGFloat
    let dockHeight: CGFloat
    let dockBottomPadding: CGFloat
    let dockReservedHeight: CGFloat
    let mountainSize: CGSize
    let mountainCenter: CGPoint

    let contentTopInset: CGFloat
    let topPadding: CGFloat
    let logoToGreeting: CGFloat
    let greetingToBlocker: CGFloat
    let blockerToInsights: CGFloat
    let insightsToDock: CGFloat
    let bottomPadding: CGFloat

    let contentHeight: CGFloat
    let requiresScroll: Bool

    init(
        screenSize: CGSize,
        safeAreaInsets: EdgeInsets,
        contentSizeCategory: ContentSizeCategory
    ) {
        self.screenSize = screenSize
        self.safeAreaInsets = safeAreaInsets
        self.contentSizeCategory = contentSizeCategory

        let availableWidth = max(0, screenSize.width)
        let sidePadding = HomeDashboardLayoutConstants.horizontalMargin
        let availableContentWidth = max(0, availableWidth - sidePadding * 2)
        contentWidth = min(HomeDashboardLayoutConstants.maxContentWidth, availableContentWidth)
        scale = contentWidth / HomeDashboardLayoutConstants.figmaContentWidth

        logoSize = CGSize(
            width: HomeDashboardLayoutConstants.logoSize.width * scale,
            height: HomeDashboardLayoutConstants.logoSize.height * scale
        )
        greetingHeight = HomeDashboardLayoutConstants.greetingHeight * scale
        blockerHeight = HomeDashboardLayoutConstants.blockerHeight * scale
        insightsHeight = HomeDashboardLayoutConstants.insightsHeight * scale
        dockHeight = HomeDashboardLayoutConstants.dockHeight * scale
        dockBottomPadding = HomeDashboardLayoutConstants.minimumDockBottomPadding * scale
        dockReservedHeight = dockHeight
            + dockBottomPadding
        let liftedContentTopInset = safeAreaInsets.top
            + HomeDashboardLayoutConstants.idealTopPadding * scale
            - HomeDashboardLayoutConstants.contentTopLift * scale
        contentTopInset = max(0, liftedContentTopInset)
        let resolvedAvailableHeight = max(0, screenSize.height - contentTopInset - dockReservedHeight)
        availableHeight = resolvedAvailableHeight

        mountainSize = CGSize(
            width: HomeDashboardLayoutConstants.mountainSize.width * scale,
            height: HomeDashboardLayoutConstants.mountainSize.height * scale
        )

        let fixedHeight = logoSize.height
            + greetingHeight
            + blockerHeight
            + insightsHeight

        let idealLogoToGreeting = HomeDashboardLayoutConstants.idealLogoToGreeting * scale
        let minimumLogoToGreeting = HomeDashboardLayoutConstants.minimumLogoToGreeting * scale
        let minimumLowerSectionGap = HomeDashboardLayoutConstants.minimumLowerSectionGap * scale
        let idealLowerHeight = fixedHeight
            + idealLogoToGreeting
            + minimumLowerSectionGap * 3
        let logoToGreetingGap = idealLowerHeight <= resolvedAvailableHeight
            ? idealLogoToGreeting
            : minimumLogoToGreeting
        let lowerSectionGap = max(
            minimumLowerSectionGap,
            (resolvedAvailableHeight - fixedHeight - logoToGreetingGap) / 3
        )

        let fittedSpacings = HomeDashboardLayoutSpacings(
            top: 0,
            logoToGreeting: logoToGreetingGap,
            greetingToBlocker: lowerSectionGap,
            blockerToInsights: lowerSectionGap,
            insightsToDock: 0,
            bottom: lowerSectionGap
        )
        let minimumHeight = fixedHeight
            + minimumLogoToGreeting
            + minimumLowerSectionGap * 3

        topPadding = fittedSpacings.top
        logoToGreeting = fittedSpacings.logoToGreeting
        greetingToBlocker = fittedSpacings.greetingToBlocker
        blockerToInsights = fittedSpacings.blockerToInsights
        insightsToDock = fittedSpacings.insightsToDock
        bottomPadding = fittedSpacings.bottom

        contentHeight = fixedHeight + fittedSpacings.total
        requiresScroll = minimumHeight > resolvedAvailableHeight
            || contentSizeCategory.bubbleRequiresHomeScroll

        mountainCenter = CGPoint(
            x: screenSize.width / 2 + HomeDashboardLayoutConstants.mountainCenterOffsetX * scale,
            y: contentTopInset + HomeDashboardLayoutConstants.mountainCenterY * scale
        )
    }

    var contentMinX: CGFloat {
        (screenSize.width - contentWidth) / 2
    }

    static let debugOverlayEnabled = false
}

private struct HomeDashboardLayoutSpacings {
    let top: CGFloat
    let logoToGreeting: CGFloat
    let greetingToBlocker: CGFloat
    let blockerToInsights: CGFloat
    let insightsToDock: CGFloat
    let bottom: CGFloat

    var total: CGFloat {
        top + logoToGreeting + greetingToBlocker + blockerToInsights + insightsToDock + bottom
    }

    func compressed(toward minimum: HomeDashboardLayoutSpacings, amount: CGFloat) -> HomeDashboardLayoutSpacings {
        let clamped = min(max(amount, 0), 1)
        return HomeDashboardLayoutSpacings(
            top: top - (top - minimum.top) * clamped,
            logoToGreeting: logoToGreeting - (logoToGreeting - minimum.logoToGreeting) * clamped,
            greetingToBlocker: greetingToBlocker - (greetingToBlocker - minimum.greetingToBlocker) * clamped,
            blockerToInsights: blockerToInsights - (blockerToInsights - minimum.blockerToInsights) * clamped,
            insightsToDock: insightsToDock - (insightsToDock - minimum.insightsToDock) * clamped,
            bottom: bottom - (bottom - minimum.bottom) * clamped
        )
    }
}

private enum HomeDashboardLayoutConstants {
    static let figmaContentWidth: CGFloat = 357
    static let horizontalMargin: CGFloat = 18
    static let maxContentWidth: CGFloat = 357

    static let logoSize = CGSize(width: 139, height: 50.4)
    static let greetingHeight: CGFloat = 126
    static let blockerHeight: CGFloat = 367
    static let insightsHeight: CGFloat = 126
    static let dockHeight: CGFloat = 58
    static let minimumDockBottomPadding: CGFloat = 2
    static let contentTopLift: CGFloat = 74
    static let mountainSize = CGSize(width: 340, height: 150)
    static let mountainCenterOffsetX: CGFloat = 116
    static let mountainCenterY: CGFloat = 176

    static let idealTopPadding: CGFloat = 8
    static let idealLogoToGreeting: CGFloat = 16

    static let minimumTopPadding: CGFloat = 0
    static let minimumLogoToGreeting: CGFloat = 8
    static let minimumLowerSectionGap: CGFloat = 14
}

private extension ContentSizeCategory {
    var bubbleRequiresHomeScroll: Bool {
        switch self {
        case .accessibilityMedium,
             .accessibilityLarge,
             .accessibilityExtraLarge,
             .accessibilityExtraExtraLarge,
             .accessibilityExtraExtraExtraLarge:
            return true
        default:
            return false
        }
    }
}
