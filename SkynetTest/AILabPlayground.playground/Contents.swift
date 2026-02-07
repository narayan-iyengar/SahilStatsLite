/*:
 # SahilStats AI Lab Playground

 Experiment with computer vision algorithms for:
 - Court line detection (auto-learn bounds)
 - Player pose estimation (distinguish players from spectators)
 - Ball tracking (detect live play vs dead ball)
 - Audio analysis (game sounds vs crowd noise)

 ## Setup
 1. AirDrop game footage to your Mac
 2. Update the `videoPath` or `imagePath` below
 3. Run the playground (Cmd+Shift+Return for all, or click play buttons)

 This playground does NOT affect SahilStatsLite in any way.
*/

import Foundation
import Vision
import AVFoundation
import CoreImage
import AppKit
import PlaygroundSupport

// Enable async execution and live view
PlaygroundPage.current.needsIndefiniteExecution = true

// MARK: - Configuration

/// Path to a game video file (for frame extraction)
let videoPath = "/Users/narayan/Downloads/Sahil games/(9U) Elements vs Vallejo Generals.mp4"

/// Path to a single frame image (for quick testing)
let imagePath = "/Users/narayan/Desktop/court_frame.jpg"

/// Output folder for extracted frames
let outputFolder = "/Users/narayan/Desktop/AILabFrames/"

//: ## 0. Visualization Helpers (Draw boxes, lines, skeletons)

/// Draws bounding boxes around detected humans - GREEN for court, RED for sideline
func drawHumanBoxes(on image: CGImage, humans: [VNHumanObservation]) -> NSImage {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)

    let nsImage = NSImage(cgImage: image, size: NSSize(width: width, height: height))

    nsImage.lockFocus()

    for human in humans {
        let box = human.boundingBox
        // Vision coordinates are normalized (0-1) with origin at bottom-left
        let rect = CGRect(
            x: box.minX * width,
            y: box.minY * height,  // Already bottom-left origin in AppKit
            width: box.width * width,
            height: box.height * height
        )

        // Color based on position: sideline (edges) = red, court (center) = green
        let isOnSideline = box.minX < 0.15 || box.maxX > 0.85
        let color: NSColor = isOnSideline ? .red : .green

        color.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 3.0
        path.stroke()

        // Label
        let label = isOnSideline ? "SIDELINE" : "PLAYER"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.boldSystemFont(ofSize: 14),
            .backgroundColor: NSColor.black.withAlphaComponent(0.7)
        ]
        label.draw(at: CGPoint(x: rect.minX, y: rect.maxY + 2), withAttributes: attrs)
    }

    nsImage.unlockFocus()
    return nsImage
}

/// Draws pose skeleton on image - shows joints and connections
func drawPoseSkeleton(on image: CGImage, poses: [VNHumanBodyPoseObservation]) -> NSImage {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)

    let nsImage = NSImage(cgImage: image, size: NSSize(width: width, height: height))

    nsImage.lockFocus()

    // Define skeleton connections
    let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.nose, .neck),
        (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.neck, .root),
        (.root, .leftHip), (.root, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
    ]

    for (poseIndex, pose) in poses.enumerated() {
        // Alternate colors for different people
        let colors: [NSColor] = [.cyan, .magenta, .yellow, .orange, .green]
        let color = colors[poseIndex % colors.count]

        color.setStroke()
        color.setFill()

        // Draw connections
        for (joint1, joint2) in connections {
            if let p1 = try? pose.recognizedPoint(joint1),
               let p2 = try? pose.recognizedPoint(joint2),
               p1.confidence > 0.3 && p2.confidence > 0.3 {

                let point1 = CGPoint(x: p1.x * width, y: p1.y * height)
                let point2 = CGPoint(x: p2.x * width, y: p2.y * height)

                let path = NSBezierPath()
                path.move(to: point1)
                path.line(to: point2)
                path.lineWidth = 2.0
                path.stroke()
            }
        }

        // Draw joints as circles
        let allJoints: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck, .leftShoulder, .rightShoulder,
            .leftElbow, .rightElbow, .leftWrist, .rightWrist,
            .root, .leftHip, .rightHip,
            .leftKnee, .rightKnee, .leftAnkle, .rightAnkle
        ]

        for joint in allJoints {
            if let point = try? pose.recognizedPoint(joint), point.confidence > 0.3 {
                let center = CGPoint(x: point.x * width, y: point.y * height)
                let circle = NSBezierPath(ovalIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
                circle.fill()
            }
        }
    }

    nsImage.unlockFocus()
    return nsImage
}

