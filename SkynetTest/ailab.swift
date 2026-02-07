#!/usr/bin/env swift
//
//  ailab.swift
//
//  PURPOSE: AI Lab command-line tool for R&D. Runs person detection, stripe
//           detection (refs), kid/adult classification, heat map generation,
//           and zoom-in-post on recorded game videos. Two modes: tracking
//           overlay (debug viz) and zoom (cropped output following action).
//  KEY TYPES: Standalone script (no app integration)
//  DEPENDS ON: AVFoundation, Vision, CoreImage, AppKit (standalone)
//
//  Usage: swift ailab.swift <video_path> [start_seconds] [duration] [--zoom] [--smooth]
//
//  NOTE: Keep this header updated when modifying this file.
//

// AILab Command Line Tool
// Run: swift ailab.swift /path/to/video.mp4 [startSeconds] [duration]

import Foundation
import Vision
import AVFoundation
import CoreImage
import AppKit

// MARK: - Configuration

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("Usage: swift ailab.swift <video_path> [start_seconds] [duration_seconds] [options]")
    print("")
    print("Options:")
    print("  --zoom     Outputs cropped video following the action center")
    print("  --smooth   Higher frame rate (15 FPS) for smooth final output")
    print("")
    print("Examples:")
    print("  swift ailab.swift ~/Desktop/game.mp4 680 30                  # Fast preview")
    print("  swift ailab.swift ~/Desktop/game.mp4 680 30 --zoom           # Zoom-in-post mode")
    print("  swift ailab.swift ~/Desktop/game.mp4 680 30 --zoom --smooth  # Smooth final output")
    exit(1)
}

let videoPath = args[1]
let startTime = args.count > 2 ? Double(args[2]) ?? 0 : 0
let clipDuration = args.count > 3 ? Double(args[3]) ?? 30 : 30

// Check for mode flags
let zoomMode = args.contains("--zoom")
let smoothMode = args.contains("--smooth")  // Higher frame rate for final output
let zoomFactor: CGFloat = 2.0  // 4K -> 1080p crop = 2x zoom headroom
let frameRate: Double = smoothMode ? 15.0 : 2.0  // 15 FPS for smooth, 2 FPS for testing

print("=== AILab Video Processor ===")
print("Video: \(videoPath)")
print("Start: \(Int(startTime))s, Duration: \(Int(clipDuration))s")
if zoomMode {
    print("Mode: ZOOM-IN-POST (follows action center)")
} else {
    print("Mode: TRACKING OVERLAY (shows classifications)")
}
if smoothMode {
    print("Frame rate: 15 FPS (smooth output, slower processing)")
} else {
    print("Frame rate: 2 FPS (fast preview)")
}
print("")

// MARK: - Tracking Region

struct TrackingRegion {
    let minX: CGFloat
    let maxX: CGFloat
    let minY: CGFloat
    let maxY: CGFloat

    var width: CGFloat { maxX - minX }
    var height: CGFloat { maxY - minY }
}

// MARK: - Frame Extraction (synchronous)

func extractFrames(from url: URL, every seconds: Double, maxFrames: Int) -> [CGImage] {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

    var frames: [CGImage] = []
    let totalSeconds = CMTimeGetSeconds(asset.duration)
    var currentTime: Double = 0

    while currentTime < totalSeconds && frames.count < maxFrames {
        let time = CMTime(seconds: currentTime, preferredTimescale: 600)
        do {
            let image = try generator.copyCGImage(at: time, actualTime: nil)
            frames.append(image)
        } catch {
            // Skip frame
        }
        currentTime += seconds
    }

    return frames
}

// MARK: - Hoop Detection

struct HoopLocation {
    let x: CGFloat  // Normalized 0-1, horizontal position
    let y: CGFloat  // Normalized 0-1, vertical position
    let confidence: Float
}

