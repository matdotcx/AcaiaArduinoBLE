import XCTest
@testable import ShotTelemetryKit

final class FirmwareUploaderTests: XCTestCase {

    func testMultipartBodyFraming() {
        let payload = Data([0x01, 0x02, 0x03, 0xFF])
        let body = FirmwareUploader.multipartBody(
            boundary: "BND", fieldName: "update", fileName: "fw.bin", fileData: payload)
        let text = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(text.hasPrefix("--BND\r\n"))
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"update\"; filename=\"fw.bin\""))
        XCTAssertTrue(text.contains("Content-Type: application/octet-stream\r\n\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n--BND--\r\n"))
    }

    func testMultipartBodyEmbedsRawBytes() {
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let body = FirmwareUploader.multipartBody(
            boundary: "B", fieldName: "update", fileName: "f.bin", fileData: payload)
        // The 4 payload bytes appear contiguously somewhere in the body.
        XCTAssertNotNil(body.range(of: payload))
    }
}
