//
//  OverlayCompositor.swift
//  SahilStatsLite
//
//  Post-processes video to burn in animated score overlay
//  Uses AVVideoComposition with Core Animation for GPU acceleration
//

import AVFoundation
import UIKit
import CoreGraphics

class OverlayCompositor {

    /// Apply animated score overlay to video
    static func addOverlay(
        to videoURL: URL,
        scoreTimeline: [ScoreTimelineTracker.ScoreSnapshot],
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        debugPrint("🎨 OverlayCompositor: Starting composition")
        debugPrint("   Video: \(videoURL.lastPathComponent)")
        debugPrint("   Timeline snapshots: \(scoreTimeline.count)")

        guard !scoreTimeline.isEmpty else {
            debugPrint("⚠️ Empty score timeline, returning original video")
            completion(.success(videoURL))
            return
        }

        let asset = AVURLAsset(url: videoURL)

        Task {
            await processVideo(asset: asset, scoreTimeline: scoreTimeline, completion: completion)
        }
    }

    private static func processVideo(
        asset: AVURLAsset,
        scoreTimeline: [ScoreTimelineTracker.ScoreSnapshot],
        completion: @escaping (Result<URL, Error>) -> Void
    ) async {
        do {
            debugPrint("🎨 Loading video tracks...")

            // Check if asset is readable
            let isReadable = try await asset.load(.isReadable)
            debugPrint("   Asset readable: \(isReadable)")

            guard isReadable else {
                debugPrint("❌ Asset is not readable")
                completion(.failure(CompositorError.noVideoTrack))
                return
            }

            // Load video track
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            debugPrint("   Found \(videoTracks.count) video tracks")

            guard let videoTrack = videoTracks.first else {
                debugPrint("❌ No video track found")
                completion(.failure(CompositorError.noVideoTrack))
                return
            }

            // Get video properties
            let videoSize = try await videoTrack.load(.naturalSize)
            let videoDuration = try await asset.load(.duration)
            let transform = try await videoTrack.load(.preferredTransform)

            debugPrint("📹 Video: \(Int(videoSize.width))x\(Int(videoSize.height)), \(String(format: "%.1f", CMTimeGetSeconds(videoDuration)))s")

            // Create composition
            let composition = AVMutableComposition()

            guard let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                completion(.failure(CompositorError.failedToCreateTrack))
                return
            }

            // Add video
            try compositionVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: videoDuration),
                of: videoTrack,
                at: .zero
            )

            // Add audio if present
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if let audioTrack = audioTracks.first,
               let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                try? compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: videoDuration),
                    of: audioTrack,
                    at: .zero
                )
            }

            // Calculate render size (accounting for rotation)
            let renderSize = calculateRenderSize(naturalSize: videoSize, transform: transform)

            // Create video composition with overlay
            let videoComposition = createVideoComposition(
                for: compositionVideoTrack,
                renderSize: renderSize,
                scoreTimeline: scoreTimeline,
                videoDuration: videoDuration,
                transform: transform
            )

            // Export
            let outputURL = createOutputURL()

            guard let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                completion(.failure(CompositorError.failedToCreateExportSession))
                return
            }

            exportSession.outputFileType = .mov
            exportSession.videoComposition = videoComposition
            exportSession.shouldOptimizeForNetworkUse = true

            debugPrint("🎬 Exporting with overlay...")

            try await exportSession.export(to: outputURL, as: .mov)

            if FileManager.default.fileExists(atPath: outputURL.path) {
                debugPrint("✅ Export completed: \(outputURL.lastPathComponent)")
                DispatchQueue.main.async {
                    completion(.success(outputURL))
                }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(CompositorError.exportFailed))
                }
            }

        } catch {
            debugPrint("❌ Compositor error: \(error)")
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Video Composition

    private static func createVideoComposition(
        for videoTrack: AVMutableCompositionTrack,
        renderSize: CGSize,
        scoreTimeline: [ScoreTimelineTracker.ScoreSnapshot],
        videoDuration: CMTime,
        transform: CGAffineTransform
    ) -> AVVideoComposition {

        // Calculate correcting transform
        let correctingTransform = calculateCorrectingTransform(for: transform, renderSize: renderSize)

        // Create layer instruction
        var layerInstructionConfig = AVVideoCompositionLayerInstruction.Configuration(trackID: videoTrack.trackID)
        layerInstructionConfig.setTransform(correctingTransform, at: .zero)
        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerInstructionConfig)

        // Create instruction
        var instructionConfig = AVVideoCompositionInstruction.Configuration()
        instructionConfig.timeRange = CMTimeRange(start: .zero, duration: videoDuration)
        instructionConfig.layerInstructions = [layerInstruction]
        let instruction = AVVideoCompositionInstruction(configuration: instructionConfig)

        // Create layers
        let parentLayer = CALayer()
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        // Create animated overlay
        let overlayLayer = createAnimatedOverlay(
            size: renderSize,
            scoreTimeline: scoreTimeline,
            videoDurationSeconds: CMTimeGetSeconds(videoDuration)
        )
        parentLayer.addSublayer(overlayLayer)

        // Create video composition
        var compositionConfig = AVVideoComposition.Configuration()
        compositionConfig.renderSize = renderSize
        compositionConfig.frameDuration = CMTime(value: 1, timescale: 30)
        compositionConfig.instructions = [instruction]
        compositionConfig.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        return AVVideoComposition(configuration: compositionConfig)
    }

    // MARK: - Animated Overlay

    private static func createAnimatedOverlay(
        size: CGSize,
        scoreTimeline: [ScoreTimelineTracker.ScoreSnapshot],
        videoDurationSeconds: TimeInterval
    ) -> CALayer {

        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: size)
        container.isGeometryFlipped = true  // AVFoundation coordinate system

        // Scale based on WIDTH for consistent sizing across orientations
        // Design baseline: 390pt width (iPhone 14/15 width)
        let scaleFactor = size.width / 390.0

        debugPrint("🎨 Overlay: video \(Int(size.width))x\(Int(size.height)), scale: \(String(format: "%.2f", scaleFactor))")

        // Scoreboard dimensions - matches SwiftUI RecordingView design
        // SwiftUI has .padding(.horizontal, 40) on the bar
        let horizontalPadding: CGFloat = 40 * scaleFactor
        let scoreboardWidth: CGFloat = size.width - (horizontalPadding * 2)
        let scoreboardHeight: CGFloat = 50 * scaleFactor
        let scoreboardX = horizontalPadding
        let scoreboardY: CGFloat = 60 * scaleFactor  // Distance from top (accounts for notch)

        // Background with blur effect appearance
        let bgLayer = CALayer()
        bgLayer.frame = CGRect(x: scoreboardX, y: scoreboardY, width: scoreboardWidth, height: scoreboardHeight)
        bgLayer.backgroundColor = UIColor.black.withAlphaComponent(0.6).cgColor
        bgLayer.cornerRadius = 12 * scaleFactor
        container.addSublayer(bgLayer)

        guard let firstSnapshot = scoreTimeline.first else { return container }

        // Layout matches SwiftUI: [TEAM score] | [Q1 / clock] | [score TEAM]
        let innerPadding: CGFloat = 16 * scaleFactor
        let centerWidth: CGFloat = 60 * scaleFactor
        let sideWidth = (scoreboardWidth - centerWidth - innerPadding * 2) / 2

        // Truncate team names to max 8 characters
        let homeTeamDisplay = String(firstSnapshot.homeTeam.prefix(8)).uppercased()
        let awayTeamDisplay = String(firstSnapshot.awayTeam.prefix(8)).uppercased()

        // === LEFT SIDE: Home team name + score ===
        let leftX = scoreboardX + innerPadding

        // Home team name (left aligned)
        let homeTeamLayer = createTextLayer(
            text: homeTeamDisplay,
            frame: CGRect(x: leftX, y: scoreboardY + 8 * scaleFactor, width: sideWidth - 60 * scaleFactor, height: 18 * scaleFactor),
            fontSize: 14 * scaleFactor,
            color: .white,
            alignment: .left
        )
        homeTeamLayer.truncationMode = .end
        container.addSublayer(homeTeamLayer)

        // Home score (right side of left section)
        let homeScoreContainer = createAnimatedScoreLayer(
            timeline: scoreTimeline,
            isHome: true,
            frame: CGRect(x: leftX + sideWidth - 55 * scaleFactor, y: scoreboardY + 10 * scaleFactor, width: 50 * scaleFactor, height: 30 * scaleFactor),
            fontSize: 24 * scaleFactor,
            videoDuration: videoDurationSeconds
        )
        container.addSublayer(homeScoreContainer)

        // === CENTER: Quarter + Clock ===
        let centerX = scoreboardX + innerPadding + sideWidth

        // Quarter label
        let quarterContainer = createAnimatedQuarterLayer(
            timeline: scoreTimeline,
            frame: CGRect(x: centerX, y: scoreboardY + 6 * scaleFactor, width: centerWidth, height: 16 * scaleFactor),
            fontSize: 12 * scaleFactor,
            videoDuration: videoDurationSeconds
        )
        container.addSublayer(quarterContainer)

        // Clock
        let clockContainer = createAnimatedClockLayer(
            timeline: scoreTimeline,
            frame: CGRect(x: centerX, y: scoreboardY + 22 * scaleFactor, width: centerWidth, height: 22 * scaleFactor),
            fontSize: 14 * scaleFactor,
            videoDuration: videoDurationSeconds
        )
        container.addSublayer(clockContainer)

        // === RIGHT SIDE: Score + Away team name ===
        let rightX = scoreboardX + innerPadding + sideWidth + centerWidth

        // Away score (left side of right section)
        let awayScoreContainer = createAnimatedScoreLayer(
            timeline: scoreTimeline,
            isHome: false,
            frame: CGRect(x: rightX + 5 * scaleFactor, y: scoreboardY + 10 * scaleFactor, width: 50 * scaleFactor, height: 30 * scaleFactor),
            fontSize: 24 * scaleFactor,
            videoDuration: videoDurationSeconds
        )
        container.addSublayer(awayScoreContainer)

        // Away team name (right aligned)
        let awayTeamLayer = createTextLayer(
            text: awayTeamDisplay,
            frame: CGRect(x: rightX + 55 * scaleFactor, y: scoreboardY + 8 * scaleFactor, width: sideWidth - 60 * scaleFactor, height: 18 * scaleFactor),
            fontSize: 14 * scaleFactor,
            color: .white,
            alignment: .right
        )
        awayTeamLayer.truncationMode = .end
        container.addSublayer(awayTeamLayer)

        debugPrint("✅ Created animated overlay with \(scoreTimeline.count) keyframes")

        return container
    }

    // MARK: - Animated Layers

    private static func createAnimatedScoreLayer(
        timeline: [ScoreTimelineTracker.ScoreSnapshot],
        isHome: Bool,
        frame: CGRect,
        fontSize: CGFloat,
        videoDuration: TimeInterval
    ) -> CALayer {

        let container = CALayer()
        container.frame = frame

        // Find unique scores
        var uniqueScores = Set<Int>()
        for snapshot in timeline {
            let score = isHome ? snapshot.homeScore : snapshot.awayScore
            uniqueScores.insert(score)
        }

        // Create a layer for each unique score
        for score in uniqueScores.sorted() {
            let textLayer = CATextLayer()
            textLayer.frame = CGRect(origin: .zero, size: frame.size)
            textLayer.string = "\(score)"
            textLayer.fontSize = fontSize
            textLayer.font = UIFont.boldSystemFont(ofSize: fontSize)
            textLayer.foregroundColor = UIColor.white.cgColor
            // Home score is on right of left section, Away score is on left of right section
            textLayer.alignmentMode = isHome ? .right : .left
            textLayer.contentsScale = 3.0

            // Build opacity animation
            var opacityValues: [CGFloat] = []
            var keyTimes: [NSNumber] = []

            for snapshot in timeline where snapshot.timestamp <= videoDuration {
                let currentScore = isHome ? snapshot.homeScore : snapshot.awayScore
                let normalizedTime = snapshot.timestamp / videoDuration
                let opacity: CGFloat = (currentScore == score) ? 1.0 : 0.0

                opacityValues.append(opacity)
                keyTimes.append(NSNumber(value: normalizedTime))
            }

            // Ensure final state persists
            if let lastSnapshot = timeline.last(where: { $0.timestamp <= videoDuration }),
               let lastTime = keyTimes.last?.doubleValue, lastTime < 0.999 {
                let lastScore = isHome ? lastSnapshot.homeScore : lastSnapshot.awayScore
                opacityValues.append(lastScore == score ? 1.0 : 0.0)
                keyTimes.append(1.0)
            }

            if !opacityValues.isEmpty {
                let animation = CAKeyframeAnimation(keyPath: "opacity")
                animation.values = opacityValues
                animation.keyTimes = keyTimes
                animation.duration = videoDuration
                animation.calculationMode = .discrete
                animation.isRemovedOnCompletion = false
                animation.fillMode = .forwards
                animation.beginTime = AVCoreAnimationBeginTimeAtZero

                textLayer.opacity = Float(opacityValues.first ?? 0.0)
                textLayer.add(animation, forKey: "opacity")
            }

            container.addSublayer(textLayer)
        }

        return container
    }

    private static func createAnimatedQuarterLayer(
        timeline: [ScoreTimelineTracker.ScoreSnapshot],
        frame: CGRect,
        fontSize: CGFloat,
        videoDuration: TimeInterval
    ) -> CALayer {

        let container = CALayer()
        container.frame = frame

        var uniqueQuarters = Set<Int>()
        for snapshot in timeline {
            uniqueQuarters.insert(snapshot.quarter)
        }

        for quarter in uniqueQuarters.sorted() {
            let textLayer = CATextLayer()
            textLayer.frame = CGRect(origin: .zero, size: frame.size)
            textLayer.string = "Q\(quarter)"
            textLayer.fontSize = fontSize
            textLayer.font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
            textLayer.foregroundColor = UIColor.orange.cgColor
            textLayer.alignmentMode = .center
            textLayer.contentsScale = 3.0

            var opacityValues: [CGFloat] = []
            var keyTimes: [NSNumber] = []

            for snapshot in timeline where snapshot.timestamp <= videoDuration {
                let normalizedTime = snapshot.timestamp / videoDuration
                let opacity: CGFloat = (snapshot.quarter == quarter) ? 1.0 : 0.0

                opacityValues.append(opacity)
                keyTimes.append(NSNumber(value: normalizedTime))
            }

            if let lastSnapshot = timeline.last(where: { $0.timestamp <= videoDuration }),
               let lastTime = keyTimes.last?.doubleValue, lastTime < 0.999 {
                opacityValues.append(lastSnapshot.quarter == quarter ? 1.0 : 0.0)
                keyTimes.append(1.0)
            }

            if !opacityValues.isEmpty {
                let animation = CAKeyframeAnimation(keyPath: "opacity")
                animation.values = opacityValues
                animation.keyTimes = keyTimes
                animation.duration = videoDuration
                animation.calculationMode = .discrete
                animation.isRemovedOnCompletion = false
                animation.fillMode = .forwards
                animation.beginTime = AVCoreAnimationBeginTimeAtZero

                textLayer.opacity = Float(opacityValues.first ?? 0.0)
                textLayer.add(animation, forKey: "opacity")
            }

            container.addSublayer(textLayer)
        }

        return container
    }

    private static func createAnimatedClockLayer(
        timeline: [ScoreTimelineTracker.ScoreSnapshot],
        frame: CGRect,
        fontSize: CGFloat,
        videoDuration: TimeInterval
    ) -> CALayer {

        let container = CALayer()
        container.frame = frame

        var uniqueTimes = [String]()
        var timeSet = Set<String>()
        for snapshot in timeline {
            if !timeSet.contains(snapshot.clockTime) {
                uniqueTimes.append(snapshot.clockTime)
                timeSet.insert(snapshot.clockTime)
            }
        }

        for clockTime in uniqueTimes {
            let textLayer = CATextLayer()
            textLayer.frame = CGRect(origin: .zero, size: frame.size)
            textLayer.string = clockTime
            textLayer.fontSize = fontSize
            textLayer.font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
            textLayer.foregroundColor = UIColor.white.cgColor
            textLayer.alignmentMode = .center
            textLayer.contentsScale = 3.0

            var opacityValues: [CGFloat] = []
            var keyTimes: [NSNumber] = []

            for snapshot in timeline where snapshot.timestamp <= videoDuration {
                let normalizedTime = snapshot.timestamp / videoDuration
                let opacity: CGFloat = (snapshot.clockTime == clockTime) ? 1.0 : 0.0

                opacityValues.append(opacity)
                keyTimes.append(NSNumber(value: normalizedTime))
            }

            if let lastSnapshot = timeline.last(where: { $0.timestamp <= videoDuration }),
               let lastTime = keyTimes.last?.doubleValue, lastTime < 0.999 {
                opacityValues.append(lastSnapshot.clockTime == clockTime ? 1.0 : 0.0)
                keyTimes.append(1.0)
            }

            if !opacityValues.isEmpty {
                let animation = CAKeyframeAnimation(keyPath: "opacity")
                animation.values = opacityValues
                animation.keyTimes = keyTimes
                animation.duration = videoDuration
                animation.calculationMode = .discrete
                animation.isRemovedOnCompletion = false
                animation.fillMode = .forwards
                animation.beginTime = AVCoreAnimationBeginTimeAtZero

                textLayer.opacity = Float(opacityValues.first ?? 0.0)
                textLayer.add(animation, forKey: "opacity")
            }

            container.addSublayer(textLayer)
        }

        return container
    }

    // MARK: - Helper Methods

    private static func createTextLayer(
        text: String,
        frame: CGRect,
        fontSize: CGFloat,
        color: UIColor,
        alignment: CATextLayerAlignmentMode
    ) -> CATextLayer {
        let layer = CATextLayer()
        layer.frame = frame
        layer.string = text
        layer.fontSize = fontSize
        layer.font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        layer.foregroundColor = color.cgColor
        layer.alignmentMode = alignment
        layer.contentsScale = 3.0
        return layer
    }

    private static func calculateRenderSize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        let angle = atan2(transform.b, transform.a)
        let isRotated = abs(angle - .pi / 2) < 0.1 || abs(angle + .pi / 2) < 0.1

        if isRotated {
            return CGSize(width: naturalSize.height, height: naturalSize.width)
        } else {
            return naturalSize
        }
    }

    private static func calculateCorrectingTransform(for transform: CGAffineTransform, renderSize: CGSize) -> CGAffineTransform {
        let angle = atan2(transform.b, transform.a)
        let degrees = angle * 180 / .pi

        if abs(degrees - 180) < 10 || abs(degrees + 180) < 10 {
            return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: renderSize.width, ty: renderSize.height)
        } else if abs(degrees - 90) < 10 {
            return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: renderSize.height)
        } else if abs(degrees + 90) < 10 || abs(degrees - 270) < 10 {
            return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: renderSize.width, ty: 0)
        } else {
            return .identity
        }
    }

    private static func createOutputURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename = "game_with_overlay_\(Int(Date().timeIntervalSince1970)).mov"
        return documentsPath.appendingPathComponent(filename)
    }

    // MARK: - Errors

    enum CompositorError: Error, LocalizedError {
        case noVideoTrack
        case failedToCreateTrack
        case failedToCreateExportSession
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "No video track found"
            case .failedToCreateTrack: return "Failed to create composition track"
            case .failedToCreateExportSession: return "Failed to create export session"
            case .exportFailed: return "Export failed"
            }
        }
    }
}
