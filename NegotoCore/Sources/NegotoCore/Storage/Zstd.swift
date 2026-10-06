import Foundation
import libzstd

public enum ZstdError: Error {
    case decompressionFailed(String)
    case truncated
}

/// Streaming zstd decompression (Anki ≥2.1.50 compresses collections and media with zstd,
/// usually without a content size in the frame header, so the streaming API is required).
public enum Zstd {
    public static let magic: [UInt8] = [0x28, 0xB5, 0x2F, 0xFD]

    public static func isCompressed(_ data: Data) -> Bool {
        data.count >= 4 && Array(data.prefix(4)) == magic
    }

    public static func decompress(_ data: Data) throws -> Data {
        var out = Data()
        let decoder = try StreamDecoder()
        try decoder.feed(data) { out.append($0) }
        try decoder.finish()
        return out
    }

    /// Incremental decoder that can be fed chunks (e.g. while unzipping).
    public final class StreamDecoder {
        private let dctx: OpaquePointer
        private var outBuffer: [UInt8]
        private var lastReturn: Int = 0
        private var sawInput = false

        public init() throws {
            guard let ctx = ZSTD_createDCtx() else { throw ZstdError.decompressionFailed("ZSTD_createDCtx") }
            dctx = ctx
            outBuffer = [UInt8](repeating: 0, count: ZSTD_DStreamOutSize())
        }

        deinit { ZSTD_freeDCtx(dctx) }

        public func feed(_ chunk: Data, _ sink: (Data) throws -> Void) throws {
            guard !chunk.isEmpty else { return }
            sawInput = true
            try chunk.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
                var input = ZSTD_inBuffer(src: src.baseAddress, size: src.count, pos: 0)
                var outputFull = false
                repeat {
                    let produced: Int = try outBuffer.withUnsafeMutableBytes { dst in
                        var output = ZSTD_outBuffer(dst: dst.baseAddress, size: dst.count, pos: 0)
                        let rc = ZSTD_decompressStream(dctx, &output, &input)
                        if ZSTD_isError(rc) != 0 {
                            throw ZstdError.decompressionFailed(String(cString: ZSTD_getErrorName(rc)))
                        }
                        lastReturn = rc
                        outputFull = output.pos == output.size
                        return output.pos
                    }
                    if produced > 0 { try sink(Data(outBuffer[0..<produced])) }
                } while input.pos < input.size || outputFull
            }
        }

        public func finish() throws {
            if sawInput && lastReturn != 0 { throw ZstdError.truncated }
        }
    }
}
