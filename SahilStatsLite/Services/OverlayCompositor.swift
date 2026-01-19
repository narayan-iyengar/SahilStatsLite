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

            debugPrint("📹 Video natural size: \(Int(videoSize.width))x\(Int(videoSize.height))")
            debugPrint("📹 Video duration: \(String(format: "%.1f", CMTimeGetSeconds(videoDuration)))s")
            debugPrint("📹 Video transform: a=\(transform.a), b=\(transform.b), c=\(transform.c), d=\(transform.d)")
            debugPrint("📹 Video transform: tx=\(transform.tx), ty=\(transform.ty)")

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
            debugPrint("📹 Calculated render size: \(Int(renderSize.width))x\(Int(renderSize.height))")

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

        debugPrint("🎬 Creating video composition with renderSize: \(Int(renderSize.width))x\(Int(renderSize.height))")

        let angle = atan2(transform.b, transform.a)
        let degrees = angle * 180 / .pi
        debugPrint("🔄 Video preferredTransform rotation: \(String(format: "%.1f", degrees))°")
        debugPrint("   Transform: a=\(transform.a), b=\(transform.b), c=\(transform.c), d=\(transform.d), tx=\(transform.tx), ty=\(transform.ty)")

        // Apply the preferredTransform to display video correctly
        debugPrint("   → Applying preferredTransform to video")

        // Create layer instruction with the video's preferredTransform
        var layerInstructionConfig = AVVideoCompositionLayerInstruction.Configuration(trackID: videoTrack.trackID)
        layerInstructionConfig.setTransform(transform, at: .zero)
        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerInstructionConfig)

        // Create instruction
        var instructionConfig = AVVideoCompositionInstruction.Configuration()
        instructionConfig.timeRange = CMTimeRange(start: .zero, duration: videoDuration)
        instructionConfig.layerInstructions = [layerInstruction]
        let instruction = AVVideoCompositionInstruction(configuration: instructionConfig)

        debugPrint("   Render size: \(Int(renderSize.width))x\(Int(renderSize.height))")

        // Create layers - both use the transformed render size
        let parentLayer = CALayer()
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        // Create animated overlay - uses the same render size so it aligns with video
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
    // Broadcast-style scoreboard similar to ScoreCam's Longboard design

    private static func createAnimatedOverlay(
        size: CGSize,
        scoreTimeline: [ScoreTimelineTracker.ScoreSnapshot],
        videoDurationSeconds: TimeInterval
    ) -> CALayer {

        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: size)
        container.isGeometryFlipped = true  // AVFoundation coordinate system

        // Scale based on the smaller dimension for consistent sizing
        let baseSize: CGFloat = 390.0
        let scaleFactor = min(size.width, size.height) / baseSize

        debugPrint("🎨 Overlay: video \(Int(size.width))x\(Int(size.height)), scale: \(String(format: "%.2f", scaleFactor))")

        guard let firstSnapshot = scoreTimeline.first else { return container }

        // Debug: show first snapshot values
        debugPrint("📊 First snapshot: home=\(firstSnapshot.homeScore), away=\(firstSnapshot.awayScore), Q\(firstSnapshot.quarter), clock=\(firstSnapshot.clockTime)")

        // Scoreboard dimensions - compact broadcast style
        let scoreboardHeight: CGFloat = 44 * scaleFactor
        let teamBoxWidth: CGFloat = 100 * scaleFactor
        let scoreBoxWidth: CGFloat = 50 * scaleFactor
        let centerBoxWidth: CGFloat = 70 * scaleFactor
        let totalWidth = (teamBoxWidth + scoreBoxWidth) * 2 + centerBoxWidth
        let scoreboardX = (size.width - totalWidth) / 2
        let scoreboardY: CGFloat = 40 * scaleFactor

        // Colors
        let homeColor = UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)  // Blue
        let awayColor = UIColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1.0)  // Red/Orange
        let darkBg = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.95)
        let scoreBg = UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 0.95)

        var currentX = scoreboardX

        // === HOME TEAM BOX (colored background) ===
        let homeTeamBox = CALayer()
        homeTeamBox.frame = CGRect(x: currentX, y: scoreboardY, width: teamBoxWidth, height: scoreboardHeight)
        homeTeamBox.backgroundColor = homeColor.cgColor
        // Round left corners only
        homeTeamBox.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        homeTeamBox.cornerRadius = 6 * scaleFactor
        addStaticAnimation(to: homeTeamBox, duration: videoDurationSeconds)
        container.addSublayer(homeTeamBox)

        // Home team name (truncated, centered in box)
        let homeTeamDisplay = String(firstSnapshot.homeTeam.prefix(10)).uppercased()
        let homeTeamLabel = createTextLayer(
            text: homeTeamDisplay,
            frame: CGRect(x: currentX + 8 * scaleFactor, y: scoreboardY + 12 * scaleFactor, width: teamBoxWidth - 16 * scaleFactor, height: 20 * scaleFactor),
            fontSize: 14 * scaleFactor,
            color: .white,
            alignment: .center
        )
        homeTeamLabel.truncationMode = .end
        addStaticAnimation(to: homeTeamLabel, duration: videoDurationSeconds)
        container.addSublayer(homeTeamLabel)
        currentX += teamBoxWidth

        // === HOME SCORE BOX ===
        let homeScoreBox = CALayer()
        homeScoreBox.frame = CGRect(x: currentX, y: scoreboardY, width: scoreBoxWidth, height: scoreboardHeight)
        homeScoreBox.backgroundColor = scoreBg.cgColor
        addStaticAnimation(to: homeScoreBox, duration: videoDurationSeconds)
        container.addSublayer(homeScoreBox)

        // ANIMATED home score
        let homeScoreLayer = createAnimatedScoreLayer(
            timeline: scoreTimeline,
            isHome: true,
            frame: CGRect(x: currentX, y: scoreboardY + 8 * scaleFactor, width: scoreBoxWidth, height: 28 * scaleFactor),
            fontSize: 22 * scaleFactor,
            videoDuration: videoDurationSeconds
        )
        container.addSublayer(homeScoreLayer)
        debugPrint("📊 Added ANIMATED home score")
        currentX += scoreBoxWidth

        // === CENTER BOX (Half + Clock) ===
        let centerBox = CALayer()
        centerBox.frame = CGRect(x: currentX, y: scoreboardY, width: centerBoxWidth, height: scoreboardHeight)
        centerBox.backgroundColor = darkBg.cgColor
        addStaticAnimation(to: centerBox, duration: videoDurationSeconds)
        container.addSublayer(centerBox)

        // ANIMATED half label
        let halfLayer = createAnimatedQuarterLayer(
            timeline: scoreTimeline,
            frame: CGRect(x: currentX, y: scoreboardY + 4 * scaleFactor, width: centerBoxWidth, height: 16 * scaleFactor),
            fontSize: 11 * scaleFactor,
            videoDuration: videoDurationSeconds
        )
        container.addSublayer(halfLayer)

        // ANIMATED clock
        let clockLayer = createAnimatedClockLayer(
            timeline: scoreTimeline,
            frame: CGRect(x: currentX, y: scoreboardY + 22 * scaleFactor, width: centerBoxWidth, height: 18 * scaleFactor),
            fontSize: 14 * scaleFactor,
            videoDuration: videoDurationSeconds
        )
        container.addSublayer(clockLayer)
        debugPrint("📊 Added ANIMATED half and clock")
        currentX += centerBoxWidth

        // === AWAY SCORE BOX ===
        let awayScoreBox = CALayer()
        awayScoreBox.frame = CGRect(x: currentX, y: scoreboardY, width: scoreBoxWidth, height: scoreboardHeight)
        awayScoreBox.backgroundColor = scoreBg.cgColor
        addStaticAnimation(to: awayScoreBox, duration: videoDurationSeconds)
        container.addSublayer(awayScoreBox)

        // ANIMATED away score
        let awayScoreLayer = createAnimatedScoreLayer(
            timeline: scoreTimeline,
            isHome: false,
            frame: CGRect(x: currentX, y: scoreboardY + 8 * scaleFactor, width: scoreBoxWidth, height: 28 * scaleFactor),
            fontSize: 22 * scaleFactor,
            videoDuration: videoDurationSeconds
        )
        container.addSublayer(awayScoreLayer)
        debugPrint("📊 Added ANIMATED away score")
        currentX += scoreBoxWidth

        // === AWAY TEAM BOX (colored background) ===
        let awayTeamBox = CALayer()
        awayTeamBox.frame = CGRect(x: currentX, y: scoreboardY, width: teamBoxWidth, height: scoreboardHeight)
        awayTeamBox.backgroundColor = awayColor.cgColor
        // Round right corners only
        awayTeamBox.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        awayTeamBox.cornerRadius = 6 * scaleFactor
        addStaticAnimation(to: awayTeamBox, duration: videoDurationSeconds)
        container.addSublayer(awayTeamBox)

        // Away team name
        let awayTeamDisplay = String(firstSnapshot.awayTeam.prefix(10)).uppercased()
        let awayTeamLabel = createTextLayer(
            text: awayTeamDisplay,
            frame: CGRect(x: currentX + 8 * scaleFactor, y: scoreboardY + 12 * scaleFactor, width: teamBoxWidth - 16 * scaleFactor, height: 20 * scaleFactor),
            fontSize: 14 * scaleFactor,
            color: .white,
            alignment: .center
        )
        awayTeamLabel.truncationMode = .end
        addStaticAnimation(to: awayTeamLabel, duration: videoDurationSeconds)
        container.addSublayer(awayTeamLabel)

        debugPrint("✅ Created broadcast-style overlay with \(scoreTimeline.count) keyframes")

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

        // Get initial score from first snapshot
        let initialScore = timeline.first.map { isHome ? $0.homeScore : $0.awayScore } ?? 0
        debugPrint("📊 Score layer (\(isHome ? "home" : "away")): initial=\(initialScore), unique=\(uniqueScores.sorted())")

        // Create a layer for each unique score
        for score in uniqueScores.sorted() {
            let textLayer = CATextLayer()
            textLayer.frame = CGRect(origin: .zero, size: frame.size)
            textLayer.string = "\(score)"
            textLayer.fontSize = fontSize
            textLayer.font = UIFont.boldSystemFont(ofSize: fontSize)
            textLayer.foregroundColor = UIColor.white.cgColor
            textLayer.alignmentMode = .center
            textLayer.contentsScale = 3.0

            // Set initial opacity
            let isInitiallyVisible = (score == initialScore)
            textLayer.opacity = isInitiallyVisible ? 1.0 : 0.0

            // Build keyframes - ONLY when score changes
            var opacityValues: [CGFloat] = []
            var keyTimes: [NSNumber] = []

            // Start at time 0
            opacityValues.append(isInitiallyVisible ? 1.0 : 0.0)
            keyTimes.append(0.0)

            // Track previous score to detect changes
            var previousScore = initialScore

            for snapshot in timeline where snapshot.timestamp > 0 && snapshot.timestamp <= videoDuration {
                let currentScore = isHome ? snapshot.homeScore : snapshot.awayScore

                // Only add keyframe when score changes
                if currentScore != previousScore {
                    let normalizedTime = snapshot.timestamp / videoDuration
                    let opacity: CGFloat = (currentScore == score) ? 1.0 : 0.0

                    opacityValues.append(opacity)
                    keyTimes.append(NSNumber(value: min(normalizedTime, 0.9999)))

                    previousScore = currentScore
                }
            }

            // Final keyframe
            if let lastSnapshot = timeline.last(where: { $0.timestamp <= videoDuration }) {
                let lastScore = isHome ? lastSnapshot.homeScore : lastSnapshot.awayScore
                let finalOpacity: CGFloat = (lastScore == score) ? 1.0 : 0.0
                // Only add if different from last added value
                if opacityValues.last != finalOpacity || keyTimes.last?.doubleValue != 1.0 {
                    opacityValues.append(finalOpacity)
                    keyTimes.append(1.0)
                }
            }

            debugPrint("   Score \(score): \(opacityValues.count) keyframes")

            if opacityValues.count > 1 {
                let animation = CAKeyframeAnimation(keyPath: "opacity")
                animation.values = opacityValues
                animation.keyTimes = keyTimes
                animation.duration = videoDuration
                animation.calculationMode = .discrete
                animation.isRemovedOnCompletion = false
                animation.fillMode = .both
                animation.beginTime = AVCoreAnimationBeginTimeAtZero

                textLayer.add(animation, forKey: "opacity")
            } else {
                // Static layer - add static animation to ensure it renders
                addStaticAnimation(to: textLayer, duration: videoDuration)
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

        // Find unique quarters/halves
        var uniqueQuarters = Set<Int>()
        for snapshot in timeline {
            uniqueQuarters.insert(snapshot.quarter)
        }

        let initialQuarter = timeline.first?.quarter ?? 1
        debugPrint("📊 Quarter layer: initial=H\(initialQuarter), unique=\(uniqueQuarters.sorted())")

        for quarter in uniqueQuarters.sorted() {
            let textLayer = CATextLayer()
            textLayer.frame = CGRect(origin: .zero, size: frame.size)
            textLayer.string = "H\(quarter)"  // Display as H1, H2 for halves
            textLayer.fontSize = fontSize
            textLayer.font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
            textLayer.foregroundColor = UIColor.orange.cgColor
            textLayer.alignmentMode = .center
            textLayer.contentsScale = 3.0

            let isInitiallyVisible = (quarter == initialQuarter)
            textLayer.opacity = isInitiallyVisible ? 1.0 : 0.0

            // Build keyframes - ONLY when quarter changes
            var opacityValues: [CGFloat] = []
            var keyTimes: [NSNumber] = []

            opacityValues.append(isInitiallyVisible ? 1.0 : 0.0)
            keyTimes.append(0.0)

            var previousQuarter = initialQuarter

            for snapshot in timeline where snapshot.timestamp > 0 && snapshot.timestamp <= videoDuration {
                if snapshot.quarter != previousQuarter {
                    let normalizedTime = snapshot.timestamp / videoDuration
                    let opacity: CGFloat = (snapshot.quarter == quarter) ? 1.0 : 0.0

                    opacityValues.append(opacity)
                    keyTimes.append(NSNumber(value: min(normalizedTime, 0.9999)))

                    previousQuarter = snapshot.quarter
                }
            }

            // Final keyframe
            if let lastSnapshot = timeline.last(where: { $0.timestamp <= videoDuration }) {
                let finalOpacity: CGFloat = (lastSnapshot.quarter == quarter) ? 1.0 : 0.0
                if opacityValues.last != finalOpacity || keyTimes.last?.doubleValue != 1.0 {
                    opacityValues.append(finalOpacity)
                    keyTimes.append(1.0)
                }
            }

            debugPrint("   Quarter H\(quarter): \(opacityValues.count) keyframes")

            if opacityValues.count > 1 {
                let animation = CAKeyframeAnimation(keyPath: "opacity")
                animation.values = opacityValues
                animation.keyTimes = keyTimes
                animation.duration = videoDuration
                animation.calculationMode = .discrete
                animation.isRemovedOnCompletion = false
                animation.fillMode = .both
                animation.beginTime = AVCoreAnimationBeginTimeAtZero

                textLayer.add(animation, forKey: "opacity")
            } else {
                addStaticAnimation(to: textLayer, duration: videoDuration)
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

        // Build list of unique clock times in order of first appearance
        var uniqueTimes = [String]()
        var timeSet = Set<String>()
        for snapshot in timeline {
            if !timeSet.contains(snapshot.clockTime) {
                uniqueTimes.append(snapshot.clockTime)
                timeSet.insert(snapshot.clockTime)
            }
        }

        let initialClockTime = timeline.first?.clockTime ?? "0:00"
        debugPrint("📊 Clock layer: \(uniqueTimes.count) unique times, initial=\(initialClockTime)")

        for clockTime in uniqueTimes {
            let textLayer = CATextLayer()
            textLayer.frame = CGRect(origin: .zero, size: frame.size)
            textLayer.string = clockTime
            textLayer.fontSize = fontSize
            textLayer.font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
            textLayer.foregroundColor = UIColor.white.cgColor
            textLayer.alignmentMode = .center
            textLayer.contentsScale = 3.0

            let isInitiallyVisible = (clockTime == initialClockTime)
            textLayer.opacity = isInitiallyVisible ? 1.0 : 0.0

            // Build keyframes - only when clock changes
            var opacityValues: [CGFloat] = []
            var keyTimes: [NSNumber] = []

            opacityValues.append(isInitiallyVisible ? 1.0 : 0.0)
            keyTimes.append(0.0)

            var previousClockTime = initialClockTime

            for snapshot in timeline where snapshot.timestamp > 0 && snapshot.timestamp <= videoDuration {
                if snapshot.clockTime != previousClockTime {
                    let normalizedTime = snapshot.timestamp / videoDuration
                    let opacity: CGFloat = (snapshot.clockTime == clockTime) ? 1.0 : 0.0

                    opacityValues.append(opacity)
                    keyTimes.append(NSNumber(value: min(normalizedTime, 0.9999)))

                    previousClockTime = snapshot.clockTime
                }
            }

            // Final keyframe
            if let lastSnapshot = timeline.last(where: { $0.timestamp <= videoDuration }) {
                let finalOpacity: CGFloat = (lastSnapshot.clockTime == clockTime) ? 1.0 : 0.0
                if opacityValues.last != finalOpacity || keyTimes.last?.doubleValue != 1.0 {
                    opacityValues.append(finalOpacity)
                    keyTimes.append(1.0)
                }
            }

            if opacityValues.count > 1 {
                let animation = CAKeyframeAnimation(keyPath: "opacity")
                animation.values = opacityValues
                animation.keyTimes = keyTimes
                animation.duration = videoDuration
                animation.calculationMode = .discrete
                animation.isRemovedOnCompletion = false
                animation.fillMode = .both
                animation.beginTime = AVCoreAnimationBeginTimeAtZero

                textLayer.add(animation, forKey: "opacity")
            } else {
                addStaticAnimation(to: textLayer, duration: videoDuration)
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

    /// Adds static animations to ensure the layer renders from frame 0 in AVVideoComposition
    private static func addStaticAnimation(to layer: CALayer, duration: TimeInterval) {
        // Explicitly set opacity to 1
        layer.opacity = 1.0

        // Opacity animation
        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = 1.0
        opacityAnim.toValue = 1.0
        opacityAnim.duration = duration
        opacityAnim.beginTime = AVCoreAnimationBeginTimeAtZero
        opacityAnim.isRemovedOnCompletion = false
        opacityAnim.fillMode = .both
        layer.add(opacityAnim, forKey: "staticOpacity")

        // Position animation (forces layer to render from frame 0)
        let positionAnim = CABasicAnimation(keyPath: "position")
        positionAnim.fromValue = layer.position
        positionAnim.toValue = layer.position
        positionAnim.duration = duration
        positionAnim.beginTime = AVCoreAnimationBeginTimeAtZero
        positionAnim.isRemovedOnCompletion = false
        positionAnim.fillMode = .both
        layer.add(positionAnim, forKey: "staticPosition")

        // For text layers, also animate the foregroundColor to ensure text renders
        if layer is CATextLayer {
            let textLayer = layer as! CATextLayer
            let colorAnim = CABasicAnimation(keyPath: "foregroundColor")
            colorAnim.fromValue = textLayer.foregroundColor
            colorAnim.toValue = textLayer.foregroundColor
            colorAnim.duration = duration
            colorAnim.beginTime = AVCoreAnimationBeginTimeAtZero
            colorAnim.isRemovedOnCompletion = false
            colorAnim.fillMode = .both
            layer.add(colorAnim, forKey: "staticColor")
        }
    }

    private static func calculateRenderSize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        let angle = atan2(transform.b, transform.a)
        let degrees = angle * 180 / .pi

        debugPrint("📐 Natural size: \(Int(naturalSize.width))x\(Int(naturalSize.height)), rotation: \(String(format: "%.1f", degrees))°")

        // Apply transform to get display size
        let rect = CGRect(origin: .zero, size: naturalSize)
        let transformedRect = rect.applying(transform)
        let displaySize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))

        debugPrint("📐 Display size after transform: \(Int(displaySize.width))x\(Int(displaySize.height))")

        return displaySize
    }

    private static func calculateCorrectingTransform(for transform: CGAffineTransform, renderSize: CGSize) -> CGAffineTransform {
        let angle = atan2(transform.b, transform.a)
        let degrees = angle * 180 / .pi

        debugPrint("🔄 Video transform: angle=\(String(format: "%.1f", degrees))°, renderSize=\(Int(renderSize.width))x\(Int(renderSize.height))")
        debugPrint("   Transform matrix: a=\(transform.a), b=\(transform.b), c=\(transform.c), d=\(transform.d), tx=\(transform.tx), ty=\(transform.ty)")

        // Portrait upside down (180°)
        if abs(degrees - 180) < 10 || abs(degrees + 180) < 10 {
            debugPrint("   → Portrait upside down")
            return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: renderSize.width, ty: renderSize.height)
        }
        // Landscape right (home button on right, 90°)
        else if abs(degrees - 90) < 10 {
            debugPrint("   → Landscape right (90°)")
            return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: renderSize.height)
        }
        // Landscape left (home button on left, -90° or 270°)
        else if abs(degrees + 90) < 10 || abs(degrees - 270) < 10 {
            debugPrint("   → Landscape left (-90°)")
            return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: renderSize.width, ty: 0)
        }
        // Portrait normal (0°)
        else {
            debugPrint("   → Portrait normal (0°)")
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
