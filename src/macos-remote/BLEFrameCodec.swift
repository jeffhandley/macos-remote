import Foundation

public enum BLEFrameError: Error, Equatable {
    case frameTooSmall
    case invalidHeader
    case unsupportedVersion
    case invalidIndex
    case tooManyFrames
    case duplicateFrame
    case assembledMessageTooLarge
    case tooManyAssemblies
}

public enum BLEFrameCodec {
    public static let headerSize = 15
    public static let version: UInt8 = 1
    private static let magic: [UInt8] = [0x4d, 0x52]

    public static func frames(
        for payload: Data,
        maximumFrameSize: Int,
        messageID: UUID = UUID()
    ) throws -> [Data] {
        guard maximumFrameSize > headerSize else {
            throw BLEFrameError.frameTooSmall
        }

        let payloadCapacity = maximumFrameSize - headerSize
        let frameCount = max(1, Int(ceil(Double(payload.count) / Double(payloadCapacity))))
        guard frameCount <= Int(UInt16.max) else {
            throw BLEFrameError.tooManyFrames
        }

        return (0 ..< frameCount).map { index in
            let start = index * payloadCapacity
            let end = min(start + payloadCapacity, payload.count)
            var frame = Data(magic)
            frame.append(version)
            var uuid = messageID.uuid
            withUnsafeBytes(of: &uuid) { frame.append(contentsOf: $0.prefix(8)) }
            frame.appendUInt16(UInt16(index))
            frame.appendUInt16(UInt16(frameCount))
            if start < end {
                let payloadStart = payload.index(payload.startIndex, offsetBy: start)
                let payloadEnd = payload.index(payload.startIndex, offsetBy: end)
                frame.append(payload[payloadStart ..< payloadEnd])
            }
            return frame
        }
    }

    fileprivate static func decode(_ frame: Data) throws -> DecodedFrame {
        guard frame.count >= headerSize else {
            throw BLEFrameError.invalidHeader
        }
        let bytes = [UInt8](frame)
        guard Array(bytes[0 ..< 2]) == magic else {
            throw BLEFrameError.invalidHeader
        }
        guard bytes[2] == version else {
            throw BLEFrameError.unsupportedVersion
        }

        let messageID = UUID(uuid: (
            bytes[3], bytes[4], bytes[5], bytes[6],
            bytes[7], bytes[8], bytes[9], bytes[10],
            0, 0, 0, 0, 0, 0, 0, 0
        ))
        let index = Int(UInt16(bytes[11]) << 8 | UInt16(bytes[12]))
        let count = Int(UInt16(bytes[13]) << 8 | UInt16(bytes[14]))
        guard count > 0, index < count else {
            throw BLEFrameError.invalidIndex
        }
        return DecodedFrame(
            messageID: messageID,
            index: index,
            count: count,
            payload: Data(frame.dropFirst(headerSize))
        )
    }
}

public struct BLEFrameAssembler: Sendable {
    private struct Assembly: Sendable {
        let count: Int
        let createdAt: Date
        var chunks: [Int: Data]
    }

    private var assemblies: [UUID: Assembly] = [:]
    private let timeout: TimeInterval
    private let maximumMessageSize: Int
    private let maximumAssemblies: Int

    public init(
        timeout: TimeInterval = 10,
        maximumMessageSize: Int = WireCodec.maximumMessageSize,
        maximumAssemblies: Int = 8
    ) {
        self.timeout = timeout
        self.maximumMessageSize = maximumMessageSize
        self.maximumAssemblies = maximumAssemblies
    }

    public mutating func accept(_ frame: Data, now: Date = Date()) throws -> Data? {
        assemblies = assemblies.filter { now.timeIntervalSince($0.value.createdAt) <= timeout }
        let decoded = try BLEFrameCodec.decode(frame)
        guard assemblies[decoded.messageID] != nil || assemblies.count < maximumAssemblies else {
            throw BLEFrameError.tooManyAssemblies
        }

        var assembly = assemblies[decoded.messageID]
            ?? Assembly(count: decoded.count, createdAt: now, chunks: [:])
        guard assembly.count == decoded.count else {
            assemblies.removeValue(forKey: decoded.messageID)
            throw BLEFrameError.invalidIndex
        }
        if let existing = assembly.chunks[decoded.index] {
            guard existing == decoded.payload else {
                assemblies.removeValue(forKey: decoded.messageID)
                throw BLEFrameError.duplicateFrame
            }
            return nil
        }

        assembly.chunks[decoded.index] = decoded.payload
        let assembledSize = assembly.chunks.values.reduce(0) { $0 + $1.count }
        guard assembledSize <= maximumMessageSize else {
            assemblies.removeValue(forKey: decoded.messageID)
            throw BLEFrameError.assembledMessageTooLarge
        }

        guard assembly.chunks.count == assembly.count else {
            assemblies[decoded.messageID] = assembly
            return nil
        }

        var payload = Data()
        for index in 0 ..< assembly.count {
            guard let chunk = assembly.chunks[index] else {
                assemblies[decoded.messageID] = assembly
                return nil
            }
            payload.append(chunk)
        }
        assemblies.removeValue(forKey: decoded.messageID)
        return payload
    }
}

private struct DecodedFrame {
    let messageID: UUID
    let index: Int
    let count: Int
    let payload: Data
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0xff))
    }
}
