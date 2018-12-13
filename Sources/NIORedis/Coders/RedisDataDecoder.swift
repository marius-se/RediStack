import Foundation
import NIO

/// Handles incoming byte messages from Redis and decodes them according to the RESP protocol.
///
/// See: https://redis.io/topics/protocol
final class RedisDataDecoder: ByteToMessageDecoder {
    /// See `ByteToMessageDecoder.cumulationBuffer`
    var cumulationBuffer: ByteBuffer?

    /// See `ByteToMessageDecoder.decode(ctx:buffer:)`
    func decode(ctx: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        var position = 0

        switch try _parse(at: &position, from: buffer) {
        case .notYetParsed:
            return .needMoreData

        case .parsed:
            return .continue
        }
    }

    private let encoding = String.Encoding.utf8

    public typealias InboundOut = Int
}

// MARK: RESP Parsing

extension UInt8 {
    static let newline: UInt8 = 0xA
    static let carriageReturn: UInt8 = 0xD
    static let dollar: UInt8 = 0x24
    static let asterisk: UInt8 = 0x2A
    static let plus: UInt8 = 0x2B
    static let hyphen: UInt8 = 0x2D
    static let colon: UInt8 = 0x3A
}

extension RedisDataDecoder {
    indirect enum _PartialRedisData {
        case notYetParsed
        #warning("parsed needs to be implemented to include RedisData!")
        case parsed
    }

    func _parse(at position: inout Int, from buffer: ByteBuffer) throws -> _PartialRedisData {
        guard let token = buffer.copyByte(at: position) else { return .notYetParsed }

        position += 1

        switch token {
        case .plus:
            guard let string = try _parseSimpleString(at: &position, from: buffer) else { return .notYetParsed }
            return .parsed
        default: return .notYetParsed
        }
    }

    func _parseSimpleString(at position: inout Int, from buffer: ByteBuffer) throws -> String? {
        let byteCount = buffer.readableBytes - position
        guard
            byteCount >= 2, // strings should at least have a CRLF line ending
            let bytes = buffer.copyBytes(at: position, length: byteCount)
        else { return nil }

        // String endings have a return carriage followed by a newline
        // Search for the first \r and to find the expected newline offset
        var expectedNewlinePosition = 0
        for offset in 0..<bytes.count {
            if bytes[offset] == .carriageReturn {
                expectedNewlinePosition = offset + 1
                break
            }
        }

        // Make sure the position is still within readable range, and that the position reality matches our
        // expectation
        guard
            expectedNewlinePosition < bytes.count,
            bytes[expectedNewlinePosition] == .newline
        else { return nil }

        // If the end of the simple string isn't more than the size of the line ending, we can shortcut
        // and return an empty string
        guard expectedNewlinePosition > 2 else { return "" }

        // Move the tip of the message position for recursive parsing to just after the newline
        position += expectedNewlinePosition + 1

        return String(bytes: bytes[ ..<(expectedNewlinePosition - 1) ], encoding: encoding)
    }
}

private extension ByteBuffer {
    /// Copies the `ByteBuffer` from the current `readerIndex`.
    ///
    ///     buffer.copyBytes(count: 5)
    ///     // Optional(5 bytes)
    ///
    /// - Parameters:
    ///     - count: The number of bytes to copy
    ///     - skipping: The amount of bytes to skip, defaulting to `0`.
    func copyBytes(count: Int, skipping: Int = 0) -> [UInt8]? {
        guard readableBytes >= count + skipping else { return nil }
        return getBytes(at: readerIndex + skipping, length: count)
    }

    /// Copies bytes from the `ByteBuffer` from at the provided position, up to the length desired.
    ///
    ///     buffer.copyBytes(at: 3, length: 2)
    ///     // Optional(2 bytes), assuming buffer contains 5 bytes
    ///
    /// - Parameters:
    ///     - at: The position offset to copy bytes from the buffer, defaulting to `0`.
    ///     - length: The number of bytes to copy.
    func copyBytes(at offset: Int = 0, length: Int) -> [UInt8]? {
        guard readableBytes >= offset + length else { return nil }
        return getBytes(at: offset + readerIndex, length: length)
    }

    /// Copies the first byte from the `ByteBuffer` at the desired position.
    ///
    ///     buffer.copyByte(at: 3)
    ///     // Optional(1 byte), assuming buffer contains 3 or more bytes
    ///
    /// - Parameter at: The position offset of the byte to be copied from the buffer.
    func copyByte(at position: Int) -> UInt8? {
        guard readableBytes >= 1 else { return nil }
        return getBytes(at: position, length: 1)?.first
    }
}