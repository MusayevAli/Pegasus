import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

extension View {
    @ViewBuilder func tripInlineTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    @ViewBuilder func tripURLInput() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
        #else
        self.autocorrectionDisabled()
        #endif
    }
}
func tripVisibleViewport() -> CGRect {
    #if os(iOS)
    UIScreen.main.bounds.insetBy(dx: 0, dy: 95)
    #else
    CGRect(x: 0, y: 80, width: 430, height: 675)
    #endif
}
struct PackingPhoto: View {
    var data: Data
    @ViewBuilder var body: some View {
        #if os(iOS)
        if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() }
        #else
        if let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit() }
        #endif
    }
}
func packingJPEG(_ data: Data) -> Data? {
    #if os(iOS)
    guard let image = UIImage(data: data) else { return nil }
    let ratio = min(1, 1024 / max(image.size.width, image.size.height))
    let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.65)
    #else
    guard let image = NSImage(data: data), let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.65])
    #endif
}
