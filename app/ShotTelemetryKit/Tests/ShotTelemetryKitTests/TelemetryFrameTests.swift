import XCTest
@testable import ShotTelemetryKit

final class TelemetryFrameTests: XCTestCase {

    func testRoundTrip() throws {
        let data = TelemetryFrame.encode(
            tMs: 12345,
            weightG: 18.4,
            flowGps: 2.1,
            state: .brew,
            scaleConnected: true,
            setpointReached: false,
            setpointG: 36.0
        )
        let f = try XCTUnwrap(TelemetryFrame(data))
        XCTAssertEqual(f.tMs, 12345)
        XCTAssertEqual(f.weightG, 18.4, accuracy: 0.0001)
        XCTAssertEqual(f.flowGps, 2.1, accuracy: 0.0001)
        XCTAssertEqual(f.state, .brew)
        XCTAssertEqual(f.rawState, 2)
        XCTAssertTrue(f.scaleConnected)
        XCTAssertFalse(f.setpointReached)
        XCTAssertEqual(f.setpointG, 36.0, accuracy: 0.01)
        XCTAssertEqual(f.elapsed, 12.345, accuracy: 0.0001)
    }

    func testLittleEndianLayout() {
        // t_ms = 1 must serialize as 01 00 00 00; frame is exactly 16 bytes.
        let data = TelemetryFrame.encode(
            tMs: 1, weightG: 0, flowGps: 0, state: .idle,
            scaleConnected: false, setpointReached: false, setpointG: 0
        )
        let bytes = [UInt8](data)
        XCTAssertEqual(data.count, 16)
        XCTAssertEqual(bytes[0], 1)
        XCTAssertEqual(bytes[1], 0)
        XCTAssertEqual(bytes[2], 0)
        XCTAssertEqual(bytes[3], 0)
        XCTAssertEqual(bytes[12], 0) // state idle
    }

    func testFlagsBoth() throws {
        let data = TelemetryFrame.encode(
            tMs: 0, weightG: 0, flowGps: 0, state: .done,
            scaleConnected: true, setpointReached: true, setpointG: 0
        )
        let f = try XCTUnwrap(TelemetryFrame(data))
        XCTAssertTrue(f.scaleConnected)
        XCTAssertTrue(f.setpointReached)
        XCTAssertEqual(f.flags, 0x03)
        XCTAssertEqual(f.state, .done)
    }

    func testUnknownStatePreservesRawByte() {
        // 0xFF is not a defined state; decode to .unknown but keep the raw byte.
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[12] = 0x07
        let f = TelemetryFrame(Data(bytes))
        XCTAssertEqual(f?.state, .unknown)
        XCTAssertEqual(f?.rawState, 7)
    }

    func testTooShortReturnsNil() {
        XCTAssertNil(TelemetryFrame(Data([0, 1, 2])))
    }

    func testEndReasonRoundTrip() throws {
        // Each reason survives the flags bits-2-4 round trip on a done frame,
        // and the scaleConnected/setpointReached bits are unaffected.
        for reason in [TelemetryFrame.EndReason.button, .weight, .time, .disconnect] {
            let data = TelemetryFrame.encode(
                tMs: 0, weightG: 0, flowGps: 0, state: .done,
                scaleConnected: true, setpointReached: true, setpointG: 36, endReason: reason
            )
            let f = try XCTUnwrap(TelemetryFrame(data))
            XCTAssertEqual(f.endReason, reason)
            XCTAssertTrue(f.scaleConnected)
            XCTAssertTrue(f.setpointReached)
        }
    }

    func testEndReasonAbsentReadsNone() throws {
        // A frame with no end-reason bits (e.g. a brew frame or legacy firmware)
        // must read .none — NOT .button — so old shots aren't mislabelled.
        let brew = try XCTUnwrap(TelemetryFrame(TelemetryFrame.encode(
            tMs: 100, weightG: 10, flowGps: 1, state: .brew,
            scaleConnected: true, setpointReached: false, setpointG: 36)))
        XCTAssertEqual(brew.endReason, .none)
    }
}
