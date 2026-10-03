import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import HatangChat

final class ImageScalingTests: XCTestCase {
    func testFitKeepsSmallImages() {
        XCTAssertTrue(ImageScaling.fit(800, 600) == (800, 600))
        XCTAssertTrue(ImageScaling.fit(2048, 1024) == (2048, 1024))
    }

    func testFitScalesTheLongerSideTo2048() {
        XCTAssertTrue(ImageScaling.fit(4032, 3024) == (2048, 1536))
        XCTAssertTrue(ImageScaling.fit(3024, 4032) == (1536, 2048))
        XCTAssertTrue(ImageScaling.fit(10000, 3) == (2048, 1))
        XCTAssertTrue(ImageScaling.fit(0, 0) == (0, 0))
    }

    func testReencodeRules() {
        let limit = 10 * 1024 * 1024
        XCTAssertTrue(ImageScaling.needsReencode(mimeType: "image/heic", size: 100, limit: limit))
        XCTAssertTrue(ImageScaling.needsReencode(mimeType: "image/heif", size: 100, limit: limit))
        XCTAssertTrue(ImageScaling.needsReencode(mimeType: "image/jpeg", size: 3 * 1024 * 1024, limit: limit))
        XCTAssertTrue(ImageScaling.needsReencode(mimeType: "image/png", size: 11 * 1024 * 1024, limit: limit))
        XCTAssertFalse(ImageScaling.needsReencode(mimeType: "image/jpeg", size: 1024 * 1024, limit: limit))
        XCTAssertFalse(ImageScaling.needsReencode(mimeType: "image/png", size: 3 * 1024 * 1024, limit: limit))
        XCTAssertFalse(ImageScaling.needsReencode(mimeType: "image/gif", size: 11 * 1024 * 1024, limit: limit))
        XCTAssertFalse(ImageScaling.needsReencode(mimeType: "application/pdf", size: 11 * 1024 * 1024, limit: limit))
    }

    func testRenamesTheExtension() {
        XCTAssertEqual(ImageScaling.withExtension("IMG_1.HEIC", "jpg"), "IMG_1.jpg")
        XCTAssertEqual(ImageScaling.withExtension("photo", "jpg"), "photo.jpg")
        XCTAssertEqual(ImageScaling.withExtension(".hidden", "jpg"), ".hidden.jpg")
    }

    func testMimeTypes() {
        XCTAssertEqual(AttachmentPreparer.mimeType(name: "a.pdf", type: .pdf), "application/pdf")
        XCTAssertEqual(AttachmentPreparer.mimeType(name: "a.HEIC", type: .heic), "image/heic")
        XCTAssertEqual(AttachmentPreparer.mimeType(name: "report.xlsx", type: nil), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        XCTAssertEqual(AttachmentPreparer.mimeType(name: "blob", type: nil), "application/octet-stream")
    }

    private func encode(_ type: UTType, width: Int, height: Int) throws -> Data {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(red: 0.1, green: 0.6, blue: 0.9, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(ctx.makeImage())
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    private func pixelSize(_ data: Data) -> (Int, Int, String?) {
        let src = CGImageSourceCreateWithData(data as CFData, nil)!
        let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
        return (p[kCGImagePropertyPixelWidth] as! Int, p[kCGImagePropertyPixelHeight] as! Int, CGImageSourceGetType(src) as String?)
    }

    func testHeicBecomesAJpegCappedAt2048() throws {
        let heic = try encode(.heic, width: 3000, height: 2000)
        let out = try AttachmentPreparer.prepare(heic, name: "IMG_0001.HEIC", mimeType: "image/heic")
        XCTAssertEqual(out.mimeType, "image/jpeg")
        XCTAssertEqual(out.name, "IMG_0001.jpg")
        let (w, h, type) = pixelSize(out.data)
        XCTAssertEqual(type, UTType.jpeg.identifier)
        XCTAssertEqual(w, 2048)
        XCTAssertTrue((1365...1366).contains(h), "\(h)") // ImageIO rounds up
    }

    func testSmallPngPassesThrough() throws {
        let png = try encode(.png, width: 40, height: 30)
        let out = try AttachmentPreparer.prepare(png, name: "a.png", mimeType: "image/png")
        XCTAssertEqual(out.data, png)
        XCTAssertEqual(out.mimeType, "image/png")
    }

    func testLargeFilesAndUnknownTypesAreRefused() {
        let big = Data(count: 10 * 1024 * 1024 + 1)
        XCTAssertThrowsError(try AttachmentPreparer.prepare(big, name: "a.pdf", mimeType: "application/pdf")) {
            XCTAssertEqual(($0 as? HatangError)?.code, "file_too_large")
        }
        XCTAssertThrowsError(try AttachmentPreparer.prepare(Data([1, 2]), name: "a.exe", mimeType: "application/x-msdownload")) {
            XCTAssertEqual(($0 as? HatangError)?.code, "unsupported_file_type")
        }
    }
}