/// Draws detected rectangles (potential court lines) in BLUE
func drawRectangles(on image: CGImage, rectangles: [VNRectangleObservation]) -> NSImage {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)

    let nsImage = NSImage(cgImage: image, size: NSSize(width: width, height: height))

    nsImage.lockFocus()

    NSColor.blue.setStroke()

    for rect in rectangles {
        // VNRectangleObservation has corner points
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.bottomLeft.x * width, y: rect.bottomLeft.y * height))
        path.line(to: CGPoint(x: rect.bottomRight.x * width, y: rect.bottomRight.y * height))
        path.line(to: CGPoint(x: rect.topRight.x * width, y: rect.topRight.y * height))
        path.line(to: CGPoint(x: rect.topLeft.x * width, y: rect.topLeft.y * height))
        path.close()
        path.lineWidth = 3.0
        path.stroke()
    }

    nsImage.unlockFocus()
    return nsImage
}

/// Show an image in the playground's live view
func showImage(_ image: NSImage, title: String = "Result") {
    print("Displaying: \(title) (\(Int(image.size.width))x\(Int(image.size.height)))")

    // Create a simple view to show the image
    let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 800, height: 450))
    imageView.image = image
    imageView.imageScaling = .scaleProportionallyUpOrDown

    PlaygroundPage.current.liveView = imageView
}

/// Save annotated image to Desktop
func saveImage(_ image: NSImage, name: String) {
    let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    let url = desktop.appendingPathComponent("\(name).png")

    if let tiffData = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let pngData = bitmap.representation(using: .png, properties: [:]) {
        try? pngData.write(to: url)
        print("Saved: \(url.path)")
    }
}

//: ## 1. Extract Frames from Video

/// Extracts frames from a video at specified interval
func extractFrames(from videoURL: URL, every seconds: Double = 1.0, maxFrames: Int = 10) async -> [CGImage] {
    let asset = AVURLAsset(url: videoURL)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero

    var frames: [CGImage] = []
    let duration: Double
    do {
        let d = try await asset.load(.duration)
        duration = CMTimeGetSeconds(d)
    } catch {
        print("Could not load duration: \(error)")
        return []
    }

    var currentTime: Double = 0
    while currentTime < duration && frames.count < maxFrames {
        let time = CMTime(seconds: currentTime, preferredTimescale: 600)
        if let result = try? await generator.image(at: time) {
            frames.append(result.image)
            print("Extracted frame at \(currentTime)s")
        }
        currentTime += seconds
    }

    print("Total frames extracted: \(frames.count)")
    return frames
}

// Uncomment to extract frames (async):
// Task {
//     let frames = await extractFrames(from: URL(fileURLWithPath: videoPath), every: 5.0, maxFrames: 20)
//     let heatMap = buildActivityHeatMap(frames: frames)
// }

//: ## 2. Court Line Detection

/// Detects rectangles and lines that could be court boundaries
func detectCourtLines(in image: CGImage) -> [VNRectangleObservation] {
    let request = VNDetectRectanglesRequest()
    request.minimumConfidence = 0.3
    request.maximumObservations = 20
    request.minimumSize = 0.1  // At least 10% of image
    request.minimumAspectRatio = 0.3
    request.maximumAspectRatio = 3.0

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([request])

    let results = request.results ?? []
    print("Found \(results.count) rectangles")

    for (i, rect) in results.enumerated() {
        print("  \(i+1). Confidence: \(rect.confidence), Bounds: \(rect.boundingBox)")
    }

    return results
}

