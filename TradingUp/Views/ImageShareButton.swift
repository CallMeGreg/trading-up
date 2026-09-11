import SwiftUI
import UIKit
import LinkPresentation

struct ImageShareButton: View {
    let image: UIImage?
    let title: String
    let subtitle: String
    @State private var sharing = false

    var body: some View {
        BigButton(title: title, subtitle: subtitle, systemImage: "square.and.arrow.up",
                  enabled: image != nil) {
            sharing = true
        }
        .sheet(isPresented: $sharing) {
            if let image {
                ImageShareSheet(image: image)
            }
        }
    }
}

struct ImageShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    var activityItems: [Any] { [ImageShareItem(image: image)] }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

final class ImageShareItem: NSObject, UIActivityItemSource {
    let image: UIImage

    init(image: UIImage) {
        self.image = image
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        image
    }

    // The preview needs its own image provider; every destination still receives
    // only the UIImage above, never a separate title or URL.
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        let provider = NSItemProvider(object: image)
        metadata.imageProvider = provider
        metadata.iconProvider = provider
        return metadata
    }
}
