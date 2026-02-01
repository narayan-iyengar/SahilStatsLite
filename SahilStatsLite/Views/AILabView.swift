//
//  AILabView.swift
//  SahilStatsLite
//
//  Experimental AI features - Skynet mode with player detection and heat maps
//

import SwiftUI
import AVFoundation
import Vision

struct AILabView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var recordingManager = RecordingManager.shared
    @State private var isProcessing = false
    @State private var detectedPlayers: [CGRect] = []
    @State private var heatMap: [[Int]] = []
    @State private var showHeatMap = true
    @State private var showBoundingBoxes = true
    @State private var framesProcessed = 0
    @State private var lastDetectionTime: String = ""

    private let heatMapRows = 20
    private let heatMapCols = 30

    // Vision request for human detection
    private let humanDetectionRequest: VNDetectHumanRectanglesRequest = {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        return request
    }()

    var body: some View {
        ZStack {
            // Camera preview
            if recordingManager.isSessionReady, let session = recordingManager.captureSession {
                CameraPreviewView(session: session)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                    .overlay(
                        VStack {
                            ProgressView()
                                .tint(.white)
                            Text("Starting camera...")
                                .foregroundColor(.white)
                                .padding(.top)
                        }
                    )
            }

            // Heat map overlay
            if showHeatMap && !heatMap.isEmpty {
                heatMapOverlay
                    .opacity(0.4)
            }

            // Bounding boxes
            if showBoundingBoxes {
                GeometryReader { geo in
                    ForEach(0..<detectedPlayers.count, id: \.self) { index in
                        let rect = detectedPlayers[index]
                        let frame = CGRect(
                            x: rect.minX * geo.size.width,
                            y: (1 - rect.maxY) * geo.size.height,
                            width: rect.width * geo.size.width,
                            height: rect.height * geo.size.height
                        )
                        Rectangle()
                            .stroke(Color.green, lineWidth: 2)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
            }

            // Top bar
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Text("AI LAB")
                        .font(.headline)
                        .foregroundColor(.orange)

                    Spacer()

                    // Placeholder for symmetry
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.clear)
                }
                .padding()

                Spacer()
            }

            // Bottom controls
            VStack {
                Spacer()

                HStack(spacing: 20) {
                    // Heat map toggle
                    Toggle(isOn: $showHeatMap) {
                        Label("Heat Map", systemImage: "flame.fill")
                    }
                    .toggleStyle(.button)
                    .tint(showHeatMap ? .orange : .gray)

                    // Bounding boxes toggle
                    Toggle(isOn: $showBoundingBoxes) {
                        Label("Players", systemImage: "person.fill")
                    }
                    .toggleStyle(.button)
                    .tint(showBoundingBoxes ? .green : .gray)
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .padding()

                // Stats
                VStack(spacing: 4) {
                    Text("Players detected: \(detectedPlayers.count)")
                        .font(.caption)
                        .foregroundColor(.white)
                    Text("Frames: \(framesProcessed) | \(lastDetectionTime)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.bottom)
            }
        }
        .task {
            await setupAndStartDetection()
        }
        .onDisappear {
            stopDetection()
        }
    }

    // MARK: - Heat Map Overlay

    private var heatMapOverlay: some View {
        GeometryReader { geo in
            let cellWidth = geo.size.width / CGFloat(heatMapCols)
            let cellHeight = geo.size.height / CGFloat(heatMapRows)

            Canvas { context, size in
                for row in 0..<heatMapRows {
                    for col in 0..<heatMapCols {
                        if row < heatMap.count && col < heatMap[row].count {
                            let value = heatMap[row][col]
                            if value > 0 {
                                let intensity = min(Double(value) / 50.0, 1.0)
                                let color = Color(
                                    red: intensity,
                                    green: 0,
                                    blue: 1.0 - intensity
                                )

                                let rect = CGRect(
                                    x: CGFloat(col) * cellWidth,
                                    y: CGFloat(row) * cellHeight,
                                    width: cellWidth,
                                    height: cellHeight
                                )

                                context.fill(Path(rect), with: .color(color))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Detection

    private func setupAndStartDetection() async {
        // Initialize heat map
        heatMap = Array(repeating: Array(repeating: 0, count: heatMapCols), count: heatMapRows)

        // Setup camera if not already ready
        if !recordingManager.isSessionReady {
            await recordingManager.requestPermissionsAndSetup()
        }

        // Set up the AI frame callback
        recordingManager.onFrameForAI = { [self] pixelBuffer in
            processFrame(pixelBuffer)
        }

        isProcessing = true
        debugPrint("[AILab] Detection started")
    }

    private func stopDetection() {
        isProcessing = false
        recordingManager.onFrameForAI = nil
        debugPrint("[AILab] Detection stopped")
    }

    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isProcessing else { return }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Create Vision request handler
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            // Run human detection
            try handler.perform([humanDetectionRequest])

            // Get results
            let results = humanDetectionRequest.results ?? []
            let rects = results.map { $0.boundingBox }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            // Update UI on main thread
            DispatchQueue.main.async {
                self.detectedPlayers = rects
                self.framesProcessed += 1
                self.lastDetectionTime = String(format: "%.0fms", elapsed * 1000)

                // Update heat map
                self.updateHeatMap(with: rects)
            }
        } catch {
            debugPrint("[AILab] Vision error: \(error)")
        }
    }

    private func updateHeatMap(with rects: [CGRect]) {
        for rect in rects {
            let col = Int(rect.midX * CGFloat(heatMapCols))
            let row = Int((1 - rect.midY) * CGFloat(heatMapRows))

            if row >= 0 && row < heatMapRows && col >= 0 && col < heatMapCols {
                heatMap[row][col] += 1
            }
        }
    }
}

#Preview {
    AILabView()
}
