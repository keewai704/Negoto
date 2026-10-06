import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// UIKit's document picker. SwiftUI's `.fileImporter` silently fails to present when the same view
/// hierarchy also hosts sheets/alerts, so the picker is presented explicitly instead.
struct DocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType]
    var allowsMultipleSelection = true
    /// Copy picked files into the app's sandbox (no security scope needed). Folders can't be copied.
    var asCopy = true
    var onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: asCopy)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
