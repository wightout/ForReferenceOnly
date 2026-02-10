import SwiftUI
import PhotosUI

/// Reusable photo editor section for Add/Edit Tool views.
/// Supports picking from photo library, taking photos with camera, reordering, and deleting.
/// Maximum 5 photos per tool. Index 0 is always the hero/thumbnail photo.
///
/// IMPORTANT: The camera is presented via a UIKit-managed presentation to avoid
/// SwiftUI Form/Section re-render issues that cause fullScreenCover to dismiss immediately.
struct ToolPhotoEditorSection: View {
    /// The array of images being managed (bound to parent view's state)
    @Binding var images: [UIImage]

    /// Selected items from PhotosPicker
    @State private var selectedItems: [PhotosPickerItem] = []
    /// Whether to show the camera
    @State private var showingCamera = false

    private let maxPhotos = ToolPhotoService.maxPhotos

    var body: some View {
        Section {
            // Current photos grid
            if !images.isEmpty {
                photoGrid
            }

            // Add photo buttons — each on its own row for clear separation
            if images.count < maxPhotos {
                // Photo Library — uses PhotosPicker directly (no boolean state needed)
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: max(1, maxPhotos - images.count),
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.body)
                        Text("Choose from Library")
                            .font(.subheadline)
                        Spacer()
                    }
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                }
                .accessibilityLabel("Add photo from library")
                .onChange(of: selectedItems) { _, newItems in
                    Task {
                        for item in newItems {
                            if images.count >= maxPhotos { break }
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                images.append(uiImage)
                            }
                        }
                        selectedItems.removeAll()
                    }
                }

                // Camera — completely separate row
                Button {
                    presentCamera()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera")
                            .font(.body)
                        Text("Take Photo")
                            .font(.subheadline)
                        Spacer()
                    }
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                }
                .accessibilityLabel("Take photo with camera")
            }

            // Help text
            HStack(spacing: 6) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Up to \(maxPhotos) photos. First photo is the thumbnail.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } header: {
            HStack {
                Text("Photos (\(images.count)/\(maxPhotos))")
                if !images.isEmpty {
                    Spacer()
                    Button("Clear All") {
                        withAnimation {
                            images.removeAll()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
        }
    }

    /// Presents the camera using UIKit directly, bypassing SwiftUI's fullScreenCover
    /// which gets dismissed when Form/Section re-renders inside NavigationStack.
    private func presentCamera() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        // Walk to the topmost presented view controller
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let picker = UIImagePickerController()
        picker.sourceType = .camera
        let delegate = CameraCaptureDelegate { [self] image in
            if images.count < maxPhotos {
                images.append(image)
            }
        }
        // Retain the delegate via objc_setAssociatedObject so it isn't deallocated
        objc_setAssociatedObject(picker, &AssociatedKeys.cameraDelegate, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        picker.delegate = delegate
        topVC.present(picker, animated: true)
    }

    // MARK: - Photo Grid (Tap-to-Reorder)

    private var photoGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    photoCell(image: image, index: index)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func photoCell(image: UIImage, index: Int) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipped()
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(index == 0 ? Color(red: 0.145, green: 0.388, blue: 0.922) : Color.clear, lineWidth: 2)
                    )

                // Delete button
                Button {
                    withAnimation {
                        let _ = images.remove(at: index)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.red).frame(width: 16, height: 16))
                }
                .offset(x: 6, y: -6)
                .accessibilityLabel("Remove photo \(index + 1)")
            }

            // Hero badge
            if index == 0 {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                    Text("Hero")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
            }

            // Move buttons (shown when there are 2+ photos)
            if images.count > 1 {
                HStack(spacing: 8) {
                    // Move left (toward hero position)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            images.swapAt(index, index - 1)
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            .frame(width: 24, height: 20)
                            .background(Color(UIColor.systemGray5))
                            .cornerRadius(4)
                    }
                    .disabled(index == 0)
                    .opacity(index == 0 ? 0.3 : 1.0)
                    .accessibilityLabel("Move photo \(index + 1) left")

                    // Move right
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            images.swapAt(index, index + 1)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            .frame(width: 24, height: 20)
                            .background(Color(UIColor.systemGray5))
                            .cornerRadius(4)
                    }
                    .disabled(index == images.count - 1)
                    .opacity(index == images.count - 1 ? 0.3 : 1.0)
                    .accessibilityLabel("Move photo \(index + 1) right")
                }
            }
        }
    }
}

// MARK: - Associated Object Key

private enum AssociatedKeys {
    nonisolated(unsafe) static var cameraDelegate: UInt8 = 0
}

// MARK: - Camera Capture Delegate (UIKit-managed, avoids SwiftUI lifecycle issues)

/// UIKit delegate for camera capture. Presented directly via UIKit to avoid
/// SwiftUI Form/Section re-render issues that cause fullScreenCover to dismiss.
private class CameraCaptureDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let onImageCaptured: (UIImage) -> Void

    init(onImageCaptured: @escaping (UIImage) -> Void) {
        self.onImageCaptured = onImageCaptured
        super.init()
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        if let image = info[.originalImage] as? UIImage {
            onImageCaptured(image)
        }
        picker.dismiss(animated: true)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