/// Detects contours (lines, curves) in an image - good for court markings
func detectContours(in image: CGImage) -> [VNContoursObservation] {
    let request = VNDetectContoursRequest()
    request.contrastAdjustment = 2.0
    request.detectsDarkOnLight = true

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([request])

    let results = request.results ?? []
    print("Found \(results.count) contour groups")

    for contour in results {
        print("  Contour with \(contour.contourCount) sub-contours")
    }

    return results
}

// Uncomment to test court detection:
// if let image = NSImage(contentsOfFile: imagePath)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
//     let rectangles = detectCourtLines(in: image)
//     let contours = detectContours(in: image)
// }

//: ## 3. Human Pose Estimation

/// Detects human body poses - useful for distinguishing active players from standing spectators
func detectPoses(in image: CGImage) -> [VNHumanBodyPoseObservation] {
    let request = VNDetectHumanBodyPoseRequest()

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([request])

    let results = request.results ?? []
    print("Found \(results.count) people")

    for (i, pose) in results.enumerated() {
        // Check if person is in athletic stance (knees bent, arms out)
        if let leftKnee = try? pose.recognizedPoint(.leftKnee),
           let rightKnee = try? pose.recognizedPoint(.rightKnee),
           let leftAnkle = try? pose.recognizedPoint(.leftAnkle),
           let rightAnkle = try? pose.recognizedPoint(.rightAnkle) {

            // Calculate knee angle (bent knees = player, straight = spectator)
            let leftKneeBend = leftKnee.y - leftAnkle.y
            let rightKneeBend = rightKnee.y - rightAnkle.y
            let avgBend = (leftKneeBend + rightKneeBend) / 2

            let isActive = avgBend > 0.1  // Threshold for "active" stance
            print("  \(i+1). \(isActive ? "PLAYER (active)" : "SPECTATOR (standing)")")
        }
    }

    return results
}

/// Detects human rectangles (bounding boxes) - faster than full pose
func detectHumans(in image: CGImage) -> [VNHumanObservation] {
    let request = VNDetectHumanRectanglesRequest()
    request.upperBodyOnly = false

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([request])

    let results = request.results ?? []
    print("Found \(results.count) humans (bounding boxes)")

    for (i, human) in results.enumerated() {
        let box = human.boundingBox
        // People on sidelines are usually at edges of frame
        let isOnSideline = box.minX < 0.1 || box.maxX > 0.9
        print("  \(i+1). Position: \(isOnSideline ? "SIDELINE" : "COURT") - \(box)")
    }

    return results
}

// Uncomment to test pose detection:
// if let image = NSImage(contentsOfFile: imagePath)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
//     let poses = detectPoses(in: image)
//     let humans = detectHumans(in: image)
// }

//: ## 4. Ball Detection (Color-based)

/// Detects orange objects that could be basketballs
func detectBall(in image: CGImage) -> [CGRect] {
    // Basketball orange color range (HSV: ~15-25 hue)
    // In production, would use a trained CoreML model

    print("Ball detection requires CoreML model for accuracy")
    print("Placeholder: Would analyze orange color regions in \(image.width)x\(image.height) image")

    // TODO: Train or download basketball detection model
    // Options:
    // - CreateML with basketball images
    // - YOLO model fine-tuned for sports
    // - Apple's built-in object detection + color filtering

    return []
}

//: ## 5. Build Activity Heat Map & Tracking Region

/// Tracking region result - the "court bounds" learned from player activity
struct TrackingRegion {
    let minX: CGFloat  // Normalized 0-1
    let maxX: CGFloat
    let minY: CGFloat
    let maxY: CGFloat

    var width: CGFloat { maxX - minX }
    var height: CGFloat { maxY - minY }
    var centerX: CGFloat { (minX + maxX) / 2 }
    var centerY: CGFloat { (minY + maxY) / 2 }

