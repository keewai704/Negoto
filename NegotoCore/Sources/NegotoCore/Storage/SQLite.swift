import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite error \(code): \(message)" }
}

/// A value read from or bound to SQLite.
public enum SQLValue: Equatable, Sendable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)

    public var int64: Int64 {
        switch self {
        case .int(let v): return v
        case .double(let v): return Int64(v)
        case .text(let s): return Int64(s) ?? Int64(Double(s) ?? 0)
        default: return 0
        }
    }

    public var int: Int { Int(truncatingIfNeeded: int64) }

    public var double: Double {
        switch self {
        case .int(let v): return Double(v)
        case .double(let v): return v
        case .text(let s): return Double(s) ?? 0
        default: return 0
        }
    }

    public var string: String {
        switch self {
        case .text(let s): return s
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .blob(let d): return String(decoding: d, as: UTF8.self)
        case .null: return ""
        }
    }

    public var data: Data {
        switch self {
        case .blob(let d): return d
        case .text(let s): return Data(s.utf8)
        default: return Data()
        }
    }

    public var isNull: Bool { self == .null }
}

public protocol SQLBindable {
    var sqlValue: SQLValue { get }
}

extension Int: SQLBindable { public var sqlValue: SQLValue { .int(Int64(self)) } }
extension Int64: SQLBindable { public var sqlValue: SQLValue { .int(self) } }
extension Int32: SQLBindable { public var sqlValue: SQLValue { .int(Int64(self)) } }
extension Double: SQLBindable { public var sqlValue: SQLValue { .double(self) } }
extension String: SQLBindable { public var sqlValue: SQLValue { .text(self) } }
extension Data: SQLBindable { public var sqlValue: SQLValue { .blob(self) } }
extension Bool: SQLBindable { public var sqlValue: SQLValue { .int(self ? 1 : 0) } }
extension SQLValue: SQLBindable { public var sqlValue: SQLValue { self } }

public struct SQLRow {
    public let values: [SQLValue]
    public let columns: [String]

    public subscript(_ index: Int) -> SQLValue { index < values.count ? values[index] : .null }

    public subscript(_ name: String) -> SQLValue {
        guard let i = columns.firstIndex(of: name) else { return .null }
        return values[i]
    }
}

/// Thin, dependency-free SQLite wrapper. Not thread-safe; confine each instance to one actor/queue.
public final class SQLiteDatabase {
    private(set) var handle: OpaquePointer?
    public let path: String

    public init(path: String, readOnly: Bool = false) throws {
        self.path = path
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(path, &db, flags | SQLITE_OPEN_NOMUTEX, nil)
        guard rc == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            sqlite3_close(db)
            throw SQLiteError(code: rc, message: msg)
        }
        handle = db
        sqlite3_busy_timeout(db, 5000)
        registerAnkiExtensions()
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    public func close() {
        if let handle { sqlite3_close_v2(handle) }
        handle = nil
    }

    /// Anki's Rust backend declares some columns with `COLLATE unicase` and uses custom SQL
    /// functions in a few indexes. Without these, SQLite refuses to touch those tables.
    private func registerAnkiExtensions() {
        sqlite3_create_collation_v2(handle, "unicase", SQLITE_UTF8, nil, { _, l1, p1, l2, p2 in
            let a = String(decoding: UnsafeRawBufferPointer(start: p1, count: Int(l1)), as: UTF8.self)
            let b = String(decoding: UnsafeRawBufferPointer(start: p2, count: Int(l2)), as: UTF8.self)
            switch a.compare(b, options: [.caseInsensitive]) {
            case .orderedAscending: return -1
            case .orderedDescending: return 1
            case .orderedSame: return 0
            }
        }, nil)
        // field_at_index(flds, idx) is referenced by some Anki versions' indexes/queries.
        sqlite3_create_function_v2(handle, "field_at_index", 2, SQLITE_UTF8 | SQLITE_DETERMINISTIC, nil, { ctx, argc, argv in
            guard let argv, argc == 2, let raw = sqlite3_value_text(argv[0]) else {
                sqlite3_result_null(ctx); return
            }
            let s = String(cString: raw)
            let idx = Int(sqlite3_value_int64(argv[1]!))
            let parts = s.split(separator: "\u{1f}", omittingEmptySubsequences: false)
            let v = idx >= 0 && idx < parts.count ? String(parts[idx]) : ""
            sqlite3_result_text(ctx, v, -1, SQLITE_TRANSIENT)
        }, nil, nil, nil)
        // regexp(pattern, text) — used by `REGEXP` searches.
        sqlite3_create_function_v2(handle, "regexp", 2, SQLITE_UTF8 | SQLITE_DETERMINISTIC, nil, { ctx, argc, argv in
            guard let argv, argc == 2, let p = sqlite3_value_text(argv[0]), let t = sqlite3_value_text(argv[1]) else {
                sqlite3_result_int(ctx, 0); return
            }
            let pattern = String(cString: p), text = String(cString: t)
            let ok = (try? NSRegularExpression(pattern: pattern))?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            sqlite3_result_int(ctx, ok ? 1 : 0)
        }, nil, nil, nil)
    }

