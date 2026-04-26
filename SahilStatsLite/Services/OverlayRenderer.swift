//
//  OverlayRenderer.swift
//  SahilStatsLite
//
//  PURPOSE: Real-time NBA corner-style scoreboard overlay renderer. Composites
//           team names, scores, period, and clock onto CVPixelBuffer frames
//           during recording. Positioned bottom-right with team color bars.
//  KEY TYPES: OverlayRenderer (@unchecked Sendable)
//  DEPENDS ON: CoreImage, CoreGraphics
//
//  NOTE: Keep this header updated when modifying this file.
//

import CoreImage
import CoreGraphics
import UIKit

/// Atomic snapshot of overlay state. Written from main thread, read from processing queue.
/// Single struct assignment is atomic for value types, eliminating the cross-thread tearing
/// that was possible when 8 individual properties were written separately.
struct OverlayState: Sendable {
    var homeTeam: String = "Home"
    var awayTeam: String = "Away"
    var homeScore: Int = 0
    var awayScore: Int = 0
    var period: String = "1st"
    var clockTime: String = "20:00"
    var isClockRunning: Bool = true
    var eventName: String = ""
}

enum ScoreboardStyle: String, CaseIterable {
    case classic = "Classic"
    case broadcast = "Broadcast"

    var description: String {
        switch self {
        case .classic: return "Corner scorebug (current)"
        case .broadcast: return "NBA-style centered bar"
        }
    }
}

class OverlayRenderer: @unchecked Sendable {

    // MARK: - Overlay State (atomic snapshot)

    nonisolated(unsafe) var state = OverlayState()
    nonisolated(unsafe) var style: ScoreboardStyle = {
        ScoreboardStyle(rawValue: UserDefaults.standard.string(forKey: "scoreboardStyle") ?? "") ?? .classic
    }()

