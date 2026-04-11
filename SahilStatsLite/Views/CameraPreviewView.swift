//
//  CameraPreviewView.swift
//  SahilStatsLite
//
//  PURPOSE: Camera preview UIViewRepresentable for AVCaptureSession display,
//           blinking colon for clock display, and orientation-aware preview layer.
//  KEY TYPES: BlinkingColon, CameraPreviewView, CameraPreviewUIView
//  DEPENDS ON: AVFoundation
//
//  NOTE: Keep this header updated when modifying this file.
//

import SwiftUI
import AVFoundation
import Combine

// MARK: - Blinking Colon View

struct BlinkingColon: View {
    let isRunning: Bool
    let font: Font
    let runningColor: Color
    let pausedColor: Color

    @State private var visible: Bool = true

    var body: some View {
        Text(":")
            .font(font)
            .foregroundColor(isRunning ? runningColor : pausedColor)
            .opacity(isRunning ? (visible ? 1.0 : 0.0) : 1.0)
            .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                if isRunning {
                    visible.toggle()
                } else {
                    visible = true
                }
            }
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer = previewLayer
        view.layer.addSublayer(previewLayer)

        view.updatePreviewOrientation()

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? CameraPreviewUIView else { return }
        view.previewLayer?.frame = view.bounds
        view.updatePreviewOrientation()
    }
}

class CameraPreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        updatePreviewOrientation()
    }

    func updatePreviewOrientation() {
        guard let connection = previewLayer?.connection else { return }

        let deviceOrientation = UIDevice.current.orientation
        let rotationAngle: CGFloat

        switch deviceOrientation {
        case .portrait:
            rotationAngle = 90
        case .portraitUpsideDown:
            rotationAngle = 270
        case .landscapeLeft:
            rotationAngle = 0
        case .landscapeRight:
            rotationAngle = 180
        default:
            if let windowScene = window?.windowScene {
                switch windowScene.effectiveGeometry.interfaceOrientation {
                case .portrait:
                    rotationAngle = 90
                case .portraitUpsideDown:
                    rotationAngle = 270
                case .landscapeLeft:
                    rotationAngle = 0
                case .landscapeRight:
                    rotationAngle = 180
                default:
                    rotationAngle = 0
                }
            } else {
                rotationAngle = 0
            }
        }

        if connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
    }
}
