//
//  YOLODetector.swift
//  SahilStatsLite
//
//  PURPOSE: YOLOv8n CoreML person detector. Replaces VNDetectHumanRectanglesRequest
//           with a sports-optimized model that handles overlapping players, partial
//           occlusion, and crowd interference far better than Apple's generic detector.
//           Falls back gracefully if the model file is absent from the bundle.
//
//  MODEL SETUP (run once on personal Mac):
//    pip install ultralytics
//    python3 -c "
//      from ultralytics import YOLO
//      YOLO('yolov8n.pt').export(format='coreml', imgsz=640, nms=False)
//    "
//    Then drag yolov8n.mlpackage into Xcode → SahilStatsLite target.
//    Xcode compiles it to yolov8n.mlmodelc at build time.
//
//  MODEL FORMAT:
//    Input:  'image'   CVPixelBuffer 640×640
//    Output: MLMultiArray shape [1, 84, 8400] — supports [1, 8400, 84] transposed too
//            84 = 4 box coords (cx,cy,w,h normalized) + 80 COCO class scores
//            COCO class 0 = person
//
//  COORDINATE SYSTEMS:
//    YOLO output: normalized in 640×640 input space, y=0 at TOP (image convention)
//    Vision/PersonClassifier: normalized, y=0 at BOTTOM (CGRect convention)
//    This file handles all transforms between them.
//
//  DEPENDS ON: CoreML, CoreImage
//

import CoreML
import CoreImage
import CoreGraphics

final class YOLODetector {

    // MARK: - Types

    struct Detection {
        /// Bounding box in Vision/CGRect convention: normalized [0,1], y=0 at bottom.
        let boundingBox: CGRect
        let confidence: Float
    }

    // MARK: - Config

    private let confidenceThreshold: Float = 0.35
    private let iouThreshold: Float = 0.45
    private let personClassCOCO = 0   // COCO class 0 = person

    // Our AI frames are 640×360. YOLO expects 640×640.
    // We letterbox by adding 140px gray bars top and bottom (no horizontal padding).
    // These constants are precomputed for the fixed 640×360 AI frame size.
    private let inputW: CGFloat = 640
    private let inputH: CGFloat = 640
    private let origW:  CGFloat = 640
    private let origH:  CGFloat = 360
    private let padTop: CGFloat = 140   // (640 - 360) / 2

    // Scale factor from 640×640 normalized to 640×360 normalized (y axis only)
    // cy_orig = cy_640 * scaleY - padTopOrigNorm
    // h_orig  = h_640  * scaleY
    private lazy var scaleY: CGFloat = inputH / origH          // 640/360 ≈ 1.778
    private lazy var padTopOrigNorm: CGFloat = padTop / origH  // 140/360 ≈ 0.389

    // MARK: - State

    private var model: MLModel?
    // Reuse CIContext and pixel buffer pool across frames.
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var letterboxPool: CVPixelBufferPool?

    var isAvailable: Bool { model != nil }

    // MARK: - Init

    init() {
        loadModel()
        setupLetterboxPool()
    }

    private func loadModel() {
        // Xcode compiles .mlpackage → .mlmodelc at build time; prefer the compiled form.
        let url = Bundle.main.url(forResource: "yolov8n", withExtension: "mlmodelc")
                  ?? Bundle.main.url(forResource: "yolov8n", withExtension: "mlpackage")

        guard let modelURL = url else {
            debugPrint("""
            [YOLO] ⚠️  Model not found — falling back to VNDetectHumanRectanglesRequest.
                   To enable YOLO: run the Python commands in this file's header, then
                   drag yolov8n.mlpackage into the Xcode project (SahilStatsLite target).
            """)
            return
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all   // Prefer Neural Engine, fall back to GPU/CPU
            model = try MLModel(contentsOf: modelURL, configuration: config)
            debugPrint("[YOLO] ✅ YOLOv8n loaded: \(modelURL.lastPathComponent)")
        } catch {
            debugPrint("[YOLO] ❌ Load failed: \(error.localizedDescription)")
        }
    }