    // Team colors (constant after init, safe to read from any thread)
    let homeColor: UIColor = UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0)  // Orange
    let awayColor: UIColor = UIColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0)  // Blue

    // MARK: - Rendering

    /// Composite overlay onto a video frame
    nonisolated func render(onto pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Lock the pixel buffer for drawing
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        // Create CGContext directly on the pixel buffer
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return pixelBuffer
        }

        // Flip to UIKit coordinates (top-left origin)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        switch style {
        case .classic:
            drawNBAStyleScoreboard(in: context, width: CGFloat(width), height: CGFloat(height))
        case .broadcast:
            drawBroadcastScoreboard(in: context, width: CGFloat(width), height: CGFloat(height))
        }

        return pixelBuffer
    }

    /// Draw NBA-style corner scoreboard
    /// Layout:
    /// ┌─────────────────────────┐
    /// │ [▮] WIL    24 │ H1     │
    /// │ [▮] OPP    18 │ 12:34  │
    /// └─────────────────────────┘
    private nonisolated func drawNBAStyleScoreboard(in context: CGContext, width: CGFloat, height: CGFloat) {
        // Snapshot state once at frame start for consistency
        let s = state
        let isLandscape = width > height
        let referenceWidth: CGFloat = isLandscape ? 1920.0 : 1080.0
        // Increase scale by 1.5x for better visibility on 4K/high-res outputs
        let scale = (width / referenceWidth) * 1.5

        // Scorebug dimensions
        let rowHeight: CGFloat = 44 * scale
        let totalHeight: CGFloat = rowHeight * 2
        let bugWidth: CGFloat = 290 * scale
        let cornerRadius: CGFloat = 10 * scale

        // Position: bottom-right corner with padding (standard broadcast position)
        let padding: CGFloat = 24 * scale
        let bugX = width - padding - bugWidth
        let bugY = height - padding - totalHeight

        // Column widths
        let colorBarWidth: CGFloat = 7 * scale
        let teamWidth: CGFloat = 58 * scale
        let scoreWidth: CGFloat = 54 * scale
        let dividerWidth: CGFloat = 2 * scale
        let timeWidth = bugWidth - colorBarWidth - teamWidth - scoreWidth - dividerWidth  // More room for "1st Half"

        // === DRAW BACKGROUND ===
        let bgRect = CGRect(x: bugX, y: bugY, width: bugWidth, height: totalHeight)
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        // Dark semi-transparent background
        context.saveGState()
        context.addPath(bgPath)
        context.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 0.88))
        context.fillPath()
        context.restoreGState()

        // === HOME TEAM ROW (TOP) ===
        let homeRowY = bugY

        // Home color bar (left edge, top half with rounded corner)
        drawColorBar(in: context, x: bugX, y: homeRowY, width: colorBarWidth, height: rowHeight,
                     color: homeColor.cgColor, roundTop: true, roundBottom: false, cornerRadius: cornerRadius, scale: scale)

        // Home team name (4 chars)
        let homeNameRect = CGRect(x: bugX + colorBarWidth + 10 * scale, y: homeRowY, width: teamWidth, height: rowHeight)
        drawText(String(s.homeTeam.prefix(4)).uppercased(), in: homeNameRect, context: context,
                 fontSize: 16 * scale, color: .white, bold: true, alignment: .left)

        // Home score
        let homeScoreRect = CGRect(x: bugX + colorBarWidth + teamWidth + 4 * scale, y: homeRowY, width: scoreWidth, height: rowHeight)
        drawText("\(s.homeScore)", in: homeScoreRect, context: context,
                 fontSize: 28 * scale, color: .white, bold: true, alignment: .right)

        // Vertical divider
        let dividerX = bugX + colorBarWidth + teamWidth + scoreWidth + 8 * scale
        context.setFillColor(CGColor(red: 0.3, green: 0.3, blue: 0.35, alpha: 1.0))
        context.fill(CGRect(x: dividerX, y: bugY + 6 * scale, width: 1 * scale, height: totalHeight - 12 * scale))

        // Period (top right section)
        let periodRect = CGRect(x: dividerX + 6 * scale, y: homeRowY, width: timeWidth - 12 * scale, height: rowHeight)
        drawText(s.period, in: periodRect, context: context,
                 fontSize: 12 * scale, color: UIColor(white: 0.7, alpha: 1.0), bold: true, alignment: .center)

        // === AWAY TEAM ROW (BOTTOM) ===
        let awayRowY = bugY + rowHeight

        // Away color bar (left edge, bottom half with rounded corner)
        drawColorBar(in: context, x: bugX, y: awayRowY, width: colorBarWidth, height: rowHeight,
                     color: awayColor.cgColor, roundTop: false, roundBottom: true, cornerRadius: cornerRadius, scale: scale)

        // Away team name (4 chars)
        let awayNameRect = CGRect(x: bugX + colorBarWidth + 10 * scale, y: awayRowY, width: teamWidth, height: rowHeight)
        drawText(String(s.awayTeam.prefix(4)).uppercased(), in: awayNameRect, context: context,
                 fontSize: 16 * scale, color: .white, bold: true, alignment: .left)

        // Away score
        let awayScoreRect = CGRect(x: bugX + colorBarWidth + teamWidth + 4 * scale, y: awayRowY, width: scoreWidth, height: rowHeight)
        drawText("\(s.awayScore)", in: awayScoreRect, context: context,
                 fontSize: 28 * scale, color: .white, bold: true, alignment: .right)

        // Clock (bottom right section)
        let clockColor = s.isClockRunning ? UIColor.white : UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)
        let clockRect = CGRect(x: dividerX + 6 * scale, y: awayRowY, width: timeWidth - 12 * scale, height: rowHeight)
        drawText(s.clockTime, in: clockRect, context: context,
                 fontSize: 20 * scale, color: clockColor, bold: true, alignment: .center, monospaced: true)

        // === SUBTLE BORDER ===
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.1))
        context.setLineWidth(1 * scale)
        context.addPath(bgPath)
        context.strokePath()

        // Row separator line
        context.setStrokeColor(CGColor(red: 0.3, green: 0.3, blue: 0.35, alpha: 0.5))
        context.setLineWidth(1 * scale)
        context.move(to: CGPoint(x: bugX + colorBarWidth, y: bugY + rowHeight))
        context.addLine(to: CGPoint(x: bugX + bugWidth - cornerRadius, y: bugY + rowHeight))
        context.strokePath()
    }

    /// NBA broadcast-style centered scoreboard
    /// Layout: ┌────────────────────────────────┐
    ///         │ LAVA  12 │ 1st 14:23 │ 8  JDRJ│
    ///         └────────────────────────────────┘
    private nonisolated func drawBroadcastScoreboard(in context: CGContext, width: CGFloat, height: CGFloat) {
        let s = state
        let isLandscape = width > height
        let referenceWidth: CGFloat = isLandscape ? 1920.0 : 1080.0
        let scale = (width / referenceWidth) * 1.5

        // Bar dimensions
        let barHeight: CGFloat = 48 * scale
        let barWidth: CGFloat = 460 * scale
        let cornerRadius: CGFloat = 6 * scale

        // Position: bottom center with padding
        let barX = (width - barWidth) / 2
        let barY = height - 40 * scale - barHeight

        // Section widths
        let teamSectionWidth: CGFloat = 160 * scale  // each team
        let centerWidth = barWidth - teamSectionWidth * 2  // period + clock

        // === BACKGROUND ===
        let bgRect = CGRect(x: barX, y: barY, width: barWidth, height: barHeight)
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.saveGState()
        context.addPath(bgPath)
        context.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 0.92))
        context.fillPath()
        context.restoreGState()

        // === HOME TEAM (left) ===
        // Color accent bar
        let homeAccentRect = CGRect(x: barX, y: barY, width: 5 * scale, height: barHeight)
        context.saveGState()
        let homeClip = CGMutablePath()
        homeClip.move(to: CGPoint(x: barX, y: barY + cornerRadius))
        homeClip.addArc(center: CGPoint(x: barX + cornerRadius, y: barY + cornerRadius), radius: cornerRadius, startAngle: .pi, endAngle: .pi * 1.5, clockwise: false)
        homeClip.addLine(to: CGPoint(x: barX + 5 * scale, y: barY))
        homeClip.addLine(to: CGPoint(x: barX + 5 * scale, y: barY + barHeight))
        homeClip.addLine(to: CGPoint(x: barX + cornerRadius, y: barY + barHeight))
        homeClip.addArc(center: CGPoint(x: barX + cornerRadius, y: barY + barHeight - cornerRadius), radius: cornerRadius, startAngle: .pi / 2, endAngle: .pi, clockwise: false)
        homeClip.closeSubpath()
        context.addPath(homeClip)
        context.setFillColor(homeColor.cgColor)
        context.fillPath()
        context.restoreGState()

        // Home team name
        let homeNameRect = CGRect(x: barX + 14 * scale, y: barY, width: 80 * scale, height: barHeight)
        drawText(String(s.homeTeam.prefix(4)).uppercased(), in: homeNameRect, context: context,
                 fontSize: 16 * scale, color: .white, bold: true, alignment: .left)

        // Home score
        let homeScoreRect = CGRect(x: barX + 90 * scale, y: barY, width: 60 * scale, height: barHeight)
        drawText("\(s.homeScore)", in: homeScoreRect, context: context,
                 fontSize: 28 * scale, color: .white, bold: true, alignment: .right)

        // === CENTER (period + clock) ===
        let centerX = barX + teamSectionWidth

        // Left divider
        context.setFillColor(CGColor(red: 0.3, green: 0.3, blue: 0.35, alpha: 0.6))
        context.fill(CGRect(x: centerX, y: barY + 8 * scale, width: 1 * scale, height: barHeight - 16 * scale))

        // Period
        let periodRect = CGRect(x: centerX + 8 * scale, y: barY, width: centerWidth / 2 - 12 * scale, height: barHeight)
        drawText(s.period, in: periodRect, context: context,
                 fontSize: 12 * scale, color: UIColor(white: 0.6, alpha: 1.0), bold: true, alignment: .center)

        // Clock
        let clockColor = s.isClockRunning ? UIColor.white : UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)
        let clockRect = CGRect(x: centerX + centerWidth / 2, y: barY, width: centerWidth / 2 - 8 * scale, height: barHeight)
        drawText(s.clockTime, in: clockRect, context: context,
                 fontSize: 20 * scale, color: clockColor, bold: true, alignment: .center, monospaced: true)

        // Right divider
        let rightDivX = barX + teamSectionWidth + centerWidth
        context.setFillColor(CGColor(red: 0.3, green: 0.3, blue: 0.35, alpha: 0.6))
        context.fill(CGRect(x: rightDivX, y: barY + 8 * scale, width: 1 * scale, height: barHeight - 16 * scale))

        // === AWAY TEAM (right) ===
        // Away score
        let awayScoreRect = CGRect(x: rightDivX + 10 * scale, y: barY, width: 60 * scale, height: barHeight)
        drawText("\(s.awayScore)", in: awayScoreRect, context: context,
                 fontSize: 28 * scale, color: .white, bold: true, alignment: .left)

        // Away team name
        let awayNameRect = CGRect(x: rightDivX + 70 * scale, y: barY, width: 80 * scale, height: barHeight)
        drawText(String(s.awayTeam.prefix(4)).uppercased(), in: awayNameRect, context: context,
                 fontSize: 16 * scale, color: .white, bold: true, alignment: .right)

        // Away color accent bar (right edge)
        let awayAccentRect = CGRect(x: barX + barWidth - 5 * scale, y: barY, width: 5 * scale, height: barHeight)
        context.saveGState()
        let awayClip = CGMutablePath()
        awayClip.move(to: CGPoint(x: barX + barWidth - 5 * scale, y: barY))
        awayClip.addLine(to: CGPoint(x: barX + barWidth - cornerRadius, y: barY))
        awayClip.addArc(center: CGPoint(x: barX + barWidth - cornerRadius, y: barY + cornerRadius), radius: cornerRadius, startAngle: -.pi / 2, endAngle: 0, clockwise: false)
        awayClip.addLine(to: CGPoint(x: barX + barWidth, y: barY + barHeight - cornerRadius))
        awayClip.addArc(center: CGPoint(x: barX + barWidth - cornerRadius, y: barY + barHeight - cornerRadius), radius: cornerRadius, startAngle: 0, endAngle: .pi / 2, clockwise: false)
        awayClip.addLine(to: CGPoint(x: barX + barWidth - 5 * scale, y: barY + barHeight))
        awayClip.closeSubpath()
        context.addPath(awayClip)
        context.setFillColor(awayColor.cgColor)
        context.fillPath()
        context.restoreGState()

        // === SUBTLE BORDER ===
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
        context.setLineWidth(1 * scale)
        context.addPath(bgPath)
        context.strokePath()
    }

    /// Draw team color bar with optional rounded corners
    private nonisolated func drawColorBar(in context: CGContext, x: CGFloat, y: CGFloat,
                                           width: CGFloat, height: CGFloat, color: CGColor,
                                           roundTop: Bool, roundBottom: Bool, cornerRadius: CGFloat, scale: CGFloat) {
        context.saveGState()

        let rect = CGRect(x: x, y: y, width: width, height: height)

        if roundTop || roundBottom {
            // Create path with selective rounded corners
            let path = CGMutablePath()
            let r = cornerRadius

            if roundTop && roundBottom {
                // Both corners rounded (shouldn't happen in our case)
                path.addRoundedRect(in: rect, cornerWidth: r, cornerHeight: r)
            } else if roundTop {
                // Only top-left corner rounded
                path.move(to: CGPoint(x: x, y: y + height))
                path.addLine(to: CGPoint(x: x, y: y + r))
                path.addArc(center: CGPoint(x: x + r, y: y + r), radius: r, startAngle: .pi, endAngle: .pi * 1.5, clockwise: false)
                path.addLine(to: CGPoint(x: x + width, y: y))
                path.addLine(to: CGPoint(x: x + width, y: y + height))
                path.closeSubpath()
            } else {
                // Only bottom-left corner rounded
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + width, y: y))
                path.addLine(to: CGPoint(x: x + width, y: y + height))
                path.addLine(to: CGPoint(x: x + r, y: y + height))
                path.addArc(center: CGPoint(x: x + r, y: y + height - r), radius: r, startAngle: .pi / 2, endAngle: .pi, clockwise: false)
                path.closeSubpath()
            }

            context.addPath(path)
            context.setFillColor(color)
            context.fillPath()
        } else {
            context.setFillColor(color)
            context.fill(rect)
        }

        context.restoreGState()
    }

    /// Draw text with alignment options
    private nonisolated func drawText(_ text: String, in rect: CGRect, context: CGContext,
                                       fontSize: CGFloat, color: UIColor, bold: Bool,
                                       alignment: NSTextAlignment, monospaced: Bool = false) {

        let font: UIFont
        if monospaced {
            font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: bold ? .bold : .medium)
        } else if bold {
            font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        } else {
            font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()

        // Calculate position based on alignment
        var textX: CGFloat
        switch alignment {
        case .left:
            textX = rect.minX
        case .right:
            textX = rect.maxX - textSize.width
        default:
            textX = rect.minX + (rect.width - textSize.width) / 2
        }
        let textY = rect.minY + (rect.height - textSize.height) / 2

        UIGraphicsPushContext(context)
        attributedString.draw(at: CGPoint(x: textX, y: textY))
        UIGraphicsPopContext()
    }
}
