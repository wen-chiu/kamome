#if canImport(CoreImage)
import CoreGraphics
import CoreImage
import Foundation

/// "Get this route" QR for the end card (§4.5 step 4). Rendered nearest-
/// neighbor so modules stay crisp at frame resolution; the software renderer
/// keeps output identical on simulator and device.
public enum RecapQRCode {
    public static func image(for text: String, sidePx: Int) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }
        let scale = (Double(sidePx) / output.extent.width).rounded(.up)
        let scaled = output.samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        return context.createCGImage(scaled, from: scaled.extent)
    }
}
#endif