    /// For DockKit setRegionOfInterest()
    var asNormalizedRect: CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }

    func description() -> String {
        return """
        Tracking Region (normalized 0-1):
          X: \(String(format: "%.2f", minX)) to \(String(format: "%.2f", maxX)) (width: \(String(format: "%.2f", width)))
          Y: \(String(format: "%.2f", minY)) to \(String(format: "%.2f", maxY)) (height: \(String(format: "%.2f", height)))
          Center: (\(String(format: "%.2f", centerX)), \(String(format: "%.2f", centerY)))
        """
    }
}

/// Analyzes multiple frames to build heat map of activity
func buildActivityHeatMap(frames: [CGImage], gridSize: Int = 20) -> [[Int]] {
    guard frames.first != nil else { return [] }

    print("Building heat map from \(frames.count) frames (\(gridSize)x\(gridSize) grid)...")

    // Initialize heat map
    var heatMap = Array(repeating: Array(repeating: 0, count: gridSize), count: gridSize)

    for (frameIndex, frame) in frames.enumerated() {
        let request = VNDetectHumanRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: frame, options: [:])
        try? handler.perform([request])

        let humans = request.results ?? []

        for human in humans {
            let box = human.boundingBox

            // Add weight to all cells the human overlaps, not just center
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

        if (frameIndex + 1) % 5 == 0 {
            print("  Processed \(frameIndex + 1)/\(frames.count) frames...")
        }
    }

    return heatMap
}

/// Calculate tracking region from heat map using threshold
func calculateTrackingRegion(from heatMap: [[Int]], threshold: Double = 0.40) -> TrackingRegion {
    let gridSize = heatMap.count
    guard gridSize > 0 else {
        return TrackingRegion(minX: 0.1, maxX: 0.9, minY: 0.1, maxY: 0.9)
    }

    // Find max value
    let maxVal = heatMap.flatMap { $0 }.max() ?? 1
    let cutoff = Int(Double(maxVal) * threshold)

    print("Heat map max: \(maxVal), threshold cutoff: \(cutoff) (\(Int(threshold * 100))%)")

    // Find bounds of cells above threshold
    // Only ignore top 30% (ceiling/wall) - let bottom be more generous for players' feet
    let minYSearch = Int(Double(gridSize) * 0.05)  // Skip bottom 5% only (camera operator's head)
    let maxYSearch = Int(Double(gridSize) * 0.70)  // Skip top 30% (ceiling)

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

    // If nothing found above threshold, use defaults
    if minX >= gridSize {
        print("Warning: No cells above threshold, using defaults")
        return TrackingRegion(minX: 0.15, maxX: 0.85, minY: 0.25, maxY: 0.70)
    }

    // Convert to normalized coordinates (0-1)
    // Add padding - more generous vertically to capture players' feet
    let horizontalPadding = 0.03
    let verticalPadding = 0.08  // More room top/bottom for full body capture
    let region = TrackingRegion(
        minX: max(0, CGFloat(minX) / CGFloat(gridSize) - horizontalPadding),
        maxX: min(1, CGFloat(maxX + 1) / CGFloat(gridSize) + horizontalPadding),
        minY: max(0, CGFloat(minY) / CGFloat(gridSize) - verticalPadding),
        maxY: min(1, CGFloat(maxY + 1) / CGFloat(gridSize) + verticalPadding)
    )

    print(region.description())

    return region
}

