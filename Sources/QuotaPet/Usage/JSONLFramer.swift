import Foundation

enum JSONLFramerError: Error, Equatable {
    case frameTooLarge
}

struct JSONLFramer {
    let maxFrameBytes: Int
    private(set) var buffer = Data()

    init(maxFrameBytes: Int = 1_048_576) {
        self.maxFrameBytes = maxFrameBytes
    }

    mutating func append(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)
        var frames: [Data] = []

        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            var frame = buffer[..<newlineIndex]
            if frame.last == 0x0D {
                frame = frame.dropLast()
            }
            guard frame.count <= maxFrameBytes else {
                buffer.removeAll(keepingCapacity: false)
                throw JSONLFramerError.frameTooLarge
            }
            if !frame.isEmpty {
                frames.append(Data(frame))
            }
            buffer.removeSubrange(...newlineIndex)
        }

        guard buffer.count <= maxFrameBytes else {
            buffer.removeAll(keepingCapacity: false)
            throw JSONLFramerError.frameTooLarge
        }
        return frames
    }
}