    private func lastError(_ rc: Int32) -> SQLiteError {
        SQLiteError(code: rc, message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "closed")
    }

    public func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? ""
            sqlite3_free(err)
            throw SQLiteError(code: rc, message: msg)
        }
    }

    private func prepare(_ sql: String, _ args: [SQLBindable]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else { throw lastError(rc) }
        for (i, arg) in args.enumerated() {
            let idx = Int32(i + 1)
            switch arg.sqlValue {
            case .null: sqlite3_bind_null(stmt, idx)
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): sqlite3_bind_double(stmt, idx, v)
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case .blob(let d):
                d.withUnsafeBytes { buf in
                    _ = sqlite3_bind_blob(stmt, idx, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
                }
            }
        }
        return stmt
    }

    private func value(_ stmt: OpaquePointer, _ col: Int32) -> SQLValue {
        switch sqlite3_column_type(stmt, col) {
        case SQLITE_INTEGER: return .int(sqlite3_column_int64(stmt, col))
        case SQLITE_FLOAT: return .double(sqlite3_column_double(stmt, col))
        case SQLITE_TEXT:
            guard let p = sqlite3_column_text(stmt, col) else { return .text("") }
            let n = Int(sqlite3_column_bytes(stmt, col))
            return .text(String(decoding: UnsafeRawBufferPointer(start: p, count: n), as: UTF8.self))
        case SQLITE_BLOB:
            let n = Int(sqlite3_column_bytes(stmt, col))
            guard n > 0, let p = sqlite3_column_blob(stmt, col) else { return .blob(Data()) }
            return .blob(Data(bytes: p, count: n))
        default: return .null
        }
    }

    /// Runs a statement and calls `body` for each row. Return false from `body` to stop early.
    public func forEach(_ sql: String, _ args: [SQLBindable] = [], _ body: (SQLRow) throws -> Bool) throws {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        let count = sqlite3_column_count(stmt)
        let columns = (0..<count).map { String(cString: sqlite3_column_name(stmt, $0)) }
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw lastError(rc) }
            let row = SQLRow(values: (0..<count).map { value(stmt, $0) }, columns: columns)
            if try !body(row) { break }
        }
    }

    public func query(_ sql: String, _ args: [SQLBindable] = []) throws -> [SQLRow] {
        var rows: [SQLRow] = []
        try forEach(sql, args) { rows.append($0); return true }
        return rows
    }

    public func scalar(_ sql: String, _ args: [SQLBindable] = []) throws -> SQLValue {
        var result: SQLValue = .null
        try forEach(sql, args) { row in result = row[0]; return false }
        return result
    }

    @discardableResult
    public func run(_ sql: String, _ args: [SQLBindable] = []) throws -> Int {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw lastError(rc) }
        return Int(sqlite3_changes(handle))
    }

    public func tableExists(_ name: String) -> Bool {
        ((try? scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name=?", [name]).int) ?? 0) > 0
    }

    public func columns(of table: String) -> [String] {
        (try? query("PRAGMA table_info(\(table))").map { $0["name"].string }) ?? []
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let r = try body()
            try execute("COMMIT")
            return r
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}