/// Visualize heat map with tracking region overlay
func drawHeatMapWithRegion(on image: CGImage, heatMap: [[Int]], region: TrackingRegion) -> NSImage {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)

    let nsImage = NSImage(cgImage: image, size: NSSize(width: width, height: height))

    nsImage.lockFocus()

    let gridSize = heatMap.count
    guard gridSize > 0 else {
        nsImage.unlockFocus()
        return nsImage
    }

    let cellWidth = width / CGFloat(gridSize)
    let cellHeight = height / CGFloat(gridSize)

    // Find max value for normalization
    let maxVal = heatMap.flatMap { $0 }.max() ?? 1

    // Draw heat map cells
    for (y, row) in heatMap.enumerated() {
        for (x, value) in row.enumerated() {
            let intensity = CGFloat(value) / CGFloat(maxVal)

            // Color gradient: transparent -> yellow -> orange -> red
            let color: NSColor
            if intensity < 0.25 {
                color = NSColor(red: 0, green: 0, blue: 1, alpha: intensity * 2)  // Blue, faint
            } else if intensity < 0.5 {
                color = NSColor(red: 1, green: 1, blue: 0, alpha: 0.4)  // Yellow
            } else if intensity < 0.75 {
                color = NSColor(red: 1, green: 0.5, blue: 0, alpha: 0.5)  // Orange
            } else {
                color = NSColor(red: 1, green: 0, blue: 0, alpha: 0.6)  // Red = hot
            }

            color.setFill()

            let rect = CGRect(
                x: CGFloat(x) * cellWidth,
                y: CGFloat(y) * cellHeight,
                width: cellWidth,
                height: cellHeight
            )
            NSBezierPath(rect: rect).fill()
        }
    }

    // Draw tracking region boundary (thick green rectangle)
    NSColor.green.setStroke()
    let regionRect = CGRect(
        x: region.minX * width,
        y: region.minY * height,
        width: region.width * width,
        height: region.height * height
    )
    let regionPath = NSBezierPath(rect: regionRect)
    regionPath.lineWidth = 6.0
    regionPath.stroke()

    // Label
    let label = "TRACKING REGION"
    let attrs: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.green,
        .font: NSFont.boldSystemFont(ofSize: 24),
        .backgroundColor: NSColor.black.withAlphaComponent(0.8)
    ]
    label.draw(at: CGPoint(x: regionRect.minX + 10, y: regionRect.maxY + 10), withAttributes: attrs)

    // Draw "IGNORE" labels outside the region
    let ignoreAttrs: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.red,
        .font: NSFont.boldSystemFont(ofSize: 18),
        .backgroundColor: NSColor.black.withAlphaComponent(0.7)
    ]

    if region.minX > 0.1 {
        "← IGNORE".draw(at: CGPoint(x: 20, y: height / 2), withAttributes: ignoreAttrs)
    }
    if region.maxX < 0.9 {
        "IGNORE →".draw(at: CGPoint(x: width - 120, y: height / 2), withAttributes: ignoreAttrs)
    }

    nsImage.unlockFocus()
    return nsImage
}

/// Print heat map to console with visual representation
func printHeatMap(_ heatMap: [[Int]]) {
    let maxVal = heatMap.flatMap { $0 }.max() ?? 1

    print("\nActivity Heat Map (░ = low, ▓ = medium, █ = high):")
    print("┌" + String(repeating: "──", count: heatMap[0].count) + "┐")

    for row in heatMap.reversed() {
        var line = "│"
        for value in row {
            let intensity = Double(value) / Double(maxVal)
            if intensity < 0.2 {
                line += "  "
            } else if intensity < 0.4 {
                line += "░░"
            } else if intensity < 0.6 {
                line += "▒▒"
            } else if intensity < 0.8 {
                line += "▓▓"
            } else {
                line += "██"
            }
        }
        line += "│"
        print(line)
    }

    print("└" + String(repeating: "──", count: heatMap[0].count) + "┘")
    print("  ↑ Sideline          Court          Sideline ↑")
}

//: ## 6. Audio Analysis (Bonus)

