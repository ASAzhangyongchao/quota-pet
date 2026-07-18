import Foundation
import XCTest
@testable import QuotaPet

final class CodexRPCClientTests: XCTestCase {
    func testSendsOnlyAllowedRequestsAndInitializedNotification() async throws {
        let transport = LockedMessages()
        let client = CodexRPCClient(send: transport.send)

        let response = Task {
            try await client.request(method: "initialize", params: ["clientInfo": ["name": "QuotaPet"]])
        }
        try await waitForMessages(transport, count: 1)

        XCTAssertEqual(try message(at: 0, from: transport)["method"] as? String, "initialize")
        XCTAssertEqual(try message(at: 0, from: transport)["id"] as? Int, 1)
        try await client.receive(line(["id": 1, "result": ["ok": true]]))
        let responseData = try await response.value
        XCTAssertEqual(try JSONSerialization.jsonObject(with: responseData) as? [String: Bool], ["ok": true])

        try await client.sendInitialized()
        XCTAssertEqual(try message(at: 1, from: transport)["method"] as? String, "initialized")
        XCTAssertNil(try message(at: 1, from: transport)["id"])

        do {
            _ = try await client.request(method: "workspace/read")
            XCTFail("Expected method rejection")
        } catch let error as CodexRPCClientError {
            XCTAssertEqual(error, .methodNotAllowed("workspace/read"))
        }
    }

    func testDeliversOnlyRateLimitUpdateNotifications() async throws {
        let transport = LockedMessages()
        let updates = LockedMessages()
        let client = CodexRPCClient(send: transport.send, onRateLimitsUpdated: updates.append)

        try await client.receive(line(["method": "account/rateLimits/updated", "params": ["usedPercent": 42]]))
        try await client.receive(line(["method": "workspace/changed", "params": ["ignored": true]]))

        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: updates.data(at: 0)) as? [String: Int], ["usedPercent": 42])
    }

    func testRejectsUnknownServerRequestAndIgnoresUnknownResponseID() async throws {
        let transport = LockedMessages()
        let client = CodexRPCClient(send: transport.send)

        try await client.receive(line(["id": 99, "method": "workspace/read", "params": [:]]))
        XCTAssertEqual(try message(at: 0, from: transport)["id"] as? Int, 99)
        let error = try XCTUnwrap(try message(at: 0, from: transport)["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32601)
        XCTAssertEqual(error["message"] as? String, "Method not allowed")

        try await client.receive(line(["id": 404, "result": ["ignored": true]]))
        XCTAssertEqual(transport.count, 1)
    }

    func testRejectsFifthPendingRequestImmediately() async throws {
        let transport = LockedMessages()
        let client = CodexRPCClient(send: transport.send)
        let pending = (0..<4).map { _ in
            Task { try await client.request(method: "account/rateLimits/read") }
        }
        try await waitForMessages(transport, count: 4)

        do {
            _ = try await client.request(method: "account/rateLimits/read")
            XCTFail("Expected pending request limit")
        } catch let error as CodexRPCClientError {
            XCTAssertEqual(error, .pendingLimitReached)
        }

        for task in pending {
            task.cancel()
            _ = try? await task.value
        }
    }

    func testTimesOutWithInjectedShortTimeout() async throws {
        let transport = LockedMessages()
        let client = CodexRPCClient(send: transport.send, requestTimeout: 0.01)

        do {
            _ = try await client.request(method: "account/rateLimits/read")
            XCTFail("Expected timeout")
        } catch let error as CodexRPCClientError {
            XCTAssertEqual(error, .requestTimedOut)
        }
        XCTAssertEqual(transport.count, 1)
    }

    func testKeepsOnlyLast64KiBOfStandardError() async {
        let client = CodexRPCClient(send: { _ in })
        let prefix = Data(repeating: 65, count: 8_192)
        let suffix = Data(repeating: 66, count: 65_536)

        await client.appendStandardError(prefix)
        await client.appendStandardError(suffix)

        let tail = await client.standardErrorTail()
        XCTAssertEqual(tail, suffix)
    }

    func testRejectsOversizedInboundFrameAndRecoversAfterClearingBuffer() async throws {
        let client = CodexRPCClient(send: { _ in })

        do {
            try await client.receive(Data(repeating: 65, count: 1_048_577))
            XCTFail("Expected frame rejection")
        } catch let error as JSONLFramerError {
            XCTAssertEqual(error, .frameTooLarge)
        }
        try await client.receive(line(["method": "workspace/changed"]))
    }

    func testReportsSerializationAndInvalidMessageErrors() async throws {
        let transport = LockedMessages()
        let client = CodexRPCClient(send: transport.send)

        do {
            _ = try await client.request(method: "initialize", params: ["invalid": Date()])
            XCTFail("Expected serialization failure")
        } catch let error as CodexRPCClientError {
            XCTAssertEqual(error, .serializationFailed)
        }

        do {
            try await client.receive(Data("not json\n".utf8))
            XCTFail("Expected invalid message failure")
        } catch let error as CodexRPCClientError {
            XCTAssertEqual(error, .invalidMessage)
        }
    }

    private func line(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        return data
    }

    private func message(at index: Int, from transport: LockedMessages) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: transport.data(at: index)) as? [String: Any])
    }

    private func waitForMessages(_ transport: LockedMessages, count: Int) async throws {
        for _ in 0..<100 {
            if transport.count >= count { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Timed out waiting for \(count) messages")
    }
}

private final class LockedMessages: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [Data] = []

    var send: (Data) throws -> Void {
        { [weak self] data in self?.append(data) }
    }

    var count: Int {
        lock.withLock { messages.count }
    }

    func append(_ data: Data) {
        lock.withLock { messages.append(data) }
    }

    func data(at index: Int) -> Data {
        lock.withLock { messages[index] }
    }
}
