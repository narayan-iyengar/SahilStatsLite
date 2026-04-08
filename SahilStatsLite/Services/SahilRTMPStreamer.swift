//
//  SahilRTMPStreamer.swift
//  SahilStatsLite
//
//  Custom RTMP streamer — no HaishinKit dependency.
//  Uses pure Swift async/await for all network I/O (no blocking threads or semaphores).
//

import Foundation
import Network
import AVFoundation
import VideoToolbox
import CoreMedia
import CoreImage

// MARK: - AMF0 Encoding

private enum AMF0 {
    static func string(_ s: String) -> Data {
        var d = Data([0x02])
        let b = s.utf8; d += [UInt8((b.count >> 8) & 0xFF), UInt8(b.count & 0xFF)]; d += b; return d
    }
    static func number(_ n: Double) -> Data {
        var v = n.bitPattern.bigEndian; return Data([0x00]) + Data(bytes: &v, count: 8)
    }
    static func null() -> Data { Data([0x05]) }
    /// AMF0 strict object (0x03) — for generic key-value objects
    static func object(_ pairs: [(String, Data)]) -> Data {
        var d = Data([0x03])
        for (k, v) in pairs {
            let kb = k.utf8; d += [UInt8((kb.count >> 8) & 0xFF), UInt8(kb.count & 0xFF)]; d += kb; d += v
        }
        return d + Data([0x00, 0x00, 0x09])
    }
    /// AMF0 ECMA array (0x08) — required by YouTube/Flash for @setDataFrame onMetaData
    static func ecmaArray(_ pairs: [(String, Data)]) -> Data {
        let count = UInt32(pairs.count)
        var d = Data([0x08,
                      UInt8((count>>24)&0xFF), UInt8((count>>16)&0xFF),
                      UInt8((count>>8)&0xFF),  UInt8(count&0xFF)])
        for (k, v) in pairs {
            let kb = k.utf8; d += [UInt8((kb.count >> 8) & 0xFF), UInt8(kb.count & 0xFF)]; d += kb; d += v
        }
        return d + Data([0x00, 0x00, 0x09])
    }
}

// MARK: - RTMP Chunk Encoding

private let kChunkSize = 128

private func makeChunk(csid: UInt8, msgType: UInt8, streamId: UInt32,
                       ts: UInt32, payload: Data) -> Data {
    var out = Data(); var offset = 0
    while offset < payload.count {
        let end = min(offset + kChunkSize, payload.count)
        if offset == 0 {
            let t = min(ts, 0xFFFFFF); let n = payload.count
            out += [csid & 0x3F,
                    UInt8((t>>16)&0xFF), UInt8((t>>8)&0xFF), UInt8(t&0xFF),
                    UInt8((n>>16)&0xFF), UInt8((n>>8)&0xFF), UInt8(n&0xFF),
                    msgType,
                    UInt8(streamId&0xFF), UInt8((streamId>>8)&0xFF),
                    UInt8((streamId>>16)&0xFF), UInt8((streamId>>24)&0xFF)]
        } else {
            out += [0xC0 | (csid & 0x3F)]
        }
        out += payload[offset..<end]; offset = end
    }
    return out
}