/// Analyzes audio to detect game sounds vs crowd noise
func analyzeAudio(from videoURL: URL) async {
    let asset = AVURLAsset(url: videoURL)

    do {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks.first else {
            print("No audio track found")
            return
        }

        let duration = try await asset.load(.duration)
        let formats = try await audioTrack.load(.formatDescriptions)

        print("Audio track found:")
        print("  Duration: \(CMTimeGetSeconds(duration))s")
        print("  Format: \(formats)")
    } catch {
        print("Error loading audio: \(error)")
        return
    }

    // For real audio analysis, would use:
    // - AVAudioEngine for real-time processing
    // - Accelerate framework for FFT (frequency analysis)
    // - CoreML sound classification model

    print("\nAudio analysis TODO:")
    print("  1. Extract frequency bands")
    print("  2. Identify whistle frequencies (~2-4 kHz)")
    print("  3. Identify crowd noise (broadband, low frequency)")
    print("  4. Identify ball bouncing (~100-500 Hz)")
}

// Uncomment to analyze audio (async):
// Task {
//     await analyzeAudio(from: URL(fileURLWithPath: videoPath))
// }

//: ## 7. Export Annotated Video

/// Process video and export with tracking overlay
/// - startTime: where to start in the video (seconds)
/// - duration: how many seconds to process
func exportAnnotatedVideo(inputPath: String, outputName: String = "AILab_Annotated", startTime: Double = 0, clipDuration: Double = 30) async {
    print("=== EXPORTING ANNOTATED VIDEO ===")
    print("Processing from \(Int(startTime))s to \(Int(startTime + clipDuration))s\n")

    let inputURL = URL(fileURLWithPath: inputPath)
    let outputURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop")
        .appendingPathComponent("\(outputName).mp4")

    // Delete existing output file
    try? FileManager.default.removeItem(at: outputURL)

    let asset = AVURLAsset(url: inputURL)

    // Get video properties
    guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
        print("ERROR: No video track found")
        return
    }

    let duration = try? await asset.load(.duration)
    let naturalSize = try? await videoTrack.load(.naturalSize)
    let frameRate = try? await videoTrack.load(.nominalFrameRate)

    guard let duration = duration, let naturalSize = naturalSize, let frameRate = frameRate else {
        print("ERROR: Could not load video properties")
        return
    }

    let totalSeconds = CMTimeGetSeconds(duration)
    print("Video: \(Int(naturalSize.width))x\(Int(naturalSize.height)), \(String(format: "%.1f", frameRate)) fps, \(String(format: "%.1f", totalSeconds))s")

    // First pass: build heat map from samples (reduced for stability)
    print("\nPass 1: Building heat map...")
    let sampleFrames = await extractFrames(from: inputURL, every: 10.0, maxFrames: 20)
    let heatMap = buildActivityHeatMap(frames: sampleFrames, gridSize: 20)
    let trackingRegion = calculateTrackingRegion(from: heatMap, threshold: 0.40)

    // Setup video writer
    guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
        print("ERROR: Could not create video writer")
        return
    }

    let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(naturalSize.width),
        AVVideoHeightKey: Int(naturalSize.height)
    ]

    let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: writerInput,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(naturalSize.width),
            kCVPixelBufferHeightKey as String: Int(naturalSize.height)
        ]
    )

    writer.add(writerInput)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    // Process frames
    print("\nPass 2: Processing frames...")
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

    // SPEED SETTINGS (reduced for stability)
    let frameInterval = 0.5  // 2 fps output - less memory pressure

    var currentTime: Double = startTime
    var frameCount = 0
    let processUntil = min(totalSeconds, startTime + clipDuration)

    print("Processing \(String(format: "%.0f", processUntil - startTime)) seconds at 5 fps (from \(Int(startTime))s to \(Int(processUntil))s)...")

    while currentTime < processUntil {
        let time = CMTime(seconds: currentTime, preferredTimescale: 600)

        if let result = try? await generator.image(at: time) {
            let cgImage = result.image

            // Detect humans in this frame
            let humans = detectHumansQuiet(in: cgImage)

            // Draw annotations
            let annotated = drawTrackingOverlay(
                on: cgImage,
                region: trackingRegion,
                humans: humans
            )

            // Convert to pixel buffer and write
            if let pixelBuffer = pixelBuffer(from: annotated, size: naturalSize) {
                while !writerInput.isReadyForMoreMediaData {
                    try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
                }
                adaptor.append(pixelBuffer, withPresentationTime: time)
            }

            frameCount += 1
            if frameCount % 30 == 0 {
                let progress = Int((currentTime / totalSeconds) * 100)
                print("  \(progress)% complete (\(frameCount) frames)...")
            }
        }

        currentTime += frameInterval
    }

    // Finish writing
    writerInput.markAsFinished()
    await writer.finishWriting()

    print("\n=== VIDEO EXPORT COMPLETE ===")
    print("Output: \(outputURL.path)")
    print("Frames processed: \(frameCount)")
}

