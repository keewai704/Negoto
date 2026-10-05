import Foundation

/// Minimal protobuf wire-format reader, enough to decode the config blobs that Anki (schema ≥15)
/// stores in its notetypes/templates/fields/decks/deck_config tables and package metadata.
public struct ProtoMessage {
    public enum Value {
        case varint(UInt64)
        case fixed64(UInt64)
        case fixed32(UInt32)
        case bytes(Data)
    }

    public private(set) var fields: [(Int, Value)] = []

    public init(_ data: Data) {
        let bytes = [UInt8](data)
        var i = 0
        func readVarint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while i < bytes.count {
                let b = bytes[i]; i += 1
                result |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { return result }
                shift += 7
                if shift > 63 { return nil }
            }
            return nil
        }
        while i < bytes.count {
            guard let key = readVarint() else { break }
            let field = Int(key >> 3)
            switch key & 7 {
            case 0:
                guard let v = readVarint() else { return }
                fields.append((field, .varint(v)))
            case 1:
                guard i + 8 <= bytes.count else { return }
                var v: UInt64 = 0
                for k in 0..<8 { v |= UInt64(bytes[i + k]) << (8 * UInt64(k)) }
                i += 8
                fields.append((field, .fixed64(v)))
            case 2:
                guard let len = readVarint(), i + Int(len) <= bytes.count else { return }
                fields.append((field, .bytes(Data(bytes[i..<(i + Int(len))]))))
                i += Int(len)
            case 5:
                guard i + 4 <= bytes.count else { return }
                var v: UInt32 = 0
                for k in 0..<4 { v |= UInt32(bytes[i + k]) << (8 * UInt32(k)) }
                i += 4
                fields.append((field, .fixed32(v)))
            default:
                return
            }
        }
    }

    private func last(_ field: Int) -> Value? { fields.last(where: { $0.0 == field })?.1 }

    public func has(_ field: Int) -> Bool { last(field) != nil }

    public func uint(_ field: Int) -> UInt64? {
        if case .varint(let v)? = last(field) { return v }
        return nil
    }

    public func int(_ field: Int) -> Int64? { uint(field).map { Int64(bitPattern: $0) } }

    public func bool(_ field: Int) -> Bool? { uint(field).map { $0 != 0 } }

    public func float(_ field: Int) -> Float? {
        if case .fixed32(let v)? = last(field) { return Float(bitPattern: v) }
        return nil
    }

    public func string(_ field: Int) -> String? {
        if case .bytes(let d)? = last(field) { return String(decoding: d, as: UTF8.self) }
        return nil
    }

    public func bytes(_ field: Int) -> Data? {
        if case .bytes(let d)? = last(field) { return d }
        return nil
    }

    public func message(_ field: Int) -> ProtoMessage? { bytes(field).map(ProtoMessage.init) }

    public func messages(_ field: Int) -> [ProtoMessage] {
        fields.compactMap { f, v in
            if f == field, case .bytes(let d) = v { return ProtoMessage(d) }
            return nil
        }
    }

    /// Repeated float, packed (proto3 default) or unpacked.
    public func floats(_ field: Int) -> [Float] {
        var out: [Float] = []
        for (f, v) in fields where f == field {
            switch v {
            case .fixed32(let x): out.append(Float(bitPattern: x))
            case .bytes(let d):
                let b = [UInt8](d)
                var i = 0
                while i + 4 <= b.count {
                    let x = UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
                    out.append(Float(bitPattern: x))
                    i += 4
                }
            default: break
            }
        }
        return out
    }
}
