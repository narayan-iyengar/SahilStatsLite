//
//  OverlayRenderer.swift
//  SahilStatsLite
//
//  Real-time scoreboard overlay renderer
//  Draws ScoreCam-style bottom bar on each video frame
//

import CoreImage
import CoreGraphics
import UIKit

class OverlayRenderer {

    // MARK: - Overlay State (updated from UI)

    var homeTeam: String = "Home"
    var awayTeam: String = "Away"
    var homeScore: Int = 0
    var awayScore: Int = 0
    var period: String = "1st"
    var clockTime: String = "20:00"
    var eventName: String = ""

    // MARK: - Rendering

    /// Composite overlay onto a video frame
    func render(onto pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
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

        // Flip to UIKit coordinates (top-left origin) for easier drawing
        // CGContext default is bottom-left origin
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        // Now we're in UIKit coordinates - draw the scoreboard at the bottom
        drawScoreboard(in: context, width: CGFloat(width), height: CGFloat(height))

        return pixelBuffer
    }

    /// Draw the ScoreCam-style bottom bar scoreboard
    /// Called with context already in UIKit coordinates (origin top-left)
    private func drawScoreboard(in context: CGContext, width: CGFloat, height: CGFloat) {
        // Determine if landscape or portrait based on dimensions
        let isLandscape = width > height

        // Scale based on video width for consistent sizing
        let referenceWidth: CGFloat = isLandscape ? 1920.0 : 1080.0
        let scale = width / referenceWidth

        // Bar dimensions - position at BOTTOM of screen in UIKit coordinates
        let barHeight: CGFloat = 60 * scale
        let barPadding: CGFloat = 30 * scale
        let barWidth = width - (barPadding * 2)
        let barX = barPadding
        let barY = height - barPadding - barHeight  // Bottom of screen in UIKit coords

        // Colors
        let darkBg = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.9)
        let scoreBg = CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 0.95)

        // Draw main bar background with rounded corners
        let barRect = CGRect(x: barX, y: barY, width: barWidth, height: barHeight)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: 8 * scale, cornerHeight: 8 * scale, transform: nil)
        context.setFillColor(darkBg)
        context.addPath(barPath)
        context.fillPath()

        // Calculate section widths
        let totalSections: CGFloat = 7
        let sectionWidth = barWidth / totalSections
        var currentX = barX

        // === HOME TEAM NAME ===
        let homeTeamRect = CGRect(x: currentX, y: barY, width: sectionWidth * 2, height: barHeight)
        drawText(homeTeam.uppercased(), in: homeTeamRect, context: context,
                 fontSize: 20 * scale, color: .white, bold: true)
        currentX += sectionWidth * 2

        // === HOME SCORE BOX ===
        let homeScoreRect = CGRect(x: currentX + 4 * scale, y: barY + 4 * scale,
                                    width: sectionWidth - 8 * scale, height: barHeight - 8 * scale)
        let homeScorePath = CGPath(roundedRect: homeScoreRect, cornerWidth: 4 * scale, cornerHeight: 4 * scale, transform: nil)
        context.setFillColor(scoreBg)
        context.addPath(homeScorePath)
        context.fillPath()
        drawText("\(homeScore)", in: CGRect(x: currentX, y: barY, width: sectionWidth, height: barHeight),
                 context: context, fontSize: 28 * scale, color: .white, bold: true)
        currentX += sectionWidth

        // === CENTER (Period + Clock) ===
        // Period at top of center section
        let periodRect = CGRect(x: currentX, y: barY + barHeight * 0.1, width: sectionWidth, height: barHeight * 0.4)
        drawText(period, in: periodRect, context: context, fontSize: 14 * scale, color: .orange, bold: true)

        // Clock at bottom of center section
        let clockRect = CGRect(x: currentX, y: barY + barHeight * 0.45, width: sectionWidth, height: barHeight * 0.45)
        drawText(clockTime, in: clockRect, context: context, fontSize: 18 * scale, color: .white, bold: false, monospaced: true)
        currentX += sectionWidth

        // === AWAY SCORE BOX ===
        let awayScoreRect = CGRect(x: currentX + 4 * scale, y: barY + 4 * scale,
                                    width: sectionWidth - 8 * scale, height: barHeight - 8 * scale)
        let awayScorePath = CGPath(roundedRect: awayScoreRect, cornerWidth: 4 * scale, cornerHeight: 4 * scale, transform: nil)
        context.setFillColor(scoreBg)
        context.addPath(awayScorePath)
        context.fillPath()
        drawText("\(awayScore)", in: CGRect(x: currentX, y: barY, width: sectionWidth, height: barHeight),
                 context: context, fontSize: 28 * scale, color: .white, bold: true)
        currentX += sectionWidth

        // === AWAY TEAM NAME ===
        let awayTeamRect = CGRect(x: currentX, y: barY, width: sectionWidth * 2, height: barHeight)
        drawText(awayTeam.uppercased(), in: awayTeamRect, context: context,
                 fontSize: 20 * scale, color: .white, bold: true)
    }

    /// Draw text centered in the given rect
    /// Context is already in UIKit coordinates
    private func drawText(_ text: String, in rect: CGRect, context: CGContext,
                          fontSize: CGFloat, color: UIColor, bold: Bool, monospaced: Bool = false) {

        let font: UIFont
        if monospaced {
            font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: bold ? .bold : .medium)
        } else {
            font = bold ? UIFont.boldSystemFont(ofSize: fontSize) : UIFont.systemFont(ofSize: fontSize)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()

        // Center text in rect
        let textX = rect.minX + (rect.width - textSize.width) / 2
        let textY = rect.minY + (rect.height - textSize.height) / 2

        // Draw text using UIKit - context is already in UIKit coordinates
        UIGraphicsPushContext(context)
        attributedString.draw(at: CGPoint(x: textX, y: textY))
        UIGraphicsPopContext()
    }
}
