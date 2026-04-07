//
//  StreamingService.swift
//  SahilStatsLite
//
//  PURPOSE: Live YouTube streaming via RTMP using HaishinKit.
//           Pre-encodes video frames to H.264 via VideoToolbox (VTCompressionSession),
//           then forwards compressed samples to HaishinKit which sends them over RTMP.
//           Audio goes directly through HaishinKit's AAC encoder.
//
//  Why VTCompressionSession instead of HaishinKit's encoder:
//    HaishinKit's custom frame injection API (actor-based append) doesn't reliably
//    route uncompressed BGRA frames through its internal VideoCodec in all versions.
//    Pre-encoding with VT gives us direct control and guaranteed H.264 output.
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
import VideoToolbox
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

    // YouTube RTMPS on port 443 (not 1935). Port must be explicit or HaishinKit
    // defaults to 1935 for both rtmp:// and rtmps://, causing TLS connection failure.
    // Connect to actual RTMP ingest server a.rtmp.youtube.com, but override TLS SNI
    // to rtmps.youtube.com (the cert CN). This satisfies iOS 26 hostname validation
    // while routing to the correct RTMP server.
    private let rtmpURL = "rtmps://a.rtmp.youtube.com/live2"

    nonisolated(unsafe) private var stream: RTMPStream?
    private var connection: RTMPConnection?
    private var statusTask: Task<Void, Never>?

    // VideoToolbox H.264 encoder — we pre-encode BGRA frames before sending to HaishinKit
    nonisolated(unsafe) private var vtSession: VTCompressionSession?
    nonisolated(unsafe) private var frameCount: Int64 = 0

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
        destroyCompressor()
        isStreaming = false
        health = .idle
    }

    // MARK: - Frame Injection (called from RecordingManager's processingQueue)

    /// Video: pre-encode with VTCompressionSession → forward H.264 to HaishinKit
    nonisolated func appendVideoBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard stream != nil else { return }

        // Lazily create the VT encoder on first frame so we know the real dimensions
        if vtSession == nil {
            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            setupCompressor(width: w, height: h)
        }
        guard let session = vtSession else { return }

        frameCount += 1
        let isKeyFrame = frameCount % 60 == 1   // Force keyframe every ~2s at 30fps

        var frameProps: CFDictionary? = nil
        if isKeyFrame {
            frameProps = [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
        }

        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: timestamp,
            duration: CMTime(value: 1, timescale: 30),
            frameProperties: frameProps,
            infoFlagsOut: nil,
            outputHandler: { [weak self] status, _, sampleBuffer in
                guard let self,
                      let sb = sampleBuffer,
                      status == noErr else { return }
                Task { await self.stream?.append(sb) }
            }
        )
    }

    /// Audio: pass directly to HaishinKit's AAC encoder
    nonisolated func appendAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let stream else { return }
        Task { await stream.append(sampleBuffer) }
    }

    // MARK: - VTCompressionSession

    nonisolated private func setupCompressor(width: Int, height: Int) {
        // Target 1080p — scale down if source is 4K
        let outW = min(width, 1920)
        let outH = min(height, 1080)

        var session: VTCompressionSession?
        VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(outW),
            height: Int32(outH),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        guard let session else { return }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime,                    value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,              value: NSNumber(value: 6_000_000))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 2.0))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,                value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering,        value: kCFBooleanFalse)

        VTCompressionSessionPrepareToEncodeFrames(session)
        vtSession = session
        debugPrint("[Stream] VT H.264 encoder ready (\(outW)×\(outH))")
    }

    nonisolated private func destroyCompressor() {
        if let session = vtSession {
            VTCompressionSessionInvalidate(session)
            vtSession = nil
        }
        frameCount = 0
    }

    // MARK: - HaishinKit RTMP

    private func _start(key: String) async {
        health = .connecting
        isStreaming = true

        let conn = RTMPConnection()
        let strm = RTMPStream(connection: conn)

        self.connection = conn
        self.stream = strm

        statusTask = Task { [weak self] in
            for await status in await strm.status {
                guard let self else { break }
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
            _ = try await conn.connect(rtmpURL)
            debugPrint("[Stream] Connected — publishing with key \(key.prefix(8))...")
            _ = try await strm.publish(key)
            debugPrint("[Stream] Published")

            // Audio settings only — video is pre-encoded by VTCompressionSession
            try? await strm.setAudioSettings(AudioCodecSettings(bitRate: 128_000))

        } catch let e as RTMPConnection.Error {
            let detail: String
            switch e {
            case .invalidState:              detail = "RTMPConn.invalidState"
            case .unsupportedCommand(let c): detail = "RTMPConn.unsupportedCommand(\(c))"
            case .connectionTimedOut:        detail = "RTMPConn.connectionTimedOut"
            case .socketErrorOccurred(let s): detail = "RTMPConn.socketError: \(s?.localizedDescription ?? "nil")"
            case .requestTimedOut:           detail = "RTMPConn.requestTimedOut"
            case .requestFailed(let r):      detail = "RTMPConn.requestFailed: \(r)"
            }
            health = .failed(detail)
            isStreaming = false
            self.stream = nil
            destroyCompressor()
            debugPrint("[Stream] ❌ \(detail)")
        } catch {
            let detail = "unexpected: \(error)"
            health = .failed(detail)
            isStreaming = false
            self.stream = nil
            destroyCompressor()
            debugPrint("[Stream] ❌ \(detail)")
        }
    }
}
