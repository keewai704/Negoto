import Foundation
import CStbVorbis

/// Decodes Ogg Vorbis (common in Anki decks, unsupported by AVFoundation) into a WAV file.
public enum OggVorbis {
    public static func isOgg(_ data: Data) -> Bool {
        data.count > 4 && Array(data.prefix(4)) == Array("OggS".utf8)
    }

    public static func decodeToWAV(_ data: Data) -> Data? {
        var channels: Int32 = 0
        var sampleRate: Int32 = 0
        var output: UnsafeMutablePointer<Int16>?
        let samples = data.withUnsafeBytes { buf -> Int32 in
            guard let base = buf.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return stb_vorbis_decode_memory(base, Int32(buf.count), &channels, &sampleRate, &output)
        }
        guard samples > 0, channels > 0, let output else { return nil }
        defer { free(output) }
        let pcmBytes = Int(samples) * Int(channels) * 2
        var wav = Data(capacity: 44 + pcmBytes)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        wav.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcmBytes))
        wav.append(contentsOf: Array("WAVE".utf8))
        wav.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(UInt16(channels))
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * UInt32(channels) * 2); u16(UInt16(channels) * 2); u16(16)
        wav.append(contentsOf: Array("data".utf8)); u32(UInt32(pcmBytes))
        output.withMemoryRebound(to: UInt8.self, capacity: pcmBytes) { wav.append($0, count: pcmBytes) }
        return wav
    }
}