private func connectCmd(tcUrl: String) -> Data {
    makeChunk(csid: 3, msgType: 0x14, streamId: 0, ts: 0,
              payload: AMF0.string("connect") + AMF0.number(1) +
              AMF0.object([("app", AMF0.string("live2")), ("type", AMF0.string("nonprivate")),
                           ("flashVer", AMF0.string("FMLE/3.0 (compatible; FMSc/1.0)")),
                           ("tcUrl", AMF0.string(tcUrl))]))
}
private func createStreamCmd() -> Data {
    makeChunk(csid: 3, msgType: 0x14, streamId: 0, ts: 0,
              payload: AMF0.string("createStream") + AMF0.number(2) + AMF0.null())
}
private func publishCmd(key: String, sid: UInt32) -> Data {
    makeChunk(csid: 8, msgType: 0x14, streamId: sid, ts: 0,
              payload: AMF0.string("publish") + AMF0.number(0) + AMF0.null() +
              AMF0.string(key) + AMF0.string("live"))
}
private func metadataCmd(sid: UInt32) -> Data {
    makeChunk(csid: 4, msgType: 0x12, streamId: sid, ts: 0,
              payload: AMF0.string("@setDataFrame") + AMF0.string("onMetaData") +
              AMF0.ecmaArray([("duration", AMF0.number(0)), ("width", AMF0.number(1920)),
                              ("height", AMF0.number(1080)), ("videocodecid", AMF0.number(7)),
                              ("videodatarate", AMF0.number(6000)), ("framerate", AMF0.number(30)),
                              ("audiocodecid", AMF0.number(10)), ("audiodatarate", AMF0.number(128)),
                              ("audiosamplerate", AMF0.number(44100))]))
}

// MARK: - FLV Video

private func avcSeqHeader(fd: CMFormatDescription, ts: UInt32, sid: UInt32) -> Data? {
    var count = 0; var nal: Int32 = 0
    guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        fd, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil,
        parameterSetCountOut: &count, nalUnitHeaderLengthOut: &nal) == noErr, count >= 2 else { return nil }
    var sp: UnsafePointer<UInt8>?; var sl = 0; var pp: UnsafePointer<UInt8>?; var pl = 0
    guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            fd, parameterSetIndex: 0, parameterSetPointerOut: &sp, parameterSetSizeOut: &sl,
            parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr,
          CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            fd, parameterSetIndex: 1, parameterSetPointerOut: &pp, parameterSetSizeOut: &pl,
            parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr,
          let sps = sp, sl >= 4, let pps = pp, pl > 0 else { return nil }
    var avcc = Data([0x01, sps[1], sps[2], sps[3], 0xFF, 0xE1])
    avcc += [UInt8((sl>>8)&0xFF), UInt8(sl&0xFF)] + Data(bytes: sps, count: sl)
    avcc += [0x01, UInt8((pl>>8)&0xFF), UInt8(pl&0xFF)] + Data(bytes: pps, count: pl)
    var p = Data([0x17, 0x00, 0x00, 0x00, 0x00]); p += avcc
    return makeChunk(csid: 6, msgType: 0x09, streamId: sid, ts: ts, payload: p)
}

private func avcFrame(sb: CMSampleBuffer, ts: UInt32, sid: UInt32, isKey: Bool) -> Data? {
    guard let block = sb.dataBuffer else { return nil }
    var len = 0; var ptr: UnsafeMutablePointer<Int8>?
    guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                      totalLengthOut: &len, dataPointerOut: &ptr) == noErr,
          let p = ptr, len > 0 else { return nil }
    var payload = Data([isKey ? 0x17 : 0x27, 0x01, 0x00, 0x00, 0x00])
    payload += Data(bytes: p, count: len)
    return makeChunk(csid: 6, msgType: 0x09, streamId: sid, ts: ts, payload: payload)
}

private func aacSeqHeader(sid: UInt32) -> Data {
    makeChunk(csid: 4, msgType: 0x08, streamId: sid, ts: 0, payload: Data([0xAF, 0x00, 0x12, 0x10]))
}
private func aacFrame(_ data: Data, ts: UInt32, sid: UInt32) -> Data {
    var p = Data([0xAF, 0x01]); p += data
    return makeChunk(csid: 4, msgType: 0x08, streamId: sid, ts: ts, payload: p)
}

// MARK: - Async Network Helpers

private func tcpConnect(host: String, port: UInt16) async throws -> NWConnection {
    let conn = NWConnection(host: NWEndpoint.Host(host),
                            port: NWEndpoint.Port(integerLiteral: port), using: .tcp)
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        var resumed = false
        conn.stateUpdateHandler = { state in
            guard !resumed else { return }
            switch state {
            case .ready:
                resumed = true; cont.resume()
            case .failed(let e):
                resumed = true; cont.resume(throwing: e)
            case .cancelled:
                resumed = true; cont.resume(throwing: CancellationError())
            default: break
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
    }
    return conn
}

private func netSend(_ conn: NWConnection, data: Data) async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        conn.send(content: data, completion: .contentProcessed { err in
            if let e = err { cont.resume(throwing: e) } else { cont.resume() }
        })
    }
}