    private func setupLetterboxPool() {
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey:           Int(inputW),
            kCVPixelBufferHeightKey:          Int(inputH),
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &letterboxPool)
    }

    // MARK: - Detection Entry Point

    /// Detect people in a 640×360 CVPixelBuffer (RecordingManager's AI frame size).
    /// Returns bounding boxes in Vision coords (normalized, y=0 at bottom).
    func detect(in pixelBuffer: CVPixelBuffer) -> [Detection] {
        guard let model = model else { return [] }
        guard let letterboxed = createLetterboxBuffer(from: pixelBuffer) else { return [] }
        guard let output = runInference(model: model, pixelBuffer: letterboxed) else { return [] }
        return decode(output)
    }

    // MARK: - Letterboxing

    /// Pad 640×360 → 640×640 with 140px gray bars top and bottom.
    /// Standard YOLO letterbox: fill color is (114,114,114) / 255.
    private func createLetterboxBuffer(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let src = CIImage(cvPixelBuffer: pixelBuffer)

        // CIImage origin is bottom-left. Translating by +padTop moves the frame UP,
        // which places it in the middle of the 640×640 canvas.
        let framed = src.transformed(by: CGAffineTransform(translationX: 0, y: padTop))
        let background = CIImage(color: CIColor(red: 114/255, green: 114/255, blue: 114/255))
            .cropped(to: CGRect(x: 0, y: 0, width: inputW, height: inputH))
        let composite = framed.composited(over: background)

        var outBuffer: CVPixelBuffer?
        if let pool = letterboxPool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outBuffer)
        }
        guard let out = outBuffer else { return nil }

        ciContext.render(composite, to: out)
        return out
    }

    // MARK: - Inference

    private func runInference(model: MLModel, pixelBuffer: CVPixelBuffer) -> MLMultiArray? {
        do {
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "image": MLFeatureValue(pixelBuffer: pixelBuffer)
            ])
            let output = try model.prediction(from: input)

            // Find the detection output by shape: [1, 84, N] or [1, N, 84]
            for name in output.featureNames {
                if let ma = output.featureValue(for: name)?.multiArrayValue,
                   ma.shape.count == 3,
                   ma.shape.map({ $0.intValue }).contains(84) {
                    return ma
                }
            }
            debugPrint("[YOLO] ⚠️ Could not find detection tensor in model output")
            return nil
        } catch {
            debugPrint("[YOLO] Inference error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Decoding

    private func decode(_ output: MLMultiArray) -> [Detection] {
        let shape = output.shape.map { $0.intValue }
        guard shape.count == 3 else { return [] }

        // Support both [1, 84, N] (standard) and [1, N, 84] (transposed) layouts.
        let isTransposed = shape[1] != 84
        let numAnchors   = isTransposed ? shape[1] : shape[2]
        let strides      = output.strides.map { $0.intValue }
        let featureStride = isTransposed ? strides[2] : strides[1]
        let anchorStride  = isTransposed ? strides[1] : strides[2]

        // Direct pointer access (Float32). Export model without `half=True` to ensure FP32.
        let ptr = output.dataPointer.assumingMemoryBound(to: Float32.self)

        var boxes:  [CGRect] = []
        var scores: [Float]  = []

        for a in 0..<numAnchors {
            // Person score (COCO class 0 = feature index 4)
            let personScore = ptr[4 * featureStride + a * anchorStride]
            guard personScore >= confidenceThreshold else { continue }

            // Box coords in normalized 640×640 space, y=0 at TOP (YOLO convention)
            let cx_640 = CGFloat(ptr[0 * featureStride + a * anchorStride])
            let cy_640 = CGFloat(ptr[1 * featureStride + a * anchorStride])
            let w_640  = CGFloat(ptr[2 * featureStride + a * anchorStride])
            let h_640  = CGFloat(ptr[3 * featureStride + a * anchorStride])

            // Reverse letterbox: recover 640×360 normalized coords (still y=0 top)
            // cx unchanged — no horizontal padding
            let cx_orig    = cx_640
            let cy_top_360 = cy_640 * scaleY - padTopOrigNorm
            let w_orig     = w_640
            let h_orig     = h_640 * scaleY

            // Filter boxes centered mostly in the padding regions (outside actual frame)
            guard cy_top_360 > -0.15 && cy_top_360 < 1.15 else { continue }

            // Convert YOLO top-origin (y=0 top) → Vision bottom-origin (y=0 bottom)
            // Vision CGRect: origin = bottom-left corner of the box
            let visionCy = 1.0 - cy_top_360
            let visionBox = CGRect(
                x: cx_orig - w_orig / 2,
                y: visionCy  - h_orig / 2,
                width:  w_orig,
                height: h_orig
            )

            boxes.append(visionBox)
            scores.append(personScore)
        }

        guard !boxes.isEmpty else { return [] }

        return nms(boxes: boxes, scores: scores).map {
            Detection(boundingBox: boxes[$0], confidence: scores[$0])
        }
    }

    // MARK: - Non-Maximum Suppression

    private func nms(boxes: [CGRect], scores: [Float]) -> [Int] {
        var sorted = scores.indices.sorted { scores[$0] > scores[$1] }
        var result: [Int] = []
        while !sorted.isEmpty {
            let best = sorted.removeFirst()
            result.append(best)
            sorted = sorted.filter { iou(boxes[best], boxes[$0]) < iouThreshold }
        }
        return result
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let inter = a.intersection(b)
        guard !inter.isNull else { return 0 }
        let ia = Float(inter.width * inter.height)
        let ua = Float(a.width * a.height + b.width * b.height) - ia
        return ua > 0 ? ia / ua : 0
    }
}
