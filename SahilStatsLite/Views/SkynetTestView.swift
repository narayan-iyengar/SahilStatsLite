//
//  SkynetTestView.swift
//  SahilStatsLite
//
//  Standalone test UI for validating the Skynet vision pipeline
//  on existing video files. Does NOT affect the main app flow.
//
//  Access: Can be shown from a debug menu or launched separately
//

import SwiftUI
import PhotosUI
import AVKit

struct SkynetTestView: View {

    // MARK: - State

    @State private var selectedVideoItem: PhotosPickerItem? = nil
    @State private var inputVideoURL: URL? = nil
    @State private var outputVideoURL: URL? = nil

    @State private var isProcessing = false
    @State private var progress: Float = 0
    @State private var statusMessage = "Select a video to test Skynet"

    @State private var processingResult: VideoProcessingResult? = nil
    @State private var errorMessage: String? = nil

    @State private var showOutputVideo = false

    // MARK: - Processor

    private let processor = TestVideoProcessor()

    // MARK: - Options

    @State private var enableDebugOverlay = true
    @State private var enableSmartCrop = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // Header
                    headerSection

                    // Video Selection
                    videoSelectionSection

                    // Options
                    optionsSection

                    // Process Button
                    processButtonSection

                    // Progress
                    if isProcessing {
                        progressSection
                    }

                    // Results
                    if let result = processingResult {
                        resultsSection(result)
                    }

                    // Error
                    if let error = errorMessage {
                        errorSection(error)
                    }

