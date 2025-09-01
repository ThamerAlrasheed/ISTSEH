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

// MARK: - ViewModel

final class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    // Public state
    @Published var capturedImage: UIImage? = nil
    @Published var isReady = false
    @Published var isCapturing = false
    @Published var showError = false
    @Published var errorMessage: String? = nil

    // Session
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "CameraSessionQueue", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()

    // MARK: Start / Stop

    func start() async throws {
        // 1) Permissions
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .video) { ok in c.resume(returning: ok) }
            }
            guard granted else {
                throw NSError(domain: "Camera", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Camera permission denied."])
            }
        } else if status != .authorized {
            throw NSError(domain: "Camera", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Camera permission denied."])
        }

        // 2) Configure + start (asynchronously on sessionQueue)
        try await configureSessionIfNeeded()
        try await startRunning()
        await MainActor.run { self.isReady = true }
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
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: Delegate

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        defer { isCapturing = false }
        if let error = error {
            present(error.localizedDescription); return
        }
        guard let data = photo.fileDataRepresentation(),
              let img = UIImage(data: data) else {
            present("Could not read image data."); return
        }
        let normalized = img.fixedOrientation()
        DispatchQueue.main.async { self.capturedImage = normalized }
    }

    // MARK: Private – async session helpers (no sync)

    private func configureSessionIfNeeded() async throws {
        try await withCheckedThrowingContinuation { cont in
            sessionQueue.async {
                do {
                    if !self.session.inputs.isEmpty && self.session.outputs.contains(self.photoOutput) {
                        cont.resume(returning: ()) // already configured
                        return
                    }

                    self.session.beginConfiguration()
                    self.session.sessionPreset = .photo

                    // Input
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                               for: .video,
                                                               position: .back) ??
                                        AVCaptureDevice.default(.builtInWideAngleCamera,
                                                                for: .video,
                                                                position: .unspecified) else {
                        throw NSError(domain: "Camera", code: 2,
                                      userInfo: [NSLocalizedDescriptionKey: "No camera available."])
                    }

                    // Remove stale inputs
                    for input in self.session.inputs { self.session.removeInput(input) }

                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.session.canAddInput(input) else {
                        throw NSError(domain: "Camera", code: 3,
                                      userInfo: [NSLocalizedDescriptionKey: "Cannot add camera input."])
                    }
                    self.session.addInput(input)

                    // Output
                    if self.session.outputs.contains(self.photoOutput) == false {
                        guard self.session.canAddOutput(self.photoOutput) else {
                            throw NSError(domain: "Camera", code: 4,
                                          userInfo: [NSLocalizedDescriptionKey: "Cannot add photo output."])
                        }
                        self.session.addOutput(self.photoOutput)
                        self.photoOutput.isHighResolutionCaptureEnabled = true
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
        try await withCheckedThrowingContinuation { cont in
            sessionQueue.async {
                if self.session.isRunning { cont.resume(returning: ()); return }
                self.session.startRunning()
                cont.resume(returning: ())
            }
        }
    }

    // MARK: Error surfacing

    private func present(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.showError = true
        }
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
        uiView.videoPreviewLayer.connection?.videoOrientation = uiOrientation()
    }

    private func uiOrientation() -> AVCaptureVideoOrientation {
        switch UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.interfaceOrientation {
        case .portrait: return .portrait
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