/// Detect basketball hoops by finding orange rims
func detectHoops(in image: CGImage) -> [HoopLocation] {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)

    // Convert to CIImage for color analysis
    let ciImage = CIImage(cgImage: image)

    var hoops: [HoopLocation] = []

    // Method 1: Look for rectangles in upper portion (backboards)
    let rectRequest = VNDetectRectanglesRequest()
    rectRequest.minimumConfidence = 0.3
    rectRequest.minimumSize = 0.02  // Small rectangles
    rectRequest.maximumObservations = 10

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([rectRequest])

    // Filter for rectangles in upper 60% of frame (where hoops would be)
    for rect in rectRequest.results ?? [] {
        let bounds = rect.boundingBox
        // Hoops are typically in upper portion and have specific aspect ratio
        if bounds.midY > 0.4 && bounds.width > bounds.height * 0.5 {
            // Check if this might be a backboard (wider than tall, upper frame)
            hoops.append(HoopLocation(
                x: bounds.midX,
                y: bounds.midY,
                confidence: rect.confidence
            ))
        }
    }

    // Method 2: Sample for orange pixels (rim color)
    // Create a bitmap context to read pixels
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerPixel = 4
    let bytesPerRow = bytesPerPixel * image.width
    let bitsPerComponent = 8
    var pixelData = [UInt8](repeating: 0, count: image.height * bytesPerRow)

    guard let context = CGContext(
        data: &pixelData,
        width: image.width,
        height: image.height,
        bitsPerComponent: bitsPerComponent,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return hoops
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

    // Scan upper portion for orange clusters (basketball rim color)
    // Orange RGB roughly: R > 180, G: 60-140, B < 80
    var orangeRegions: [(x: Int, y: Int)] = []

    let scanStartY = Int(Double(image.height) * 0.3)  // Upper 70%
    let scanEndY = Int(Double(image.height) * 0.8)
    let step = 10  // Sample every 10 pixels for speed

    for y in stride(from: scanStartY, to: scanEndY, by: step) {
        for x in stride(from: 0, to: image.width, by: step) {
            let offset = (y * image.width + x) * bytesPerPixel
            let r = pixelData[offset]
            let g = pixelData[offset + 1]
            let b = pixelData[offset + 2]

            // Check for orange (rim color)
            if r > 170 && g > 50 && g < 150 && b < 100 && r > g && r > b {
                orangeRegions.append((x: x, y: y))
            }
        }
    }

    // Cluster orange pixels to find rim locations
    if orangeRegions.count > 5 {
        // Find leftmost and rightmost orange clusters
        let sortedByX = orangeRegions.sorted { $0.x < $1.x }

        // Left cluster (first 20% of orange pixels)
        let leftCluster = sortedByX.prefix(max(1, orangeRegions.count / 5))
        if let leftAvg = leftCluster.first {
            let avgX = CGFloat(leftCluster.map { $0.x }.reduce(0, +)) / CGFloat(leftCluster.count)
            let avgY = CGFloat(leftCluster.map { $0.y }.reduce(0, +)) / CGFloat(leftCluster.count)
            hoops.append(HoopLocation(
                x: avgX / width,
                y: 1.0 - (avgY / height),  // Flip Y
                confidence: 0.7
            ))
        }

        // Right cluster (last 20% of orange pixels)
        let rightCluster = sortedByX.suffix(max(1, orangeRegions.count / 5))
        if let rightAvg = rightCluster.first {
            let avgX = CGFloat(rightCluster.map { $0.x }.reduce(0, +)) / CGFloat(rightCluster.count)
            let avgY = CGFloat(rightCluster.map { $0.y }.reduce(0, +)) / CGFloat(rightCluster.count)
            hoops.append(HoopLocation(
                x: avgX / width,
                y: 1.0 - (avgY / height),  // Flip Y
                confidence: 0.7
            ))
        }
    }

    return hoops
}

/// Find court boundaries based on hoop positions
func findCourtBounds(from frames: [CGImage]) -> (leftX: CGFloat, rightX: CGFloat)? {
    var allHoops: [HoopLocation] = []

    print("  Scanning for hoops...")
    for (i, frame) in frames.prefix(10).enumerated() {
        let hoops = detectHoops(in: frame)
        allHoops.append(contentsOf: hoops)
        if (i + 1) % 3 == 0 {
            print("    Scanned \(i + 1) frames, found \(allHoops.count) potential hoops")
        }
    }

    guard allHoops.count >= 2 else {
        print("  Could not find enough hoops")
        return nil
    }

    // Sort by X position
    let sortedByX = allHoops.sorted { $0.x < $1.x }

    // Left hoop = leftmost detections averaged
    let leftHoops = sortedByX.prefix(allHoops.count / 3)
    let leftX = leftHoops.map { $0.x }.reduce(0, +) / CGFloat(leftHoops.count)

    // Right hoop = rightmost detections averaged
    let rightHoops = sortedByX.suffix(allHoops.count / 3)
    let rightX = rightHoops.map { $0.x }.reduce(0, +) / CGFloat(rightHoops.count)

    print("  Hoops found: Left=\(String(format: "%.2f", leftX)), Right=\(String(format: "%.2f", rightX))")

    // Sanity check: hoops should be reasonably apart
    if rightX - leftX < 0.3 {
        print("  Warning: Hoops too close together, might be false detection")
        return nil
    }

    return (leftX: leftX, rightX: rightX)
}

