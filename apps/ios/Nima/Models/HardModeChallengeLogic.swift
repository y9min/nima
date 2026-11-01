import CoreGraphics
import CoreText
import Foundation
import UIKit

struct HardModeCoverageResult: Equatable {
    let targetCoverage: Double
    let inkPrecision: Double
    let coveredRegions: Int
    let passed: Bool
}

enum HardModePathScorer {
    static func evaluate(
        targetGroups: [[CGPoint]],
        drawingGroups: [[CGPoint]],
        tolerance: CGFloat = 0.045,
        minimumCoverage: Double = 0.35,
        minimumInkPrecision: Double = 0.35,
        minimumRegions: Int = 3,
        minimumCoveragePerRequiredGroup: Double = 0
    ) -> HardModeCoverageResult {
        guard !targetGroups.isEmpty,
              drawingGroups.contains(where: { $0.count >= 2 }) else {
            return HardModeCoverageResult(
                targetCoverage: 0,
                inkPrecision: 0,
                coveredRegions: 0,
                passed: false
            )
        }

        let targetSamples = targetGroups.flatMap {
            resample(points: $0, spacing: max(0.004, tolerance * 0.28))
        }
        let drawingSamples = drawingGroups.flatMap {
            resample(points: $0, spacing: max(0.004, tolerance * 0.28))
        }
        guard !targetSamples.isEmpty, !drawingSamples.isEmpty else {
            return HardModeCoverageResult(
                targetCoverage: 0,
                inkPrecision: 0,
                coveredRegions: 0,
                passed: false
            )
        }

        let coveredTarget = targetSamples.map { point in
            drawingSamples.contains { distance($0, point) <= tolerance }
        }
        let targetCoverage = Double(coveredTarget.filter { $0 }.count) / Double(coveredTarget.count)
        let nearbyInk = drawingSamples.filter { ink in
            targetSamples.contains { distance(ink, $0) <= tolerance }
        }
        let inkPrecision = Double(nearbyInk.count) / Double(drawingSamples.count)
        let coveredRegions = Set<Int>(targetSamples.enumerated().compactMap { index, point in
            guard coveredTarget[index] else { return nil }
            return Int(min(5, max(0, floor(point.x * 6))))
        }).count

        let groupsPass = targetGroups.allSatisfy { group in
            let samples = resample(points: group, spacing: max(0.004, tolerance * 0.28))
            guard !samples.isEmpty else { return false }
            let coverage = Double(samples.filter { targetPoint in
                drawingSamples.contains { distance($0, targetPoint) <= tolerance }
            }.count) / Double(samples.count)
            return coverage >= minimumCoveragePerRequiredGroup
        }

        return HardModeCoverageResult(
            targetCoverage: targetCoverage,
            inkPrecision: inkPrecision,
            coveredRegions: coveredRegions,
            passed: targetCoverage >= minimumCoverage
                && inkPrecision >= minimumInkPrecision
                && coveredRegions >= minimumRegions
                && groupsPass
        )
    }

