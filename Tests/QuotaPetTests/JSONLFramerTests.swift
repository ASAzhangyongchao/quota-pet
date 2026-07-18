import Foundation
import XCTest
@testable import QuotaPet

final class JSONLFramerTests: XCTestCase {
    func testFramesOneLineSplitAcrossThreeChunks() throws {
        var framer = JSONLFramer()

        XCTAssertEqual(try framer.append(Data("{\"m".utf8)), [])
        XCTAssertEqual(try framer.append(Data("ethod\":\"ok".utf8)), [])
        XCTAssertEqual(try framer.append(Data("\"}\n".utf8)), [Data("{\"method\":\"ok\"}".utf8)])
    }

    func testFramesTwoLinesFromOneChunk() throws {
        var framer = JSONLFramer()

        XCTAssertEqual(
            try framer.append(Data("{\"id\":1}\n{\"id\":2}\n".utf8)),
            [Data("{\"id\":1}".utf8), Data("{\"id\":2}".utf8)]
        )
    }

    func testStripsCarriageReturnFromCRLFFrames() throws {
        var framer = JSONLFramer()

        XCTAssertEqual(try framer.append(Data("{\"id\":1}\r\n".utf8)), [Data("{\"id\":1}".utf8)])
    }

    func testIgnoresEmptyLines() throws {
        var framer = JSONLFramer()

        XCTAssertEqual(try framer.append(Data("\n\r\n{\"id\":1}\n\n".utf8)), [Data("{\"id\":1}".utf8)])
    }

    func testRejectsCompleteFrameOverLimitAndClearsBuffer() throws {
        var framer = JSONLFramer(maxFrameBytes: 4)

        XCTAssertThrowsError(try framer.append(Data("12345\n".utf8))) {
            XCTAssertEqual($0 as? JSONLFramerError, .frameTooLarge)
        }
        XCTAssertEqual(try framer.append(Data("ok\n".utf8)), [Data("ok".utf8)])
    }

    func testRejectsUnterminatedFrameOverOneMiBAndClearsBuffer() throws {
        var framer = JSONLFramer(maxFrameBytes: 1_048_576)

        XCTAssertThrowsError(try framer.append(Data(repeating: 65, count: 1_048_577))) {
            XCTAssertEqual($0 as? JSONLFramerError, .frameTooLarge)
        }
        XCTAssertEqual(try framer.append(Data("ok\n".utf8)), [Data("ok".utf8)])
    }
}