// MARK: - Heat Map

func buildHeatMap(frames: [CGImage], gridSize: Int = 20) -> [[Int]] {
    var heatMap = Array(repeating: Array(repeating: 0, count: gridSize), count: gridSize)

    for frame in frames {
        let request = VNDetectHumanRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: frame, options: [:])
        try? handler.perform([request])

        for human in request.results ?? [] {
            let box = human.boundingBox
            let startX = max(0, Int(box.minX * Double(gridSize)))
            let endX = min(gridSize - 1, Int(box.maxX * Double(gridSize)))
            let startY = max(0, Int(box.minY * Double(gridSize)))
            let endY = min(gridSize - 1, Int(box.maxY * Double(gridSize)))

            for y in startY...endY {
                for x in startX...endX {
                    heatMap[y][x] += 1
                }
            }
        }
    }

    return heatMap
}

func calculateTrackingRegion(from heatMap: [[Int]], threshold: Double = 0.40) -> TrackingRegion {
    let gridSize = heatMap.count
    guard gridSize > 0 else {
        return TrackingRegion(minX: 0.1, maxX: 0.9, minY: 0.1, maxY: 0.9)
    }

    let maxVal = heatMap.flatMap { $0 }.max() ?? 1
    let cutoff = Int(Double(maxVal) * threshold)

    let minYSearch = Int(Double(gridSize) * 0.05)
    let maxYSearch = Int(Double(gridSize) * 0.70)

    var minX = gridSize, maxX = 0
    var minY = gridSize, maxY = 0

    for y in minYSearch..<maxYSearch {
        for x in 0..<gridSize {
            if heatMap[y][x] > cutoff {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
    }

    if minX >= gridSize {
        return TrackingRegion(minX: 0.15, maxX: 0.85, minY: 0.25, maxY: 0.70)
    }

    let hPad = 0.03
    let vPad = 0.08

    return TrackingRegion(
        minX: max(0, CGFloat(minX) / CGFloat(gridSize) - hPad),
        maxX: min(1, CGFloat(maxX + 1) / CGFloat(gridSize) + hPad),
        minY: max(0, CGFloat(minY) / CGFloat(gridSize) - vPad),
        maxY: min(1, CGFloat(maxY + 1) / CGFloat(gridSize) + vPad)
    )
}

// MARK: - Human Detection

struct DetectedPerson {
    let box: CGRect
    let isLikelyKid: Bool      // Based on size
    let isLikelyRef: Bool      // Based on striped jersey
    let isLikelyOnCourt: Bool  // Based on position in tracking region
}

func detectHumans(in image: CGImage) -> [VNHumanObservation] {
    let request = VNDetectHumanRectanglesRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([request])
    return request.results ?? []
}

/// Check if a region has striped pattern (ref jersey)
func hasStripedJersey(in image: CGImage, box: CGRect) -> Bool {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)

    // Get upper body region (torso where jersey is)
    let torsoRect = CGRect(
        x: box.minX * width,
        y: (1 - box.maxY) * height + box.height * height * 0.3,  // Upper 40% of person (flip Y)
        width: box.width * width,
        height: box.height * height * 0.4
    )

    // Clamp to image bounds
    let sampleX = max(0, min(Int(torsoRect.midX), image.width - 1))
    let sampleStartY = max(0, Int(torsoRect.minY))
    let sampleEndY = min(image.height - 1, Int(torsoRect.maxY))

    guard sampleEndY > sampleStartY + 10 else { return false }

    // Create bitmap to read pixels
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerPixel = 4
    let bytesPerRow = bytesPerPixel * image.width
    var pixelData = [UInt8](repeating: 0, count: image.height * bytesPerRow)

    guard let context = CGContext(
        data: &pixelData,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return false }

    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

    // Sample vertical line down the torso center, looking for alternating light/dark
    var transitions = 0
    var lastWasLight: Bool? = nil

    for y in stride(from: sampleStartY, to: sampleEndY, by: 3) {
        let offset = (y * image.width + sampleX) * bytesPerPixel
        let r = Int(pixelData[offset])
        let g = Int(pixelData[offset + 1])
        let b = Int(pixelData[offset + 2])

        // Calculate brightness
        let brightness = (r + g + b) / 3
        let isLight = brightness > 140

        // Check for black/white specifically (low saturation)
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let saturation = maxC > 0 ? (maxC - minC) * 100 / maxC : 0
        let isBlackOrWhite = saturation < 25  // Low saturation = grayscale

        if isBlackOrWhite {
            if let last = lastWasLight, last != isLight {
                transitions += 1
            }
            lastWasLight = isLight
        }
    }

    // Refs typically have 3+ stripe transitions in their jersey
    return transitions >= 3
}

/// Detect humans and classify based on stripes (ref) and size (kid/adult)
func detectAndClassifyHumans(in image: CGImage, region: TrackingRegion) -> [DetectedPerson] {
    let request = VNDetectHumanRectanglesRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([request])

    let humans = request.results ?? []

    // Calculate median height to determine kid vs adult threshold
    let heights = humans.map { $0.boundingBox.height }
    let sortedHeights = heights.sorted()
    let medianHeight = sortedHeights.isEmpty ? 0.2 : sortedHeights[sortedHeights.count / 2]

    // Adults are typically 25%+ taller than median (kids)
    let adultThreshold = medianHeight * 1.25

    return humans.map { human in
        let box = human.boundingBox

        // Check for striped jersey (ref)
        let isRef = hasStripedJersey(in: image, box: box)

        // Size-based kid/adult (only matters if not a ref)
        let isLikelyKid = box.height < adultThreshold

        // Check if within tracking region (heat map based court bounds)
        let isOnCourt = box.midX >= region.minX && box.midX <= region.maxX &&
                        box.midY >= region.minY && box.midY <= region.maxY

        return DetectedPerson(
            box: box,
            isLikelyKid: isLikelyKid,
            isLikelyRef: isRef,
            isLikelyOnCourt: isOnCourt
        )
    }
}

// MARK: - Drawing

func drawOverlay(on image: CGImage, region: TrackingRegion, humans: [VNHumanObservation]) -> NSImage {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)

    let nsImage = NSImage(cgImage: image, size: NSSize(width: width, height: height))
    nsImage.lockFocus()

    // Draw tracking region
    NSColor.green.withAlphaComponent(0.8).setStroke()
    let regionRect = CGRect(
        x: region.minX * width,
        y: region.minY * height,
        width: region.width * width,
        height: region.height * height
    )
    let regionPath = NSBezierPath(rect: regionRect)
    regionPath.lineWidth = 4.0
    regionPath.stroke()

    // Draw ignore zones (red tint)
    NSColor.red.withAlphaComponent(0.2).setFill()
    if region.minX > 0.02 {
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: region.minX * width, height: height)).fill()
    }
    if region.maxX < 0.98 {
        NSBezierPath(rect: CGRect(x: region.maxX * width, y: 0, width: (1 - region.maxX) * width, height: height)).fill()
    }

    // Draw human boxes
    for human in humans {
        let box = human.boundingBox
        let rect = CGRect(
            x: box.minX * width,
            y: box.minY * height,
            width: box.width * width,
            height: box.height * height
        )

        let isInRegion = box.midX >= region.minX && box.midX <= region.maxX &&
                         box.midY >= region.minY && box.midY <= region.maxY

        let color: NSColor = isInRegion ? .cyan : .orange
        color.setStroke()

        let boxPath = NSBezierPath(rect: rect)
        boxPath.lineWidth = 4.0
        boxPath.stroke()

        // Label
        let label = isInRegion ? "TRACK" : "IGNORE"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.boldSystemFont(ofSize: 16),
            .backgroundColor: NSColor.black.withAlphaComponent(0.6)
        ]
        label.draw(at: CGPoint(x: rect.minX + 2, y: rect.maxY + 2), withAttributes: attrs)
    }

    nsImage.unlockFocus()
    return nsImage
}