/// Detect humans without console spam
func detectHumansQuiet(in image: CGImage) -> [VNHumanObservation] {
    let request = VNDetectHumanRectanglesRequest()
    request.upperBodyOnly = false
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([request])
    return request.results ?? []
}

/// Draw tracking region and human boxes on frame
func drawTrackingOverlay(on image: CGImage, region: TrackingRegion, humans: [VNHumanObservation]) -> NSImage {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)

    let nsImage = NSImage(cgImage: image, size: NSSize(width: width, height: height))

    nsImage.lockFocus()

    // Draw tracking region boundary (green rectangle)
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

    // Draw semi-transparent overlay outside tracking region (the "ignore" zones)
    NSColor.red.withAlphaComponent(0.2).setFill()

    // Left ignore zone
    if region.minX > 0.02 {
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: region.minX * width, height: height)).fill()
    }
    // Right ignore zone
    if region.maxX < 0.98 {
        NSBezierPath(rect: CGRect(x: region.maxX * width, y: 0, width: (1 - region.maxX) * width, height: height)).fill()
    }
    // Top ignore zone
    if region.maxY < 0.98 {
        NSBezierPath(rect: CGRect(x: region.minX * width, y: region.maxY * height, width: region.width * width, height: (1 - region.maxY) * height)).fill()
    }
    // Bottom ignore zone
    if region.minY > 0.02 {
        NSBezierPath(rect: CGRect(x: region.minX * width, y: 0, width: region.width * width, height: region.minY * height)).fill()
    }

    // Draw human boxes - THICKER lines so they're visible in video
    for human in humans {
        let box = human.boundingBox
        let rect = CGRect(
            x: box.minX * width,
            y: box.minY * height,
            width: box.width * width,
            height: box.height * height
        )

        // Is this human inside or outside the tracking region?
        let isInRegion = box.midX >= region.minX && box.midX <= region.maxX &&
                         box.midY >= region.minY && box.midY <= region.maxY

        let color: NSColor = isInRegion ? .cyan : .orange
        color.setStroke()

        let boxPath = NSBezierPath(rect: rect)
        boxPath.lineWidth = 4.0  // Thicker!
        boxPath.stroke()

        // Add label
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

/// Convert NSImage to CVPixelBuffer for video writing
func pixelBuffer(from image: NSImage, size: CGSize) -> CVPixelBuffer? {
    let attrs: [String: Any] = [
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ]

    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        Int(size.width),
        Int(size.height),
        kCVPixelFormatType_32ARGB,
        attrs as CFDictionary,
        &pixelBuffer
    )

    guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
        return nil
    }

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

    guard let ctx = context else { return nil }

    // Draw the image
    if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))
    }

    return buffer
}

//: ## 8. Complete Demo - Visualize Everything!

