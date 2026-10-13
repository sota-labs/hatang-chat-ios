import Foundation
#if canImport(CoreImage)
import CoreGraphics
import CoreImage
#endif

/// What the payment card draws its VietQR code from.
public enum PaymentQRSource: Sendable, Hashable {
    /// The EMVCo string: drawn natively (`PaymentQR.image(payload:)`).
    case payload(String)
    /// A raster image (PNG, JPEG, GIF, WebP) served at `qr_image_url`.
    case image(Data)
}

/// Why no QR code could be found.
public enum PaymentQRError: Error, Sendable, Equatable {
    /// No payload and no usable image URL.
    case noSource
    /// The server answered with this status.
    case http(Int)
    /// The answer was neither a raster image nor a checkout with a payload (e.g. an SVG).
    case undecodable
}

/// Finds and draws the VietQR code of a payment card.
///
/// `qr_image_url` points at the gateway's `/pay/{id}/qr.svg`, which iOS cannot decode (`AsyncImage` and
/// `UIImage(data:)` have no SVG support). The code itself is just the EMVCo payload, so the SDK draws it
/// with CoreImage: from the card's payload when it carries one, else from the public checkout JSON next to
/// the SVG (`GET /pay/{id}` → `qr.payload`). Any other URL is fetched and used when it is a raster image.
public enum PaymentQR {
    /// The checkout JSON for an image URL of the form `…/pay/{id}/qr.svg` (or `qr.png`), else nil.
    public static func checkoutURL(forImageURL url: URL) -> URL? {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let parts = c.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 3, let last = parts.last, last == "qr.svg" || last == "qr.png",
              parts[parts.count - 3] == "pay", !parts[parts.count - 2].isEmpty else { return nil }
        c.path = parts.dropLast().joined(separator: "/")
        c.query = nil
        c.fragment = nil
        return c.url
    }

    /// The bytes start like a PNG, JPEG, GIF or WebP file.
    public static func isRaster(_ data: Data) -> Bool {
        let b = [UInt8](data.prefix(12))
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true }   // PNG
        if b.starts(with: [0xFF, 0xD8, 0xFF]) { return true }         // JPEG
        if b.starts(with: [0x47, 0x49, 0x46, 0x38]) { return true }   // GIF
        if b.count >= 12, b.starts(with: [0x52, 0x49, 0x46, 0x46]), Array(b[8..<12]) == [0x57, 0x45, 0x42, 0x50] { return true } // WebP
        return false
    }

    /// Where to draw `card`'s QR from: its payload, the checkout's payload, or a raster image.
    public static func resolve(_ card: PaymentCard, session: URLSession = .shared, timeout: TimeInterval = 15) async throws -> PaymentQRSource {
        if let p = card.qrPayload, !p.isEmpty { return .payload(p) }
        guard let url = URL(string: card.qrImageUrl), url.scheme?.hasPrefix("http") == true else { throw PaymentQRError.noSource }
        if let checkout = checkoutURL(forImageURL: url) {
            let data = try await get(checkout, accept: "application/json", session: session, timeout: timeout)
            if let p = JSONValue.parse(data)?.objectValue?.obj("qr")?.str("payload"), !p.isEmpty { return .payload(p) }
            throw PaymentQRError.undecodable
        }
        let data = try await get(url, accept: "image/png,image/jpeg,image/*;q=0.8", session: session, timeout: timeout)
        guard isRaster(data) else { throw PaymentQRError.undecodable }
        return .image(data)
    }

    private static func get(_ url: URL, accept: String, session: URLSession, timeout: TimeInterval) async throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PaymentQRError.http(http.statusCode)
        }
        return data
    }

    #if canImport(CoreImage)
    /// The QR code for `payload`, one pixel per module plus a quiet zone; scale it without interpolation.
    public static func image(payload: String, correctionLevel: String = "M") -> CGImage? {
        guard !payload.isEmpty, let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue(correctionLevel, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: output.extent)
    }
    #endif
}