/// Draw with heat map region and stripe-based ref detection
func drawOverlayWithClassification(on image: CGImage, region: TrackingRegion, people: [DetectedPerson]) -> NSImage {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)

    let nsImage = NSImage(cgImage: image, size: NSSize(width: width, height: height))
    nsImage.lockFocus()

    // Draw tracking region (heat map based)
    NSColor.green.withAlphaComponent(0.8).setStroke()
    let regionRect = CGRect(
        x: region.minX * width,
        y: region.minY * height,
        width: region.width * width,
        height: region.height * height
    )
    let regionPath = NSBezierPath(rect: regionRect)
    regionPath.lineWidth = 3.0
    regionPath.stroke()

    // Shade outside areas (ignore zones)
    NSColor.red.withAlphaComponent(0.12).setFill()
    // Left
    if region.minX > 0.02 {
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: region.minX * width, height: height)).fill()
    }
    // Right
    if region.maxX < 0.98 {
        NSBezierPath(rect: CGRect(x: region.maxX * width, y: 0, width: (1 - region.maxX) * width, height: height)).fill()
    }

    // Draw people with classification
    for person in people {
        let box = person.box
        let rect = CGRect(
            x: box.minX * width,
            y: box.minY * height,
            width: box.width * width,
            height: box.height * height
        )

        // Color coding:
        // - Yellow: REF (striped jersey)
        // - Cyan: PLAYER (kid on court)
        // - Orange: BENCH (kid off court)
        // - Red: COACH (adult off court)
        let color: NSColor
        let label: String

        if person.isLikelyRef {
            color = .yellow
            label = "REF"
        } else if person.isLikelyOnCourt {
            if person.isLikelyKid {
                color = .cyan
                label = "PLAYER"
            } else {
                color = .magenta
                label = "ADULT?"
            }
        } else {
            if person.isLikelyKid {
                color = .orange
                label = "BENCH"
            } else {
                color = .red
                label = "COACH"
            }
        }

        color.setStroke()
        let boxPath = NSBezierPath(rect: rect)
        boxPath.lineWidth = 4.0
        boxPath.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.boldSystemFont(ofSize: 14),
            .backgroundColor: NSColor.black.withAlphaComponent(0.6)
        ]
        label.draw(at: CGPoint(x: rect.minX + 2, y: rect.maxY + 2), withAttributes: attrs)
    }

    nsImage.unlockFocus()
    return nsImage
}