/// Run full analysis on a video and show annotated frames
func runFullDemo() async {
    print("=== STARTING FULL DEMO ===\n")

    // 1. Extract MORE frames for better heat map
    print("Step 1: Extracting frames from video...")
    let videoURL = URL(fileURLWithPath: videoPath)
    let frames = await extractFrames(from: videoURL, every: 5.0, maxFrames: 20)  // More frames!

    guard let firstFrame = frames.first else {
        print("ERROR: Could not extract frames from video")
        print("Make sure videoPath points to a valid video file")
        return
    }

    // 2. Build heat map from all frames (this is the key!)
    print("\nStep 2: Building activity heat map from \(frames.count) frames...")
    let heatMap = buildActivityHeatMap(frames: frames, gridSize: 20)
    printHeatMap(heatMap)

    // 3. Calculate tracking region from heat map
    // Higher threshold = tighter region (only include high-activity cells)
    print("\nStep 3: Calculating tracking region...")
    let trackingRegion = calculateTrackingRegion(from: heatMap, threshold: 0.40)

    // 4. Visualize heat map with tracking region
    print("\nStep 4: Drawing heat map with tracking region...")
    let heatMapWithRegion = drawHeatMapWithRegion(on: firstFrame, heatMap: heatMap, region: trackingRegion)

    // 5. Also do skeleton detection for comparison
    print("\nStep 5: Detecting poses for visualization...")
    let poses = detectPoses(in: firstFrame)
    let skeletonImage = drawPoseSkeleton(on: firstFrame, poses: poses)

    // 6. Save images
    print("\nStep 6: Saving annotated images to Desktop...")
    saveImage(heatMapWithRegion, name: "AILab_TrackingRegion")
    saveImage(skeletonImage, name: "AILab_Skeletons")

    // 7. Show tracking region result
    print("\nStep 7: Displaying tracking region...")
    showImage(heatMapWithRegion, title: "Tracking Region")

    print("\n=== DEMO COMPLETE ===")
    print("")
    print("TRACKING REGION FOR DOCKKIT:")
    print("─────────────────────────────")
    print(trackingRegion.description())
    print("")
    print("Swift code for DockKit:")
    print("  let region = CGRect(x: \(String(format: "%.3f", trackingRegion.minX)), y: \(String(format: "%.3f", trackingRegion.minY)), width: \(String(format: "%.3f", trackingRegion.width)), height: \(String(format: "%.3f", trackingRegion.height)))")
    print("  dockAccessory.setRegionOfInterest(region)")
    print("")
    print("Images saved:")
    print("  - AILab_TrackingRegion.png  (heat map + green tracking box)")
    print("  - AILab_Skeletons.png       (pose detection)")
}

/// Quick single-frame analysis (faster for testing)
func analyzeFrame(at path: String) {
    print("Analyzing single frame: \(path)\n")

    guard let nsImage = NSImage(contentsOfFile: path),
          let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("ERROR: Could not load image at path")
        return
    }

    // Detect and draw
    let humans = detectHumans(in: cgImage)
    let poses = detectPoses(in: cgImage)

    let annotated = drawHumanBoxes(on: cgImage, humans: humans)
    let withSkeleton = drawPoseSkeleton(on: cgImage, poses: poses)

    saveImage(annotated, name: "AILab_Analyzed_Boxes")
    saveImage(withSkeleton, name: "AILab_Analyzed_Skeleton")

    showImage(withSkeleton, title: "Analysis Result")

    print("\nImages saved to Desktop!")
}

//: ## Run the Demo

print("=== AI Lab Playground Ready ===\n")
print("Your video: \(videoPath)\n")

// UNCOMMENT ONE OF THESE TO RUN:

// Option 1: Full demo (extracts frames, runs all detection, saves images)
//Task {
//    await runFullDemo()
//}

// Option 2: Export annotated VIDEO (see AI tracking in motion!)
// ADJUST THESE to test different parts of the game:
let startAtSecond: Double = 680    // 11:20 into the video
let processDuration: Double = 30   // Process 30 seconds (reduced for stability)

Task {
    await exportAnnotatedVideo(
        inputPath: videoPath,
        outputName: "AILab_Tracked",
        startTime: startAtSecond,
        clipDuration: processDuration
    )
}

// Option 3: Analyze a single frame image (faster)
// analyzeFrame(at: imagePath)

// Option 4: Just extract and show a frame
// Task {
//     let frames = await extractFrames(from: URL(fileURLWithPath: videoPath), every: 30.0, maxFrames: 1)
//     if let frame = frames.first {
//         showImage(NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height)), title: "Frame")
//     }
// }
