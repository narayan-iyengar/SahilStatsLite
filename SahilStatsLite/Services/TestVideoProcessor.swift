//
//  TestVideoProcessor.swift
//  SahilStatsLite
//
//  Test harness for validating the Skynet vision pipeline
//  on existing video files before integrating into live recording.
//
//  Features:
//  - Reads existing video files (AVAssetReader)
//  - Processes each frame through VideoAnalysisPipeline
//  - Outputs processed video with:
//    - Smart crop/zoom following action probability field
//    - Debug overlay showing detections (optional)
//  - Generates statistics report
//
//  Usage:
//  let processor = TestVideoProcessor()
//  processor.processVideo(
//      inputURL: videoURL,
//      outputURL: outputURL,
//      options: .init(enableDebugOverlay: true)
//  ) { progress in
//      print("Progress: \(progress * 100)%")
//  } completion: { result in
//      switch result {
//      case .success(let stats): print("Done! \(stats)")
//      case .failure(let error): print("Error: \(error)")
//      }
//  }
//

import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import UIKit

// MARK: - Processing Options

struct VideoProcessingOptions {
    /// Enable debug overlay showing detections
    var enableDebugOverlay: Bool = true

    /// Output video resolution (nil = same as input)
    var outputResolution: CGSize? = nil

    /// Apply smart crop/zoom from action probability field
    var enableSmartCrop: Bool = true

    /// Frame processing rate (1 = every frame, 2 = every other frame, etc.)
    var processingRate: Int = 1

    /// Export quality (0-1)
    var exportQuality: Float = 0.8
}

// MARK: - Processing Result

struct VideoProcessingResult {
    let inputURL: URL
    let outputURL: URL
    let statistics: VideoAnalysisPipeline.Statistics
    let processingDuration: TimeInterval
    let inputDuration: TimeInterval
    let framesProcessed: Int
}

// MARK: - Test Video Processor

class TestVideoProcessor {

    // MARK: - Pipeline

    private let pipeline = VideoAnalysisPipeline()

    // MARK: - State

    private var isProcessing = false
    private var shouldCancel = false

    // MARK: - Processing