    static func resample(points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard let first = points.first else { return [] }
        var output = [first]
        var remaining = spacing
        for (start, end) in zip(points, points.dropFirst()) {
            let segmentLength = distance(start, end)
            guard segmentLength > 0 else { continue }
            var offset = remaining
            while offset <= segmentLength {
                let ratio = offset / segmentLength
                output.append(CGPoint(
                    x: start.x + (end.x - start.x) * ratio,
                    y: start.y + (end.y - start.y) * ratio
                ))
                offset += spacing
            }
            remaining = max(0, offset - segmentLength)
        }
        return output
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

enum HardModeRasterTraceScorer {
    static func evaluate(
        image: UIImage,
        drawingGroups: [[CGPoint]],
        canvasSize: CGSize,
        imageInset: CGFloat = 0,
        tolerance: CGFloat = 0.065,
        minimumCoverage: Double = 0.35,
        minimumInkPrecision: Double = 0.35,
        minimumRegions: Int = 3
    ) -> HardModeCoverageResult {
        guard drawingGroups.contains(where: { $0.count >= 2 }),
              canvasSize.width > 0,
              canvasSize.height > 0 else {
            return HardModeCoverageResult(
                targetCoverage: 0,
                inkPrecision: 0,
                coveredRegions: 0,
                passed: false
            )
        }

        let target = targetPoints(
            image: image,
            canvasSize: canvasSize,
            imageInset: imageInset
        )
        let drawing = drawingGroups.flatMap {
            HardModePathScorer.resample(
                points: $0,
                spacing: max(0.004, tolerance * 0.28)
            )
        }
        guard !target.isEmpty else {
            return HardModeCoverageResult(
                targetCoverage: 0,
                inkPrecision: 0,
                coveredRegions: 0,
                passed: false
            )
        }

        let covered = target.map { targetPoint in
            drawing.contains { distance($0, targetPoint) <= tolerance }
        }
        let targetCoverage = Double(covered.filter { $0 }.count) / Double(covered.count)
        let nearbyInk = drawing.filter { ink in
            target.contains { distance(ink, $0) <= tolerance }
        }
        let inkPrecision = Double(nearbyInk.count) / Double(drawing.count)
        let coveredRegions = Set<Int>(target.enumerated().compactMap { index, point in
            guard covered[index] else { return nil }
            return Int(min(5, max(0, floor(point.x * 6))))
        }).count

        return HardModeCoverageResult(
            targetCoverage: targetCoverage,
            inkPrecision: inkPrecision,
            coveredRegions: coveredRegions,
            passed: targetCoverage >= minimumCoverage
                && inkPrecision >= minimumInkPrecision
                && coveredRegions >= minimumRegions
        )
    }

    static func targetPoints(
        image: UIImage,
        canvasSize: CGSize,
        imageInset: CGFloat = 0
    ) -> [CGPoint] {
        guard let cgImage = image.cgImage else { return [] }
        let width = 110
        let height = max(1, Int((CGFloat(width) * CGFloat(cgImage.height) / CGFloat(cgImage.width)).rounded()))
        let bytesPerRow = width * 4
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return []
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixelData = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return []
        }

        let inset = max(0, min(imageInset, min(canvasSize.width, canvasSize.height) / 2 - 1))
        let availableWidth = max(1, canvasSize.width - inset * 2)
        let availableHeight = max(1, canvasSize.height - inset * 2)
        let imageAspect = CGFloat(cgImage.width) / CGFloat(cgImage.height)
        let availableAspect = availableWidth / availableHeight
        let fitted: CGRect
        if imageAspect > availableAspect {
            let fittedHeight = availableWidth / imageAspect
            fitted = CGRect(
                x: inset,
                y: (canvasSize.height - fittedHeight) / 2,
                width: availableWidth,
                height: fittedHeight
            )
        } else {
            let fittedWidth = availableHeight * imageAspect
            fitted = CGRect(
                x: (canvasSize.width - fittedWidth) / 2,
                y: inset,
                width: fittedWidth,
                height: availableHeight
            )
        }

        var points: [CGPoint] = []
        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixelData[y * bytesPerRow + x * 4 + 3]
                guard alpha > 24 else { continue }
                points.append(CGPoint(
                    x: (fitted.minX + (CGFloat(x) + 0.5) / CGFloat(width) * fitted.width)
                        / canvasSize.width,
                    y: (fitted.minY + (CGFloat(y) + 0.5) / CGFloat(height) * fitted.height)
                        / canvasSize.height
                ))
            }
        }
        return points
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

struct HardModeSortItem: Identifiable, Equatable, Sendable {
    let id: Int
    let lightness: Double
    let size: Double
}

enum HardModeSortChallenge {
    static let items: [HardModeSortItem] = (0..<15).map { index in
        HardModeSortItem(
            id: index,
            lightness: 0.14 + Double(index) * 0.045,
            size: 0.28 + Double(index) * 0.047
        )
    }

    static let rankedItemIDs = items.map(\.id)

    static func isCorrect(_ slots: [Int?]) -> Bool {
        slots.compactMap { $0 } == rankedItemIDs
    }

    static func firstIncorrectPair(_ slots: [Int?]) -> ClosedRange<Int>? {
        for index in 0..<(rankedItemIDs.count - 1) {
            if slots[index] != rankedItemIDs[index]
                || slots[index + 1] != rankedItemIDs[index + 1] {
                return index...(index + 1)
            }
        }
        return nil
    }

    static func incorrectSlotIndices(_ slots: [Int?]) -> Set<Int> {
        Set(rankedItemIDs.indices.filter {
            slots[$0] != rankedItemIDs[$0]
        })
    }

    static func shuffledIDs() -> [Int] {
        rankedItemIDs.shuffled()
    }
}

enum HardModeChallengeGeometry {
    static let phraseTexts = [
        "Scrolling is the enemy.",
        "Discipline beats motivation.",
        "My time is worth more."
    ]

    static let phraseTargetGroups: [[[CGPoint]]] = phraseTexts.map(cursiveTarget(for:))

    static let palmTrunk: [CGPoint] = [
        CGPoint(x: 0.50, y: 0.77),
        CGPoint(x: 0.49, y: 0.65),
        CGPoint(x: 0.51, y: 0.53),
        CGPoint(x: 0.50, y: 0.42)
    ]