                    Spacer(minLength: 50)
                }
                .padding()
            }
            .navigationTitle("Skynet Lab")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showOutputVideo) {
                if let url = outputVideoURL {
                    VideoPlayerSheet(url: url)
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Skynet Vision Pipeline")
                .font(.title2.bold())

            Text("Test the AI tracking on existing videos")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical)
    }

    // MARK: - Video Selection

    private var videoSelectionSection: some View {
        VStack(spacing: 12) {
            PhotosPicker(
                selection: $selectedVideoItem,
                matching: .videos,
                photoLibrary: .shared()
            ) {
                HStack {
                    Image(systemName: inputVideoURL != nil ? "checkmark.circle.fill" : "video.badge.plus")
                        .font(.title2)

                    Text(inputVideoURL != nil ? "Video Selected" : "Select Video from Photos")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(inputVideoURL != nil ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(inputVideoURL != nil ? Color.green : Color.blue, lineWidth: 1)
                )
            }
            .onChange(of: selectedVideoItem) { _, newValue in
                loadVideo(from: newValue)
            }

            if let url = inputVideoURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Options Section

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Options")
                .font(.headline)

            Toggle(isOn: $enableDebugOverlay) {
                VStack(alignment: .leading) {
                    Text("Debug Overlay")
                        .font(.subheadline)
                    Text("Show ball tracking, player boxes, focus point")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .purple))

            Toggle(isOn: $enableSmartCrop) {
                VStack(alignment: .leading) {
                    Text("Smart Crop/Zoom")
                        .font(.subheadline)
                    Text("Apply action-based automatic zoom")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .purple))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    // MARK: - Process Button

    private var processButtonSection: some View {
        Button(action: startProcessing) {
            HStack {
                if isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "play.fill")
                }

                Text(isProcessing ? "Processing..." : "Run Skynet Analysis")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(canProcess ? Color.purple : Color.gray)
            )
            .foregroundColor(.white)
        }
        .disabled(!canProcess)
    }

    private var canProcess: Bool {
        inputVideoURL != nil && !isProcessing
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress) {
                Text(statusMessage)
                    .font(.caption)
            }
            .progressViewStyle(LinearProgressViewStyle(tint: .purple))

            Text("\(Int(progress * 100))%")
                .font(.title2.monospacedDigit().bold())
                .foregroundColor(.purple)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    // MARK: - Results Section

    private func resultsSection(_ result: VideoProcessingResult) -> some View {
        VStack(spacing: 16) {
            // Success header
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)

                Text("Processing Complete")
                    .font(.headline)

                Spacer()
            }

            // Stats grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(
                    title: "Frames",
                    value: "\(result.framesProcessed)",
                    icon: "film"
                )

                StatCard(
                    title: "Duration",
                    value: String(format: "%.1fs", result.processingDuration),
                    icon: "clock"
                )

                StatCard(
                    title: "Ball Detection",
                    value: String(format: "%.0f%%", result.statistics.ballDetectionRate * 100),
                    icon: "sportscourt"
                )

                StatCard(
                    title: "Avg Players",
                    value: String(format: "%.1f", result.statistics.avgPlayerCount),
                    icon: "person.3"
                )
            }

            // Game state breakdown
            if !result.statistics.gameStateBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Game States Detected")
                        .font(.subheadline.bold())

                    ForEach(Array(result.statistics.gameStateBreakdown.keys), id: \.self) { state in
                        if let count = result.statistics.gameStateBreakdown[state] {
                            HStack {
                                Text("\(state.emoji) \(state.rawValue)")
                                Spacer()
                                Text("\(count) frames")
                                    .foregroundColor(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                )
            }

            // View Output Button
            Button(action: { showOutputVideo = true }) {
                HStack {
                    Image(systemName: "play.rectangle.fill")
                    Text("View Processed Video")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue)
                )
                .foregroundColor(.white)
            }

            // Share Button
            if let url = outputVideoURL {
                ShareLink(item: url) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Video")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue, lineWidth: 1)
                    )
                    .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    // MARK: - Error Section

    private func errorSection(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)

            Text(error)
                .font(.caption)
                .foregroundColor(.red)

            Spacer()

            Button("Dismiss") {
                errorMessage = nil
            }
            .font(.caption)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
        )
    }

    // MARK: - Actions

    private func loadVideo(from item: PhotosPickerItem?) {
        guard let item = item else { return }

        statusMessage = "Loading video..."

        item.loadTransferable(type: VideoTransferable.self) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let video):
                    if let video = video {
                        self.inputVideoURL = video.url
                        self.statusMessage = "Video loaded - ready to process"
                        self.processingResult = nil
                        self.errorMessage = nil
                    }
                case .failure(let error):
                    self.errorMessage = "Failed to load video: \(error.localizedDescription)"
                }
            }
        }
    }

    private func startProcessing() {
        guard let inputURL = inputVideoURL else { return }

        isProcessing = true
        progress = 0
        processingResult = nil
        errorMessage = nil
        statusMessage = "Initializing pipeline..."

        // Create output URL
        let outputFileName = "skynet_\(UUID().uuidString.prefix(8)).mp4"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName)
        self.outputVideoURL = outputURL

        let options = VideoProcessingOptions(
            enableDebugOverlay: enableDebugOverlay,
            enableSmartCrop: enableSmartCrop
        )

        processor.processVideo(
            inputURL: inputURL,
            outputURL: outputURL,
            options: options,
            progressHandler: { newProgress in
                DispatchQueue.main.async {
                    self.progress = newProgress
                    self.statusMessage = "Processing frame \(Int(newProgress * 100))%..."
                }
            },
            completion: { result in
                DispatchQueue.main.async {
                    self.isProcessing = false

                    switch result {
                    case .success(let processingResult):
                        self.processingResult = processingResult
                        self.statusMessage = "Complete!"
                    case .failure(let error):
                        self.errorMessage = error.localizedDescription
                        self.statusMessage = "Failed"
                    }
                }
            }
        )
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(.purple)

            Text(value)
                .font(.title3.bold())

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
        )
    }
}

// MARK: - Video Player Sheet

private struct VideoPlayerSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea()
                .navigationTitle("Processed Video")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

// MARK: - Video Transferable

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            // Copy to temp location
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("input_\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return VideoTransferable(url: tempURL)
        }
    }
}

// MARK: - Preview

#Preview {
    SkynetTestView()
}