// MARK: - Action Center Calculation

struct ActionCenter {
    let x: CGFloat  // Normalized 0-1
    let y: CGFloat  // Normalized 0-1
}

/// Calculate weighted center of action from detected players
/// Bigger bounding box = closer to camera = more weight
func calculateActionCenter(from people: [DetectedPerson], fallback: ActionCenter = ActionCenter(x: 0.5, y: 0.5)) -> ActionCenter {
    // Only consider players and refs on court (not sideline)
    let trackable = people.filter { $0.isLikelyOnCourt || $0.isLikelyRef }

    guard !trackable.isEmpty else { return fallback }

    var totalWeight: CGFloat = 0
    var weightedX: CGFloat = 0
    var weightedY: CGFloat = 0

    for person in trackable {
        // Weight by area (bigger = closer = more important)
        let weight = person.box.width * person.box.height * 100
        weightedX += person.box.midX * weight
        weightedY += person.box.midY * weight
        totalWeight += weight
    }

    guard totalWeight > 0 else { return fallback }

    return ActionCenter(
        x: weightedX / totalWeight,
        y: weightedY / totalWeight
    )
}

/// Smooth transition between action centers (ease toward target)
func smoothActionCenter(current: ActionCenter, target: ActionCenter, smoothing: CGFloat = 0.15) -> ActionCenter {
    return ActionCenter(
        x: current.x + (target.x - current.x) * smoothing,
        y: current.y + (target.y - current.y) * smoothing
    )
}

/// Crop frame around action center for zoom-in-post effect
func cropAroundActionCenter(image: CGImage, center: ActionCenter, zoomFactor: CGFloat) -> CGImage? {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)

    // Calculate crop size (smaller = more zoom)
    let cropWidth = width / zoomFactor
    let cropHeight = height / zoomFactor

    // Calculate crop origin, keeping center point centered
    var cropX = (center.x * width) - (cropWidth / 2)
    var cropY = ((1 - center.y) * height) - (cropHeight / 2)  // Flip Y for CGImage coords

    // Clamp to image bounds
    cropX = max(0, min(cropX, width - cropWidth))
    cropY = max(0, min(cropY, height - cropHeight))

    let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)

    return image.cropping(to: cropRect)
}

