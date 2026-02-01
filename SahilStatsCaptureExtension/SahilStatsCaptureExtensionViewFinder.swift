//
//  SahilStatsCaptureExtensionViewFinder.swift
//  SahilStatsCaptureExtension
//
//  Camera Control extension with AVCaptureSession and zoom slider support
//

import SwiftUI
import AVFoundation
import AVKit
import LockedCameraCapture

struct SahilStatsCaptureExtensionViewFinder: UIViewControllerRepresentable {
    let session: LockedCameraCaptureSession

    init(session: LockedCameraCaptureSession) {
        self.session = session
    }

    func makeUIViewController(context: Context) -> CaptureViewController {
        return CaptureViewController(lockedSession: session)
    }

    func updateUIViewController(_ uiViewController: CaptureViewController, context: Context) {
    }
}

// MARK: - Capture View Controller

class CaptureViewController: UIViewController {
    private let lockedSession: LockedCameraCaptureSession
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var videoDevice: AVCaptureDevice?

    private let controlQueue = DispatchQueue(label: "com.sahilstats.captureControl")

    init(lockedSession: LockedCameraCaptureSession) {
        self.lockedSession = lockedSession
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCaptureSession()
        setupCaptureInteraction()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    // MARK: - Setup Capture Session

    private func setupCaptureSession() {
        let session = AVCaptureSession()
        session.beginConfiguration()

        // Set quality
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        }

        // Add video input
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("No camera available")
            return
        }
        videoDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            print("Failed to create video input: \(error)")
            return
        }

        // Add Camera Control zoom slider (iOS 18+, iPhone 16+)
        if #available(iOS 18.0, *) {
            if session.supportsControls {
                // Remove existing controls
                for control in session.controls {
                    session.removeControl(control)
                }

                // Add zoom slider
                let zoomSlider = AVCaptureSystemZoomSlider(device: device) { zoomFactor in
                    // Zoom is handled automatically by the system
                    print("Zoom: \(zoomFactor)x")
                }

                if session.canAddControl(zoomSlider) {
                    session.addControl(zoomSlider)
                    print("Camera Control zoom slider added")
                }

                // Set delegate
                session.setControlsDelegate(self, queue: controlQueue)
            }
        }

        session.commitConfiguration()
        captureSession = session

        // Setup preview layer
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview
    }

    // MARK: - Setup Capture Interaction (Camera Control button)

    private func setupCaptureInteraction() {
        // Use SwiftUI's onCameraCaptureEvent or handle via delegate
        // The AVCaptureSessionControlsDelegate handles Camera Control interactions
    }

    private func openMainApp() {
        // Open the main SahilStatsLite app
        Task {
            await lockedSession.openApplication()
        }
    }
}

// MARK: - Camera Control Delegate

@available(iOS 18.0, *)
extension CaptureViewController: AVCaptureSessionControlsDelegate {
    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {
        print("Camera Control active")
    }

    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {
        print("Camera Control entering fullscreen")
    }

    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {
        print("Camera Control exiting fullscreen")
    }

    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
        print("Camera Control inactive")
    }
}
