import CoreImage.CIFilterBuiltins
import UIKit

/// Draws QR codes on this phone with Core Image. Nothing is stored or sent.
enum QRImage {
    /// Modules of white around the code that scanners need.
    static let quietZone: CGFloat = 4

    /// A black-on-white QR code with a quiet zone, crisp at any size. Nil if the text is too long for one code.
    static func make(_ text: String, moduleSize: CGFloat = 8) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage else { return nil }
        let scaled = code.samplingNearest().transformed(by: CGAffineTransform(scaleX: moduleSize, y: moduleSize))
        let canvas = scaled.extent.insetBy(dx: -quietZone * moduleSize, dy: -quietZone * moduleSize)
        let image = scaled.composited(over: CIImage(color: .white).cropped(to: canvas))
        guard let cg = CIContext().createCGImage(image, from: canvas) else { return nil }
        return UIImage(cgImage: cg)
    }
}