private func netRecv(_ conn: NWConnection, exactly n: Int) async throws -> Data {
    var buf = Data()
    while buf.count < n {
        let remaining = n - buf.count
        let chunk = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            conn.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, isEOF, err in
                if let e = err { cont.resume(throwing: e); return }
                if isEOF && (data == nil || data!.isEmpty) {
                    cont.resume(throwing: URLError(.badServerResponse)); return
                }
                cont.resume(returning: data ?? Data())
            }
        }
        if chunk.isEmpty { throw URLError(.badServerResponse) }
        buf += chunk
    }
    return buf
}

/// Drain incoming bytes until the given ASCII tag appears (for RTMP _result parsing).
private func netWait(_ conn: NWConnection, tag: String) async throws {
    var buf = Data(); let needle = Data(tag.utf8)
    while !buf.contains(needle) {
        let chunk = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isEOF, err in
                if let e = err { cont.resume(throwing: e); return }
                if isEOF && (data == nil || data!.isEmpty) {
                    cont.resume(throwing: URLError(.badServerResponse)); return
                }
                cont.resume(returning: data ?? Data())
            }
        }
        buf += chunk
        if buf.count > 65536 { buf = Data(buf.suffix(32768)) }
    }
}

private extension Data {
    func contains(_ needle: Data) -> Bool {
        guard !needle.isEmpty, needle.count <= count else { return false }
        for i in 0...(count - needle.count) {
            if self[i..<(i + needle.count)] == needle { return true }
        }
        return false
    }
}

// MARK: - SahilRTMPStreamer

final class SahilRTMPStreamer: @unchecked Sendable {

    private let host = "a.rtmp.youtube.com"
    private let port: UInt16 = 1935

    nonisolated(unsafe) private var conn: NWConnection?
    nonisolated(unsafe) private var streamId: UInt32 = 1
    nonisolated(unsafe) private var running = false

    nonisolated(unsafe) private var vtSession: VTCompressionSession?
    nonisolated(unsafe) private var frameCount: Int64 = 0
    nonisolated(unsafe) private var videoStart: CMTime = .invalid
    nonisolated(unsafe) private var sentVideoSeqHdr = false

