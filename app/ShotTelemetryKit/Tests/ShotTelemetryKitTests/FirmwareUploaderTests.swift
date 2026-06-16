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

    func testProgressFractionMath() {
        XCTAssertEqual(FirmwareUploader.progressFraction(totalBytesSent: 0, totalBytesExpectedToSend: 100), 0)
        XCTAssertEqual(FirmwareUploader.progressFraction(totalBytesSent: 50, totalBytesExpectedToSend: 100), 0.5)
        XCTAssertEqual(FirmwareUploader.progressFraction(totalBytesSent: 100, totalBytesExpectedToSend: 100), 1)
        // Unknown total → nil so the progress update is skipped, not divided by zero.
        XCTAssertNil(FirmwareUploader.progressFraction(totalBytesSent: 5, totalBytesExpectedToSend: 0))
        XCTAssertNil(FirmwareUploader.progressFraction(totalBytesSent: 5, totalBytesExpectedToSend: -1))
    }

    /// Regression for F-001: `URLSession` delivers `didSendBodyData` on its own
    /// (background) delegate queue, not the main actor. Invoking the progress
    /// delegate off the main thread must return normally — the old code called
    /// `MainActor.assumeIsolated` here, which traps off the main actor and aborts
    /// the upload (and, here, the test process).
    func testProgressCallbackIsSafeOffTheMainThread() {
        let uploader = MainActor.assumeIsolated { FirmwareUploader() }
        let task = URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1/update")!)
        let returned = expectation(description: "delegate returned off the main thread")
        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertFalse(Thread.isMainThread)
            uploader.urlSession(.shared, task: task, didSendBodyData: 8,
                                totalBytesSent: 8, totalBytesExpectedToSend: 16)
            returned.fulfill()
        }
        wait(for: [returned], timeout: 2)
    }
}