    static let palmFronds: [CGPoint] = [
        CGPoint(x: 0.50, y: 0.42),
        CGPoint(x: 0.42, y: 0.37),
        CGPoint(x: 0.31, y: 0.34),
        CGPoint(x: 0.18, y: 0.36),
        CGPoint(x: 0.29, y: 0.28),
        CGPoint(x: 0.40, y: 0.25),
        CGPoint(x: 0.50, y: 0.42),
        CGPoint(x: 0.59, y: 0.31),
        CGPoint(x: 0.68, y: 0.25),
        CGPoint(x: 0.82, y: 0.22),
        CGPoint(x: 0.71, y: 0.33),
        CGPoint(x: 0.60, y: 0.38),
        CGPoint(x: 0.50, y: 0.42),
        CGPoint(x: 0.62, y: 0.48),
        CGPoint(x: 0.76, y: 0.55),
        CGPoint(x: 0.88, y: 0.58),
        CGPoint(x: 0.72, y: 0.61),
        CGPoint(x: 0.59, y: 0.55),
        CGPoint(x: 0.50, y: 0.42)
    ]

    static let palmGround: [CGPoint] = [
        CGPoint(x: 0.28, y: 0.78),
        CGPoint(x: 0.50, y: 0.80),
        CGPoint(x: 0.72, y: 0.78)
    ]

    private static func cursiveTarget(for phrase: String) -> [[CGPoint]] {
        let font = CTFontCreateWithName("SnellRoundhand-Bold" as CFString, 80, nil)
        let attributes = [kCTFontAttributeName: font] as CFDictionary
        let attributed = CFAttributedStringCreate(nil, phrase as CFString, attributes)!
        let line = CTLineCreateWithAttributedString(attributed)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        let path = CGMutablePath()

        for run in runs {
            let runAttributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = (runAttributes[kCTFontAttributeName] as! CTFont)
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = Array(repeating: CGGlyph(), count: count)
            var positions = Array(repeating: CGPoint.zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for index in 0..<count {
                guard let glyphPath = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) else {
                    continue
                }
                path.addPath(
                    glyphPath,
                    transform: CGAffineTransform(
                        translationX: positions[index].x,
                        y: positions[index].y
                    )
                )
            }
        }

        let bounds = path.boundingBoxOfPath
        guard bounds.width > 0, bounds.height > 0 else { return [] }
        let horizontalInset: CGFloat = 0.055
        let verticalInset: CGFloat = 0.22
        let scale = min(
            (1 - horizontalInset * 2) / bounds.width,
            (1 - verticalInset * 2) / bounds.height
        )
        var transform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: -scale,
            tx: 0.5 - bounds.midX * scale,
            ty: 0.5 + bounds.midY * scale
        )
        guard let normalizedPath = path.copy(using: &transform) else { return [] }
        return flatten(path: normalizedPath)
    }

    private static func flatten(path: CGPath, curveSteps: Int = 18) -> [[CGPoint]] {
        var groups: [[CGPoint]] = []
        var points: [CGPoint] = []
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                if points.count > 1 {
                    groups.append(points)
                }
                points = []
                current = element.points[0]
                subpathStart = current
                points.append(current)
            case .addLineToPoint:
                points.append(element.points[0])
                current = element.points[0]
            case .addQuadCurveToPoint:
                let end = element.points[1]
                let control = element.points[0]
                for step in 1...curveSteps {
                    let t = CGFloat(step) / CGFloat(curveSteps)
                    let inverse = 1 - t
                    points.append(CGPoint(
                        x: inverse * inverse * current.x + 2 * inverse * t * control.x + t * t * end.x,
                        y: inverse * inverse * current.y + 2 * inverse * t * control.y + t * t * end.y
                    ))
                }
                current = end
            case .addCurveToPoint:
                let control1 = element.points[0]
                let control2 = element.points[1]
                let end = element.points[2]
                for step in 1...curveSteps {
                    let t = CGFloat(step) / CGFloat(curveSteps)
                    let inverse = 1 - t
                    points.append(CGPoint(
                        x: inverse * inverse * inverse * current.x
                            + 3 * inverse * inverse * t * control1.x
                            + 3 * inverse * t * t * control2.x
                            + t * t * t * end.x,
                        y: inverse * inverse * inverse * current.y
                            + 3 * inverse * inverse * t * control1.y
                            + 3 * inverse * t * t * control2.y
                            + t * t * t * end.y
                    ))
                }
                current = end
            case .closeSubpath:
                points.append(subpathStart)
                current = subpathStart
            @unknown default:
                break
            }
        }
        if points.count > 1 {
            groups.append(points)
        }
        return groups
    }
}
