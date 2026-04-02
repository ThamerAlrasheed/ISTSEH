import SwiftUI
import AVFoundation
import UIKit

/// SwiftUI sheet that shows a live camera preview and returns a captured UIImage.
struct CameraCaptureView: View {
    let onImage: (UIImage) -> Void
    let onError: (String) -> Void

    @StateObject private var model = CameraModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            CameraPreview(session: model.session)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        onError("cancelled")
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .tint(.white)
                    .padding(.leading, 16)
                    .padding(.top, 14)

                    Spacer()
                }
                Spacer()
                Button {
                    model.capturePhoto()
                } label: {
                    ZStack {
                        Circle().fill(.white.opacity(0.25)).frame(width: 86, height: 86)
                        Circle().fill(.white).frame(width: 70, height: 70)
                    }
                }
                .padding(.bottom, 28)
                .disabled(!model.isReady || model.isCapturing)
            }
        }
        .onAppear {
            Task {
                do { try await model.start() }
                catch { onError(error.localizedDescription); dismiss() }
            }
        }
        .onDisappear { model.stop() }
        .onReceive(model.$capturedImage.compactMap { $0 }) { img in
            onImage(img); dismiss()
        }
        .alert("Camera Error", isPresented: $model.showError) {
            Button("OK") { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "Unknown error.")
        }
    }
}

@MainActor
final class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var capturedImage: UIImage? = nil
    @Published var isReady = false
    @Published var isCapturing = false
    @Published var showError = false
    @Published var errorMessage: String? = nil

    nonisolated let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "CameraSessionQueue", qos: .userInitiated)
    nonisolated private let photoOutput = AVCapturePhotoOutput()

    // MARK: Start / Stop

    func start() async throws {
        // 0) Safety check
        if Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") == nil {
            throw NSError(domain: "Camera", code: -10,
                          userInfo: [NSLocalizedDescriptionKey: "Missing NSCameraUsageDescription in Info.plist."])
        }

        // 1) Permissions
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .video) { ok in c.resume(returning: ok) }
            }
            guard granted else {
                throw NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera permission denied."])
            }
        } else if status != .authorized {
            throw NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera permission denied."])
        }

        // 2) Configure
        try await configureSessionIfNeeded()
        try await startRunning()
        self.isReady = true
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // MARK: Capture

    func capturePhoto() {
        guard isReady, session.isRunning else { return }
        isCapturing = true
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        
        // Use newer API if available for high res
        if #available(iOS 17.0, *) {
            // maxPhotoDimensions is preferred
        } else {
            settings.isHighResolutionPhotoEnabled = true 
        }
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: Delegate

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        if let error = error {
            Task { @MainActor in self.present(error.localizedDescription); self.isCapturing = false }
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let img = UIImage(data: data) else {
            Task { @MainActor in self.present("Could not read image data."); self.isCapturing = false }
            return
        }
        let normalized = img.fixedOrientation()
        Task { @MainActor in
            self.capturedImage = normalized
            self.isCapturing = false
        }
    }

    // MARK: Private async helpers

    private func configureSessionIfNeeded() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else { return }
                do {
                    if !self.session.inputs.isEmpty && self.session.outputs.contains(self.photoOutput) {
                        cont.resume(returning: ())
                        return
                    }

                    self.session.beginConfiguration()
                    self.session.sessionPreset = .photo

                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ??
                                        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) else {
                        throw NSError(domain: "Camera", code: 2, userInfo: [NSLocalizedDescriptionKey: "No camera available."])
                    }

                    for input in self.session.inputs { self.session.removeInput(input) }

                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.session.canAddInput(input) else {
                        throw NSError(domain: "Camera", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot add camera input."])
                    }
                    self.session.addInput(input)

                    if !self.session.outputs.contains(self.photoOutput) {
                        guard self.session.canAddOutput(self.photoOutput) else {
                            throw NSError(domain: "Camera", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot add photo output."])
                        }
                        self.session.addOutput(self.photoOutput)
                    }

                    self.session.commitConfiguration()
                    cont.resume(returning: ())
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func startRunning() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else { return }
                if self.session.isRunning { cont.resume(returning: ()); return }
                self.session.startRunning()
                cont.resume(returning: ())
            }
        }
    }

    // MARK: Error UI

    private func present(_ message: String) {
        self.errorMessage = message
        self.showError = true
    }

    func clearError() { errorMessage = nil; showError = false }
}

// MARK: - Preview Layer

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        let layer = uiView.videoPreviewLayer
        guard let connection = layer.connection else { return }

        if #available(iOS 17.0, *) {
            connection.videoRotationAngle = uiRotationAngle()
        } else {
            connection.videoOrientation = uiOrientation()
        }
    }

    private func uiRotationAngle() -> CGFloat {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.interfaceOrientation ?? .portrait
        
        switch orientation {
        case .landscapeLeft: return 180
        case .landscapeRight: return 0
        case .portraitUpsideDown: return 270
        default: return 90 // portrait
        }
    }

    @available(iOS, deprecated: 17.0, message: "Use videoRotationAngle instead")
    private func uiOrientation() -> AVCaptureVideoOrientation {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.interfaceOrientation ?? .portrait
        
        switch orientation {
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Utilities

private extension UIImage {
    /// Normalize orientation to .up
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return img ?? self
    }
}
