//
//  SahilStatsCaptureExtension.swift
//  SahilStatsCaptureExtension
//
//  Created by Narayan Iyengar on 2/1/26.
//

import ExtensionKit
import Foundation
import LockedCameraCapture
import SwiftUI

@main
struct SahilStatsCaptureExtension: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            SahilStatsCaptureExtensionViewFinder(session: session)
        }
    }
}