    /// Process a video file through the Skynet pipeline
    /// - Parameters:
    ///   - inputURL: URL of input video
    ///   - outputURL: URL for output video
    ///   - options: Processing options
    ///   - progressHandler: Called with progress 0-1
    ///   - completion: Called with result or error
    func processVideo(
        inputURL: URL,
        outputURL: URL,
        options: VideoProcessingOptions = VideoProcessingOptions(),
        progressHandler: @escaping (Float) -> Void,
        completion: @escaping (Result<VideoProcessingResult, Error>) -> Void
    ) {
        guard !isProcessing else {
            completion(.failure(ProcessingError.alreadyProcessing))
            return
        }

        isProcessing = true
        shouldCancel = false

        let statsAccumulator = VideoAnalysisPipeline.StatisticsAccumulator()

        pipeline.config.debugMode = options.enableDebugOverlay

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let result = try self.processVideoSync(
                    inputURL: inputURL,
                    outputURL: outputURL,
                    options: options,
                    statsAccumulator: statsAccumulator,
                    progressHandler: progressHandler
                )

                DispatchQueue.main.async {
                    self.isProcessing = false
                    completion(.success(result))
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    completion(.failure(error))
                }
            }
        }
    }

    /// Cancel ongoing processing
    func cancel() {
        shouldCancel = true
    }

    // MARK: - Sync Processing

    private func processVideoSync(
        inputURL: URL,
        outputURL: URL,
        options: VideoProcessingOptions,
        statsAccumulator: VideoAnalysisPipeline.StatisticsAccumulator,
        progressHandler: @escaping (Float) -> Void
    ) throws -> VideoProcessingResult {

        let startTime = Date()

        // Open input video using modern API
        let asset = AVURLAsset(url: inputURL)

        // Load track properties using semaphore for sync context
        // Note: Using semaphore since this runs on background thread
        // and async/await would require restructuring the entire processing pipeline
        var videoTrack: AVAssetTrack?
        var naturalSize: CGSize = .zero
        var transform: CGAffineTransform = .identity
        var fps: Float = 30.0
        var duration: Double = 0

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                duration = CMTimeGetSeconds(try await asset.load(.duration))
                let tracks = try await asset.loadTracks(withMediaType: .video)
                videoTrack = tracks.first
                if let track = videoTrack {
                    naturalSize = try await track.load(.naturalSize)
                    transform = try await track.load(.preferredTransform)
                    fps = try await track.load(.nominalFrameRate)
                }
            } catch {
                // Will fall through with nil videoTrack
            }
            semaphore.signal()
        }
        semaphore.wait()

        guard let videoTrack = videoTrack else {
            throw ProcessingError.noVideoTrack
        }

        let totalFrames = Int(duration * Double(fps))

        debugPrint("🎬 [TestProcessor] Input: \(Int(naturalSize.width))x\(Int(naturalSize.height)) @ \(fps)fps, \(totalFrames) frames")

        // Setup reader
        let reader = try AVAssetReader(asset: asset)

        let readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerSettings)
        readerOutput.alwaysCopiesSampleData = false

        guard reader.canAdd(readerOutput) else {
            throw ProcessingError.cannotAddReaderOutput
        }
        reader.add(readerOutput)

        // Calculate output size
        let outputSize = options.outputResolution ?? CGSize(
            width: abs(naturalSize.width * transform.a + naturalSize.height * transform.c),
            height: abs(naturalSize.width * transform.b + naturalSize.height * transform.d)
        )

        // Setup writer
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let writerSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 10_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: writerSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height)
            ]
        )

        guard writer.canAdd(writerInput) else {
            throw ProcessingError.cannotAddWriterInput
        }
        writer.add(writerInput)

        // Start reading and writing
        guard reader.startReading() else {
            throw ProcessingError.cannotStartReading
        }

        guard writer.startWriting() else {
            throw ProcessingError.cannotStartWriting
        }

        writer.startSession(atSourceTime: .zero)

        // Process frames
        var frameNumber = 0
        var processedFrames = 0
        let ciContext = CIContext()

        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            if shouldCancel {
                reader.cancelReading()
                writer.cancelWriting()
                throw ProcessingError.cancelled
            }

            frameNumber += 1

            // Skip frames based on processing rate
            if frameNumber % options.processingRate != 0 {
                continue
            }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }

            let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

            // Process through pipeline
            let result = pipeline.processFrame(pixelBuffer, timestamp: timestamp)
            statsAccumulator.add(result: result)

            // Create output frame
            let outputBuffer = try createOutputFrame(
                input: pixelBuffer,
                pipelineResult: result,
                outputSize: outputSize,
                options: options,
                context: ciContext
            )

            // Wait for writer to be ready
            while !writerInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }

            // Write frame
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            adaptor.append(outputBuffer, withPresentationTime: presentationTime)

            processedFrames += 1

            // Report progress
            let progress = Float(frameNumber) / Float(totalFrames)
            DispatchQueue.main.async {
                progressHandler(progress)
            }
        }

        // Finish writing
        writerInput.markAsFinished()

        let finishGroup = DispatchGroup()
        finishGroup.enter()

        writer.finishWriting {
            finishGroup.leave()
        }

        finishGroup.wait()

        guard writer.status == .completed else {
            throw ProcessingError.writingFailed(writer.error)
        }

        let processingDuration = Date().timeIntervalSince(startTime)

        debugPrint("🎬 [TestProcessor] Complete: \(processedFrames) frames in \(String(format: "%.1f", processingDuration))s")

        return VideoProcessingResult(
            inputURL: inputURL,
            outputURL: outputURL,
            statistics: statsAccumulator.getStatistics(),
            processingDuration: processingDuration,
            inputDuration: duration,
            framesProcessed: processedFrames
        )
    }

    // MARK: - Frame Creation

    private func createOutputFrame(
        input: CVPixelBuffer,
        pipelineResult: PipelineResult,
        outputSize: CGSize,
        options: VideoProcessingOptions,
        context: CIContext
    ) throws -> CVPixelBuffer {

        let inputWidth = CGFloat(CVPixelBufferGetWidth(input))
        let inputHeight = CGFloat(CVPixelBufferGetHeight(input))

        // Create CIImage from input
        var ciImage = CIImage(cvPixelBuffer: input)

        // Apply smart crop/zoom if enabled
        if options.enableSmartCrop {
            let focusPoint = pipelineResult.recommendedFocusPoint
            let zoom = pipelineResult.recommendedZoom

            // Calculate crop rect centered on focus point
            let cropWidth = inputWidth / zoom
            let cropHeight = inputHeight / zoom

            let cropX = (focusPoint.x * inputWidth) - (cropWidth / 2)
            let cropY = ((1 - focusPoint.y) * inputHeight) - (cropHeight / 2)  // Flip Y

            var cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)

            // Clamp to input bounds
            cropRect.origin.x = max(0, min(inputWidth - cropWidth, cropRect.origin.x))
            cropRect.origin.y = max(0, min(inputHeight - cropHeight, cropRect.origin.y))

            ciImage = ciImage.cropped(to: cropRect)

            // Scale to output size
            let scaleX = outputSize.width / cropRect.width
            let scaleY = outputSize.height / cropRect.height
            ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            ciImage = ciImage.transformed(by: CGAffineTransform(translationX: -cropRect.origin.x * scaleX, y: -cropRect.origin.y * scaleY))
        }

        // Add debug overlay if enabled
        if options.enableDebugOverlay {
            ciImage = addDebugOverlay(
                to: ciImage,
                pipelineResult: pipelineResult,
                outputSize: outputSize
            )
        }

        // Create output pixel buffer
        var outputBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(outputSize.width),
            Int(outputSize.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &outputBuffer
        )

        guard let output = outputBuffer else {
            throw ProcessingError.cannotCreateOutputBuffer
        }

        // Render to output
        context.render(ciImage, to: output)

        return output
    }

    // MARK: - Debug Overlay

    private func addDebugOverlay(
        to image: CIImage,
        pipelineResult: PipelineResult,
        outputSize: CGSize
    ) -> CIImage {

        // Create overlay using UIGraphics
        let renderer = UIGraphicsImageRenderer(size: outputSize)

        let overlayImage = renderer.image { ctx in
            let context = ctx.cgContext

            // Semi-transparent background for text
            context.setFillColor(UIColor.black.withAlphaComponent(0.5).cgColor)
            context.fill(CGRect(x: 10, y: 10, width: 300, height: 120))

            // Text attributes
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .medium),
                .foregroundColor: UIColor.white
            ]

            // Draw status text
            let status = """
            Frame: \(pipelineResult.frameNumber)
            State: \(pipelineResult.gameState.emoji) \(pipelineResult.gameState.rawValue)
            Ball: \(pipelineResult.ball != nil ? "✓ Tracking" : "✗ Lost")
            Players: \(pipelineResult.players.count)
            Zoom: \(String(format: "%.2f", pipelineResult.recommendedZoom))x
            """

            (status as NSString).draw(at: CGPoint(x: 15, y: 15), withAttributes: textAttrs)

            // Draw focus point crosshair
            let focusX = pipelineResult.recommendedFocusPoint.x * outputSize.width
            let focusY = pipelineResult.recommendedFocusPoint.y * outputSize.height

            context.setStrokeColor(UIColor.cyan.cgColor)
            context.setLineWidth(2)

            // Horizontal line
            context.move(to: CGPoint(x: focusX - 20, y: focusY))
            context.addLine(to: CGPoint(x: focusX + 20, y: focusY))

            // Vertical line
            context.move(to: CGPoint(x: focusX, y: focusY - 20))
            context.addLine(to: CGPoint(x: focusX, y: focusY + 20))

            context.strokePath()

            // Draw ball position if detected
            if let ball = pipelineResult.ball {
                let ballX = ball.position.x * outputSize.width
                let ballY = ball.position.y * outputSize.height
                let radius = ball.radius * outputSize.width

                context.setStrokeColor(UIColor.orange.cgColor)
                context.setLineWidth(3)
                context.addEllipse(in: CGRect(
                    x: ballX - radius,
                    y: ballY - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.strokePath()

                // Draw predicted position
                let predX = ball.predictedPosition.x * outputSize.width
                let predY = ball.predictedPosition.y * outputSize.height

                context.setStrokeColor(UIColor.yellow.withAlphaComponent(0.5).cgColor)
                context.setLineDash(phase: 0, lengths: [5, 5])
                context.move(to: CGPoint(x: ballX, y: ballY))
                context.addLine(to: CGPoint(x: predX, y: predY))
                context.strokePath()
            }

            // Draw player boxes
            context.setLineDash(phase: 0, lengths: [])
            for player in pipelineResult.players {
                let pos = player.kalman.position
                let boxSize: CGFloat = 40

                let x = pos.x * outputSize.width - boxSize / 2
                let y = pos.y * outputSize.height - boxSize / 2

                // Color by classification
                let color: UIColor
                switch player.classification {
                case .player:
                    color = .green
                case .referee:
                    color = .yellow
                default:
                    color = .gray
                }

                context.setStrokeColor(color.cgColor)
                context.setLineWidth(2)
                context.addRect(CGRect(x: x, y: y, width: boxSize, height: boxSize))
                context.strokePath()
            }

            // Draw court bounds
            let court = pipelineResult.court
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
            context.setLineWidth(1)
            context.addRect(CGRect(
                x: court.bounds.origin.x * outputSize.width,
                y: court.bounds.origin.y * outputSize.height,
                width: court.bounds.width * outputSize.width,
                height: court.bounds.height * outputSize.height
            ))
            context.strokePath()
        }

        // Convert UIImage to CIImage and composite
        guard let cgOverlay = overlayImage.cgImage else {
            return image
        }

        let ciOverlay = CIImage(cgImage: cgOverlay)

        // Composite overlay on top of image
        let composite = ciOverlay.composited(over: image)

        return composite
    }
}

// MARK: - Errors

enum ProcessingError: Error, LocalizedError {
    case alreadyProcessing
    case noVideoTrack
    case cannotAddReaderOutput
    case cannotAddWriterInput
    case cannotStartReading
    case cannotStartWriting
    case cannotCreateOutputBuffer
    case writingFailed(Error?)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .alreadyProcessing:
            return "Video processing is already in progress"
        case .noVideoTrack:
            return "Input video has no video track"
        case .cannotAddReaderOutput:
            return "Cannot add reader output"
        case .cannotAddWriterInput:
            return "Cannot add writer input"
        case .cannotStartReading:
            return "Cannot start reading video"
        case .cannotStartWriting:
            return "Cannot start writing video"
        case .cannotCreateOutputBuffer:
            return "Cannot create output pixel buffer"
        case .writingFailed(let error):
            return "Writing failed: \(error?.localizedDescription ?? "unknown")"
        case .cancelled:
            return "Processing was cancelled"
        }
    }
}
