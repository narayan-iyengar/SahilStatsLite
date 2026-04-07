//
//  StreamingService.swift
//  SahilStatsLite
//
//  PURPOSE: Live YouTube streaming via RTMP using HaishinKit.
//           Passes raw CVPixelBuffers (with score overlay) to HaishinKit's internal
//           VideoCodec (H.264 via VideoToolbox), which also handles the RTMP metadata,
//           sequence header, and FLV framing. Audio CMSampleBuffers go through
//           HaishinKit's AAC encoder.
//
//  SETUP:
//    1. HaishinKit added via SPM (done)
//    2. Settings → YouTube Live → stream key + toggle ON
//
//  YOUTUBE REQUIREMENTS:
//    Endpoint: rtmp://a.rtmp.youtube.com/live2
//    Codec:    H.264 High profile, keyframe every 2s, 6 Mbps
//

import Foundation
import AVFoundation
import Combine
import HaishinKit
import RTMPHaishinKit

// MARK: - Stream Health

enum StreamHealth: Equatable {
    case idle
    case connecting
    case live
    case reconnecting
    case failed(String)

    var label: String {
        switch self {
        case .idle:          return "Not streaming"
        case .connecting:    return "Connecting…"
        case .live:          return "LIVE"
        case .reconnecting:  return "Reconnecting…"
        case .failed(let e): return "Failed: \(e)"
        }
    }

    var isActive: Bool {
        switch self { case .live, .reconnecting: return true; default: return false }
    }
}

// MARK: - Streaming Service

@MainActor
final class StreamingService: ObservableObject {
    static let shared = StreamingService()

    @Published var isStreaming: Bool = false
    @Published var health: StreamHealth = .idle

    static let streamKeyDefaultsKey        = "SahilStats_YouTubeStreamKey"
    static let streamingEnabledDefaultsKey = "SahilStats_StreamingEnabled"

    var savedStreamKey: String {
        get { UserDefaults.standard.string(forKey: Self.streamKeyDefaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.streamKeyDefaultsKey) }
    }

    var streamingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.streamingEnabledDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.streamingEnabledDefaultsKey) }
    }

    // Plain RTMP port 1935. RTMPConnection.swift (DerivedData) patched to:
    // 1. Send minimal FMLE-compatible connect command (4 fields, no Enhanced RTMP)
    // 2. Skip SetChunkSize(8192) — YouTube rejects it; keep default 128-byte chunks
    private let rtmpURL = "rtmp://a.rtmp.youtube.com/live2"

    nonisolated(unsafe) private var stream: RTMPStream?
    private var connection: RTMPConnection?
    private var statusTask: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    func startStream() async {
        guard !savedStreamKey.isEmpty else {
            health = .failed("No stream key — add one in Settings")
            return
        }
        await _start(key: savedStreamKey)
    }

    func stopStream() async {
        statusTask?.cancel()
        statusTask = nil
        if let s = stream { try? await s.close() }
        try? await connection?.close()
        stream = nil
        connection = nil
        isStreaming = false
        health = .idle
    }

    // MARK: - Frame Injection (called from RecordingManager's processingQueue)

    /// Video: wrap CVPixelBuffer (with overlay) in CMSampleBuffer and pass to
    /// HaishinKit's internal H.264 encoder. This populates the onMetaData frame
    /// (width, height, videocodecid) that YouTube needs before it will display video.
    nonisolated func appendVideoBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let stream else { return }

        var formatDesc: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc)
        guard let fd = formatDesc else { return }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: timestamp,
            decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fd,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer)
        guard let sb = sampleBuffer else { return }
        Task { await stream.append(sb) }
    }

    /// Audio: pass directly to HaishinKit's AAC encoder
    nonisolated func appendAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let stream else { return }
        Task { await stream.append(sampleBuffer) }
    }

    // MARK: - HaishinKit RTMP

    private func _start(key: String) async {
        health = .connecting
        isStreaming = true

        let conn = RTMPConnection()
        let strm = RTMPStream(connection: conn)

        self.connection = conn
        // self.stream is set AFTER connect + publish + codec config so that
        // appendVideoBuffer returns early (guard stream != nil) during setup.
        // YouTube closes the connection if media arrives before _result is sent.

        statusTask = Task { [weak self] in
            for await status in await strm.status {
                guard let self else { break }
                debugPrint("[Stream] STATUS code=\(status.code) level=\(status.level)")
                await MainActor.run {
                    switch status.code {
                    case RTMPStream.Code.publishStart.rawValue:
                        self.health = .live
                        debugPrint("[Stream] 🔴 LIVE → YouTube")
                    case RTMPStream.Code.publishBadName.rawValue:
                        self.health = .failed("Invalid stream key")
                    default:
                        break
                    }
                }
            }
        }

        do {
            debugPrint("[Stream] Connecting to \(rtmpURL)...")
            let connectResp = try await conn.connect(rtmpURL)
            debugPrint("[Stream] Connected — \(connectResp.status?.code ?? "?")")

            debugPrint("[Stream] Publishing with key \(key.prefix(8))...")
            _ = try await strm.publish(key)
            debugPrint("[Stream] Publish accepted — configuring codecs")

            // Video: 1080p H.264 High profile, 6 Mbps, 30fps
            // HaishinKit will scale the 4K input to 1920×1080 and encode
            try? await strm.setVideoSettings(VideoCodecSettings(
                videoSize: CGSize(width: 1920, height: 1080),
                bitRate: 6_000_000))

            // Audio: AAC 128kbps
            try? await strm.setAudioSettings(AudioCodecSettings(bitRate: 128_000))

            // Expose stream — frames now accepted and encoded by HaishinKit
            self.stream = strm
            debugPrint("[Stream] 🔴 stream live — HaishinKit encoding at 1080p/6Mbps")

        } catch let e as RTMPConnection.Error {
            let detail: String
            switch e {
            case .invalidState:              detail = "RTMPConn.invalidState"
            case .unsupportedCommand(let c): detail = "RTMPConn.unsupportedCommand(\(c))"
            case .connectionTimedOut:        detail = "RTMPConn.connectionTimedOut"
            case .socketErrorOccurred(let s): detail = "RTMPConn.socketError: \(s?.localizedDescription ?? "nil")"
            case .requestTimedOut:           detail = "RTMPConn.requestTimedOut"
            case .requestFailed(let r):
                let s = r.status
                detail = "RTMPConn.requestFailed code=\(s?.code ?? "?") desc=\(s?.description ?? "?")"
            }
            health = .failed(detail)
            isStreaming = false
            self.stream = nil
            debugPrint("[Stream] ❌ \(detail)")
        } catch {
            let detail = "unexpected: \(error)"
            health = .failed(detail)
            isStreaming = false
            self.stream = nil
            debugPrint("[Stream] ❌ \(detail)")
        }
    }
}