/// Draw zoom indicator showing where we're looking
func drawZoomOverlay(on image: CGImage, center: ActionCenter, zoomFactor: CGFloat) -> NSImage {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)

    let nsImage = NSImage(cgImage: image, size: NSSize(width: width, height: height))
    nsImage.lockFocus()

    // Draw crop rectangle (what will be in final zoomed video)
    let cropWidth = width / zoomFactor
    let cropHeight = height / zoomFactor
    let cropX = (center.x * width) - (cropWidth / 2)
    let cropY = (center.y * height) - (cropHeight / 2)

    // Clamp
    let clampedX = max(0, min(cropX, width - cropWidth))
    let clampedY = max(0, min(cropY, height - cropHeight))

    let cropRect = CGRect(x: clampedX, y: clampedY, width: cropWidth, height: cropHeight)

    // Dim outside crop area
    NSColor.black.withAlphaComponent(0.5).setFill()
    // Top
    NSBezierPath(rect: CGRect(x: 0, y: cropRect.maxY, width: width, height: height - cropRect.maxY)).fill()
    // Bottom
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: cropRect.minY)).fill()
    // Left
    NSBezierPath(rect: CGRect(x: 0, y: cropRect.minY, width: cropRect.minX, height: cropRect.height)).fill()
    // Right
    NSBezierPath(rect: CGRect(x: cropRect.maxX, y: cropRect.minY, width: width - cropRect.maxX, height: cropRect.height)).fill()

    // Draw crop border
    NSColor.yellow.withAlphaComponent(0.9).setStroke()
    let borderPath = NSBezierPath(rect: cropRect)
    borderPath.lineWidth = 4.0
    borderPath.stroke()

    // Draw center crosshair
    NSColor.yellow.setStroke()
    let crossSize: CGFloat = 20
    let centerX = center.x * width
    let centerY = center.y * height

    let hLine = NSBezierPath()
    hLine.move(to: CGPoint(x: centerX - crossSize, y: centerY))
    hLine.line(to: CGPoint(x: centerX + crossSize, y: centerY))
    hLine.lineWidth = 2.0
    hLine.stroke()

    let vLine = NSBezierPath()
    vLine.move(to: CGPoint(x: centerX, y: centerY - crossSize))
    vLine.line(to: CGPoint(x: centerX, y: centerY + crossSize))
    vLine.lineWidth = 2.0
    vLine.stroke()

    // Label
    let attrs: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.yellow,
        .font: NSFont.boldSystemFont(ofSize: 16),
        .backgroundColor: NSColor.black.withAlphaComponent(0.7)
    ]
    "ZOOM PREVIEW".draw(at: CGPoint(x: cropRect.minX + 5, y: cropRect.maxY - 25), withAttributes: attrs)

    nsImage.unlockFocus()
    return nsImage
}

// MARK: - Pixel Buffer

func pixelBuffer(from image: NSImage, size: CGSize) -> CVPixelBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let attrs: [String: Any] = [
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ]

    CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                        kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pixelBuffer)

    guard let buffer = pixelBuffer else { return nil }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

    let context = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer),
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
    )

    if let ctx = context, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))
    }

    return buffer
}

// MARK: - Main Processing

