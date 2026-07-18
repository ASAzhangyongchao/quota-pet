import Foundation

enum CodexRPCClientError: Error, Equatable {
    case methodNotAllowed(String)
    case pendingLimitReached
    case requestTimedOut
    case serializationFailed
    case invalidMessage
    case remoteError
    case sendFailed
}

actor CodexRPCClient {
    private static let maximumPendingRequests = 4
    private static let standardErrorLimit = 64 * 1_024
    private static let requestMethods: Set<String> = ["initialize", "account/rateLimits/read"]

    private struct PendingRequest {
        let continuation: CheckedContinuation<Data, Error>
        let timeoutTask: Task<Void, Never>
    }

    private let send: (Data) throws -> Void
    private let onRateLimitsUpdated: ((Data) -> Void)?
    private let requestTimeout: TimeInterval
    private var framer = JSONLFramer()
    private var nextID = 1
    private var pending: [Int: PendingRequest] = [:]
    private var standardError = Data()

    init(
        send: @escaping (Data) throws -> Void,
        onRateLimitsUpdated: ((Data) -> Void)? = nil,
        requestTimeout: TimeInterval = 15
    ) {
        self.send = send
        self.onRateLimitsUpdated = onRateLimitsUpdated
        self.requestTimeout = max(0, requestTimeout)
    }

    func request(method: String, params: [String: Any] = [:]) async throws -> Data {
        guard Self.requestMethods.contains(method) else {
            throw CodexRPCClientError.methodNotAllowed(method)
        }
        guard pending.count < Self.maximumPendingRequests else {
            throw CodexRPCClientError.pendingLimitReached
        }
        guard JSONSerialization.isValidJSONObject(params) else {
            throw CodexRPCClientError.serializationFailed
        }

        let id = nextID
        nextID += 1
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]
        let payload = try encodeJSONObject(message)
        return try await enqueue(id: id, payload: payload)
    }

    func sendInitialized(params: [String: Any] = [:]) throws {
        guard JSONSerialization.isValidJSONObject(params) else {
            throw CodexRPCClientError.serializationFailed
        }
        try sendLine(try encodeJSONObject([
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": params,
        ]))
    }

    func receive(_ chunk: Data) throws {
        for frame in try framer.append(chunk) {
            try handle(frame)
        }
    }

    func appendStandardError(_ chunk: Data) {
        standardError.append(chunk)
        let excess = standardError.count - Self.standardErrorLimit
        if excess > 0 {
            standardError.removeFirst(excess)
        }
    }

    func standardErrorTail() -> Data {
        standardError
    }

    private func enqueue(id: Int, payload: Data) async throws -> Data {
        try await withTaskCancellationHandler(operation: {
            if Task.isCancelled {
                throw CancellationError()
            }
            return try await withCheckedThrowingContinuation { continuation in
                let timeout = requestTimeout
                let timeoutTask = Task { [weak self] in
                    if timeout > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    }
                    guard !Task.isCancelled else { return }
                    await self?.complete(id: id, with: .failure(CodexRPCClientError.requestTimedOut))
                }
                pending[id] = PendingRequest(continuation: continuation, timeoutTask: timeoutTask)
                do {
                    try sendLine(payload)
                } catch {
                    complete(id: id, with: .failure(CodexRPCClientError.sendFailed))
                }
            }
        }, onCancel: { [weak self] in
            Task {
                await self?.complete(id: id, with: .failure(CancellationError()))
            }
        })
    }

    private func handle(_ frame: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: frame),
              let message = object as? [String: Any]
        else {
            throw CodexRPCClientError.invalidMessage
        }

        if let method = message["method"] as? String {
            if let id = message["id"] {
                try rejectServerRequest(id: id)
            } else if method == "account/rateLimits/updated", let params = message["params"] {
                onRateLimitsUpdated?(try encodeJSONValue(params))
            }
            return
        }

        guard let id = message["id"] as? Int else {
            throw CodexRPCClientError.invalidMessage
        }
        guard pending[id] != nil else {
            return
        }
        if message["error"] != nil {
            complete(id: id, with: .failure(CodexRPCClientError.remoteError))
        } else if let result = message["result"] {
            complete(id: id, with: .success(try encodeJSONValue(result)))
        } else {
            complete(id: id, with: .failure(CodexRPCClientError.invalidMessage))
        }
    }

    private func rejectServerRequest(id: Any) throws {
        try sendLine(try encodeJSONObject([
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": -32601,
                "message": "Method not allowed",
            ],
        ]))
    }

    private func complete(id: Int, with result: Result<Data, Error>) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeoutTask.cancel()
        request.continuation.resume(with: result)
    }

    private func sendLine(_ data: Data) throws {
        var line = data
        line.append(0x0A)
        try send(line)
    }

    private func encodeJSONObject(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object)
        else {
            throw CodexRPCClientError.serializationFailed
        }
        return data
    }

    private func encodeJSONValue(_ value: Any) throws -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) else {
            throw CodexRPCClientError.invalidMessage
        }
        return data
    }
}
