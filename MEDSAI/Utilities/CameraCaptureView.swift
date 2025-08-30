import SwiftUI
import UIKit
import AVFoundation

/// SwiftUI wrapper over UIImagePickerController for camera capture.
struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    /// Called with the captured image (original).
    let onImage: (UIImage) -> Void
    /// Optional error callback (e.g., if camera is unavailable/denied).
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCaptureView
        init(parent: CameraCaptureView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.onImage(img)
            } else {
                parent.onError("No image returned.")
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Simple demo view you can push/present to try the camera.
struct CameraDemoView: View {
    @State private var showCamera = false
    @State private var lastImage: UIImage?

    var body: some View {
        VStack(spacing: 16) {
            if let ui = lastImage {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
            } else {
                Text("No photo yet").foregroundStyle(.secondary)
            }

            Button("Open Camera") { showCamera = true }
                .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Camera Demo")
        .sheet(isPresented: $showCamera) {
            CameraCaptureView(
                onImage: { img in lastImage = img },
                onError: { msg in print("Camera error:", msg) }
            )
        }
    }
}