    // Scale 4K input → 1080p before VT encode
    // VTCompressionSession does NOT auto-scale — mismatched input produces corrupt H.264
    nonisolated(unsafe) private let ciCtx = CIContext(options: [.useSoftwareRenderer: false])
    nonisolated(unsafe) private var scaledPool: CVPixelBufferPool? = {
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: 1920,
            kCVPixelBufferHeightKey: 1080,
            kCVPixelBufferIOSurfacePropertiesKey: NSDictionary()
        ] as NSDictionary, &pool)
        return pool
    }()

    nonisolated(unsafe) private var audioConverter: AVAudioConverter?
    nonisolated(unsafe) private var audioStart: CMTime = .invalid
    nonisolated(unsafe) private var sentAudioSeqHdr = false
    nonisolated(unsafe) private var realAudioActive = false  // true once mic audio flows

    var onLive: (() -> Void)?
    var onFailed: ((String) -> Void)?

    // MARK: - Start / Stop

    func start(streamKey: String) {
        Task { await self.connectAndStream(key: streamKey) }
    }

    func stop() {
        running = false
        let c = conn; conn = nil
        c?.cancel()          // triggers netRecv to throw CancellationError, breaking drain loop
        destroyVT()
        audioConverter = nil; audioStart = .invalid; sentAudioSeqHdr = false
        debugPrint("[SahilRTMP] stopped")
    }

    // MARK: - Protocol (async)

    private func connectAndStream(key: String) async {
        do {
            debugPrint("[SahilRTMP] Connecting to \(host):\(port)...")
            let c = try await tcpConnect(host: host, port: port)
            conn = c
            debugPrint("[SahilRTMP] TCP ready — starting handshake")

            // RTMP handshake: C0+C1 → S0+S1 → C2 → drain S2
            var c0c1 = Data([0x03])
            c0c1 += Data(repeating: 0, count: 4)   // C1 time = 0
            c0c1 += Data(repeating: 0, count: 4)   // C1 zeros
            c0c1 += Data((0..<1528).map { _ in UInt8.random(in: 0...255) })
            try await netSend(c, data: c0c1)

            let s01 = try await netRecv(c, exactly: 1537)   // S0 (1) + S1 (1536)
            let c2 = Data(s01[1..<1537])                    // C2 = S1
            try await netSend(c, data: c2)
            _ = try? await netRecv(c, exactly: 1536)        // drain S2 (optional)
            debugPrint("[SahilRTMP] Handshake complete")

            // RTMP protocol
            try await netSend(c, data: connectCmd(tcUrl: "rtmp://\(host)/live2"))
            try await netWait(c, tag: "_result")
            debugPrint("[SahilRTMP] connect _result received")

            try await netSend(c, data: createStreamCmd())
            try await netWait(c, tag: "_result")
            debugPrint("[SahilRTMP] createStream _result received")

            try await netSend(c, data: publishCmd(key: key, sid: streamId))
            try await netWait(c, tag: "NetStream.Publish.Start")
            debugPrint("[SahilRTMP] Publish.Start received")

            try await netSend(c, data: metadataCmd(sid: streamId))
            try await netSend(c, data: aacSeqHeader(sid: streamId))
            sentAudioSeqHdr = true
            running = true
            debugPrint("[SahilRTMP] ✅ LIVE")
            await MainActor.run { self.onLive?() }

            // Send silent AAC audio at 44100Hz — guarantees YouTube gets A/V sync point.
            // Without audio, YouTube stays at "Preparing stream" indefinitely.
            // Real mic audio from appendAudio() supplements this when available.
            Task { [weak self] in await self?.silentAudioLoop(conn: c) }

            // Drain incoming (window ack, ping requests, etc.) until stop() is called
            while running {
                guard let _ = try? await netRecv(c, exactly: 1) else { break }
            }
            debugPrint("[SahilRTMP] drain loop exited (running=\(running))")
        } catch {
            fail("\(error)")
        }
    }

    // MARK: - Frame Injection

    func appendVideo(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard running else { return }
        // Scale camera frame to 1920×1080 BGRA — VT requires input to match output dimensions.
        // Green BGRA 1920×1080 showed "Preparing stream" (YouTube decoded it).
        // Raw 4K NV12 camera frame produces corrupt H.264 (YouTube shows black).
        let inputBuf: CVPixelBuffer
        let inW = CVPixelBufferGetWidth(pixelBuffer)
        let inH = CVPixelBufferGetHeight(pixelBuffer)
        if inW > 1920 || inH > 1080 {
            // Create clean BGRA 1920×1080 buffer and render scaled camera frame into it
            var scaled: CVPixelBuffer?
            let attrs: NSDictionary = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: 1920,
                kCVPixelBufferHeightKey: 1080,
                kCVPixelBufferIOSurfacePropertiesKey: NSDictionary()
            ]
            if CVPixelBufferCreate(kCFAllocatorDefault, 1920, 1080,
                                   kCVPixelFormatType_32BGRA, attrs, &scaled) == kCVReturnSuccess,
               let out = scaled {
                let scaleX = 1920.0 / Double(inW)
                let scaleY = 1080.0 / Double(inH)
                // Use sRGB colorspace to avoid HDR/wide-color issues with YouTube decoder
                let ci = CIImage(cvPixelBuffer: pixelBuffer)
                    .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                ciCtx.render(ci, to: out, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                             colorSpace: CGColorSpaceCreateDeviceRGB())
                inputBuf = out
            } else {
                inputBuf = pixelBuffer  // fallback (shouldn't happen)
            }
        } else {
            inputBuf = pixelBuffer
        }

        if vtSession == nil { setupVT(1920, 1080) }
        guard let session = vtSession else { return }
        if videoStart == .invalid { videoStart = timestamp }
        frameCount += 1
        let isKey = frameCount % 60 == 1
        let props: CFDictionary? = isKey ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        let capturedIsKey = isKey
        VTCompressionSessionEncodeFrame(
            session, imageBuffer: inputBuf,
            presentationTimeStamp: timestamp, duration: CMTime(value: 1, timescale: 30),
            frameProperties: props, infoFlagsOut: nil,
            outputHandler: { [weak self] status, _, sb in
                guard let self, let sb, status == noErr, self.running else { return }
                self.sendVideo(sb, isKey: capturedIsKey)
            })
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard running, sentAudioSeqHdr else { return }
        encodeAudio(sampleBuffer)
    }

    // MARK: - Silent Audio (guarantees A/V sync for YouTube preview)

    private func silentAudioLoop(conn: NWConnection) async {
        let pcmFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 44100, channels: 2, interleaved: false)!
        guard let aacFmt = AVAudioFormat(settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                                     AVSampleRateKey: 44100,
                                                     AVNumberOfChannelsKey: 2,
                                                     AVEncoderBitRateKey: 128_000]),
              let conv = AVAudioConverter(from: pcmFmt, to: aacFmt) else {
            debugPrint("[SahilRTMP] ❌ silent audio converter failed")
            return
        }
        let maxPkt = max(768, Int(aacFmt.streamDescription.pointee.mBytesPerPacket))
        var audioTs: UInt32 = 0
        let nsPerFrame: UInt64 = 23_219_954  // 1024/44100 seconds in nanoseconds

        debugPrint("[SahilRTMP] 🔇 silent audio loop started — stops when mic audio flows")
        while running {
            // Step aside once real mic audio is established
            if realAudioActive { try? await Task.sleep(nanoseconds: 1_000_000_000); continue }
            guard let silentBuf = AVAudioPCMBuffer(pcmFormat: pcmFmt, frameCapacity: 1024) else { break }
            silentBuf.frameLength = 1024
            // Leave samples at 0 (silence — pcmFormatFloat32 zero-init'd)
            let outBuf = AVAudioCompressedBuffer(format: aacFmt, packetCapacity: 1,
                                                  maximumPacketSize: maxPkt)
            var convErr: NSError?
            conv.convert(to: outBuf, error: &convErr) { _, status in
                status.pointee = .haveData; return silentBuf
            }
            if convErr == nil, outBuf.byteLength > 0 {
                let msg = aacFrame(Data(bytes: outBuf.data, count: Int(outBuf.byteLength)),
                                   ts: audioTs, sid: streamId)
                conn.send(content: msg, completion: .idempotent)
            }
            audioTs &+= 23  // ~23ms per AAC frame
            try? await Task.sleep(nanoseconds: nsPerFrame)
        }
        debugPrint("[SahilRTMP] 🔇 silent audio loop exited")
    }

    // MARK: - Video Sending

    private func sendVideo(_ sb: CMSampleBuffer, isKey: Bool) {
        guard let c = conn else { debugPrint("[SahilRTMP] ⚠️ sendVideo: conn is nil"); return }
        let ts = msSince(sb.presentationTimeStamp, start: videoStart)
        if !sentVideoSeqHdr, let fd = sb.formatDescription {
            sentVideoSeqHdr = true
            if let seqData = avcSeqHeader(fd: fd, ts: ts, sid: streamId) {
                c.send(content: seqData, completion: .idempotent)
                debugPrint("[SahilRTMP] AVC sequence header sent")
            }
        }
        if let frameData = avcFrame(sb: sb, ts: ts, sid: streamId, isKey: isKey) {
            c.send(content: frameData, completion: .idempotent)
        }
    }

    // MARK: - Audio Encoding (PCM → AAC)

    private func encodeAudio(_ sb: CMSampleBuffer) {
        guard let c = conn,
              let inputFmt = sb.formatDescription.flatMap({ AVAudioFormat(cmAudioFormatDescription: $0) }) else { return }
        if audioConverter == nil {
            // Match input channel count — iPhone mic is mono, forcing stereo causes converter failure
            let inChannels = inputFmt.channelCount
            guard let aacFmt = AVAudioFormat(settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                                         AVSampleRateKey: inputFmt.sampleRate,
                                                         AVNumberOfChannelsKey: inChannels,
                                                         AVEncoderBitRateKey: 128_000]),
                  let conv = AVAudioConverter(from: inputFmt, to: aacFmt) else {
                debugPrint("[SahilRTMP] ⚠️ AAC converter init failed — staying on silent audio")
                return
            }
            audioConverter = conv
            debugPrint("[SahilRTMP] 🎤 AAC converter ready: \(inChannels)ch @\(Int(inputFmt.sampleRate))Hz")
        }
        guard let conv = audioConverter else { return }
        if audioStart == .invalid { audioStart = sb.presentationTimeStamp }

        let n = CMSampleBufferGetNumSamples(sb)
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inputFmt, frameCapacity: AVAudioFrameCount(n)) else { return }
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sb, at: 0, frameCount: Int32(n), into: inBuf.mutableAudioBufferList) == noErr else { return }
        inBuf.frameLength = AVAudioFrameCount(n)

        let maxPkt = max(768, Int(conv.outputFormat.streamDescription.pointee.mBytesPerPacket))
        let outBuf = AVAudioCompressedBuffer(format: conv.outputFormat, packetCapacity: 1, maximumPacketSize: maxPkt)
        var convErr: NSError?
        conv.convert(to: outBuf, error: &convErr) { _, status in status.pointee = .haveData; return inBuf }
        guard convErr == nil, outBuf.byteLength > 0 else { return }

        let ts = msSince(sb.presentationTimeStamp, start: audioStart)
        c.send(content: aacFrame(Data(bytes: outBuf.data, count: Int(outBuf.byteLength)), ts: ts, sid: streamId),
               completion: .idempotent)
        realAudioActive = true  // mic audio confirmed working — silent loop backs off
    }

    // MARK: - VTCompressionSession

    private func setupVT(_ width: Int, _ height: Int) {
        let w = min(width, 1920), h = min(height, 1080)
        var s: VTCompressionSession?
        VTCompressionSessionCreate(allocator: kCFAllocatorDefault, width: Int32(w), height: Int32(h),
                                   codecType: kCMVideoCodecType_H264, encoderSpecification: nil,
                                   imageBufferAttributes: nil, compressedDataAllocator: nil,
                                   outputCallback: nil, refcon: nil, compressionSessionOut: &s)
        guard let session = s else { return }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime,                    value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,              value: NSNumber(value: 6_000_000))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 2.0))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,                value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering,        value: kCFBooleanFalse)
        VTCompressionSessionPrepareToEncodeFrames(session)
        vtSession = session
        debugPrint("[SahilRTMP] VT H.264 ready \(w)×\(h)")
    }

    private func destroyVT() {
        if let s = vtSession { VTCompressionSessionInvalidate(s); vtSession = nil }
        frameCount = 0; videoStart = .invalid; sentVideoSeqHdr = false
    }

    private func msSince(_ t: CMTime, start: CMTime) -> UInt32 {
        guard CMTimeCompare(start, .invalid) != 0 else { return 0 }
        return UInt32(max(0, (t.seconds - start.seconds) * 1000))
    }

    private func fail(_ msg: String) {
        debugPrint("[SahilRTMP] ❌ \(msg)")
        running = false
        DispatchQueue.main.async { self.onFailed?(msg) }
    }
}
