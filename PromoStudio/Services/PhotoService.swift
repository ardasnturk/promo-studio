import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Real photos in videos (players from the web, the user's uploads): resized for rendering and cut out of their background on the Mac.
enum PhotoService {
    /// Writes the image upright and at most `maxSide` px on its long side: PNG if it has transparency, otherwise JPEG.
    /// Returns the file written (the extension follows the format), nil if the data isn't an image.
    static func normalize(_ data: Data, to base: URL, maxSide: Int = 1800) -> URL? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxSide,
              ] as CFDictionary) else { return nil }
        let alpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let url = base.appendingPathExtension(alpha ? "png" : "jpg")
        guard write(image, to: url, type: alpha ? .png : .jpeg) else { return nil }
        return url
    }

    /// Removes the background around the photo's subject (a person, or the main object) with Vision.
    /// Writes a PNG cropped to the subject; false if Vision finds no subject.
    static func cutout(_ input: URL, to output: URL) async -> Bool {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
                guard let result = request.results?.first, !result.allInstances.isEmpty else { return false }
                let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
                let masked = CIImage(cvPixelBuffer: buffer)
                guard let cut = CIContext().createCGImage(masked, from: masked.extent) else { return false }
                return write(cut, to: output, type: .png)
            } catch {
                return false
            }
        }.value
    }

    private static func write(_ image: CGImage, to url: URL, type: UTType) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary : nil)
        return CGImageDestinationFinalize(dest)
    }
}