func processVideo() {
    let inputURL = URL(fileURLWithPath: videoPath)
    let outputFilename = zoomMode ? "AILab_Zoomed.mp4" : "AILab_Tracked.mp4"
    let outputURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop/\(outputFilename)")

    try? FileManager.default.removeItem(at: outputURL)

    let asset = AVURLAsset(url: inputURL)

    // Use synchronous properties
    let totalSeconds = CMTimeGetSeconds(asset.duration)

    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
        print("ERROR: No video track found")
        return
    }

    let naturalSize = videoTrack.naturalSize

    print("Video: \(Int(naturalSize.width))x\(Int(naturalSize.height)), \(String(format: "%.1f", totalSeconds))s total")

    // Extract sample frames
    print("\nExtracting sample frames...")
    let sampleFrames = extractFrames(from: inputURL, every: 10.0, maxFrames: 20)
    print("  Sampled \(sampleFrames.count) frames")

    // Build heat map from player positions (primary method)
    print("\nBuilding heat map from player positions...")
    let heatMap = buildHeatMap(frames: sampleFrames)
    let region = calculateTrackingRegion(from: heatMap)
    print("  Tracking region: X[\(String(format: "%.2f", region.minX))-\(String(format: "%.2f", region.maxX))], Y[\(String(format: "%.2f", region.minY))-\(String(format: "%.2f", region.maxY))]")
    print("  (Players cluster here = court bounds)")

    // Determine output size based on mode
    let outputSize: CGSize
    if zoomMode {
        // Zoomed output is smaller (cropped from original)
        outputSize = CGSize(
            width: naturalSize.width / zoomFactor,
            height: naturalSize.height / zoomFactor
        )
        print("\nZoom mode: \(Int(naturalSize.width))x\(Int(naturalSize.height)) → \(Int(outputSize.width))x\(Int(outputSize.height))")
    } else {
        outputSize = naturalSize
    }

    // Setup writer
    guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
        print("ERROR: Could not create writer")
        return
    }

    let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(outputSize.width),
        AVVideoHeightKey: Int(outputSize.height)
    ]

    let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: writerInput,
        sourcePixelBufferAttributes: nil
    )

    writer.add(writerInput)
    writer.startWriting()
    writer.startSession(atSourceTime: CMTime(seconds: startTime, preferredTimescale: 600))

    // Process frames
    print("\nProcessing frames...")
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

    let frameInterval = 1.0 / frameRate  // 2 FPS (testing) or 15 FPS (smooth)
    var currentTime = startTime
    let processUntil = min(totalSeconds, startTime + clipDuration)
    var frameCount = 0

    // Track action center for smooth camera movement
    var currentActionCenter = ActionCenter(x: 0.5, y: 0.5)

    while currentTime < processUntil {
        let time = CMTime(seconds: currentTime, preferredTimescale: 600)

        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)

            // Classify people using stripe detection (refs) and size (kids vs adults)
            let people = detectAndClassifyHumans(in: cgImage, region: region)

            // Calculate and smooth action center
            let targetCenter = calculateActionCenter(from: people, fallback: currentActionCenter)
            currentActionCenter = smoothActionCenter(current: currentActionCenter, target: targetCenter, smoothing: 0.2)

            // Generate output frame based on mode
            let outputImage: NSImage
            if zoomMode {
                // Crop around action center
                if let cropped = cropAroundActionCenter(image: cgImage, center: currentActionCenter, zoomFactor: zoomFactor) {
                    outputImage = NSImage(cgImage: cropped, size: outputSize)
                } else {
                    outputImage = NSImage(cgImage: cgImage, size: naturalSize)
                }
            } else {
                // Show tracking overlay with zoom preview
                outputImage = drawOverlayWithClassification(on: cgImage, region: region, people: people)
            }

            if let buffer = pixelBuffer(from: outputImage, size: outputSize) {
                while !writerInput.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                adaptor.append(buffer, withPresentationTime: time)
            }

            frameCount += 1
            let progress = Int(((currentTime - startTime) / clipDuration) * 100)

            // Show stats about detected people
            let players = people.filter { $0.isLikelyKid && $0.isLikelyOnCourt && !$0.isLikelyRef }.count
            let refs = people.filter { $0.isLikelyRef }.count

            if zoomMode {
                print("  \(progress)% - Center:(\(String(format: "%.2f", currentActionCenter.x)),\(String(format: "%.2f", currentActionCenter.y))) Players:\(players) Refs:\(refs)    ", terminator: "\r")
            } else {
                let sideline = people.filter { !$0.isLikelyOnCourt && !$0.isLikelyRef }.count
                print("  \(progress)% - Players:\(players) Refs:\(refs) Sideline:\(sideline)    ", terminator: "\r")
            }
            fflush(stdout)
        } catch {
            // Skip frame
        }

        currentTime += frameInterval
    }

    writerInput.markAsFinished()

    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting {
        semaphore.signal()
    }
    semaphore.wait()

    print("\n\nDone! Output: \(outputURL.path)")
    print("Frames: \(frameCount)")
}

// Run
processVideo()
