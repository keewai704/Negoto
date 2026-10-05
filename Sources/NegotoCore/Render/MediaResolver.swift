import Foundation

/// Maps media references found in card HTML to files that actually exist in the media folder,
/// tolerating percent-encoding, entity-encoding, Unicode normalisation (NFC/NFD) and case.
public final class MediaResolver: @unchecked Sendable {
    public let folder: URL
    private var exact: Set<String> = []
    private var normalized: [String: String] = [:]
    private var lowercased: [String: String] = [:]
    private let lock = NSLock()

    public init(folder: URL) {
        self.folder = folder
        reload()
    }

    public func reload() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        lock.lock(); defer { lock.unlock() }
        exact = Set(names)
        normalized = [:]
        lowercased = [:]
        for n in names {
            normalized[n.precomposedStringWithCanonicalMapping] = n
            lowercased[n.precomposedStringWithCanonicalMapping.lowercased()] = n
        }
    }

    public var count: Int { lock.lock(); defer { lock.unlock() }; return exact.count }

    public func exists(_ name: String) -> Bool { resolve(name) != nil }

    /// Returns the on-disk filename for a reference, or nil if no such file exists.
    public func resolve(_ reference: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        var candidates = [reference]
        let decoded = HTMLText.decodeEntities(reference)
        candidates.append(decoded)
        if let p = decoded.removingPercentEncoding { candidates.append(p) }
        for c in candidates {
            if exact.contains(c) { return c }
            let nfc = c.precomposedStringWithCanonicalMapping
            if let n = normalized[nfc] { return n }
            if let n = lowercased[nfc.lowercased()] { return n }
        }
        return nil
    }

    public func url(for name: String) -> URL { folder.appendingPathComponent(name) }

    static let allowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "#?%;/:")
        return set
    }()

    public static func encode(_ filename: String) -> String {
        filename.addingPercentEncoding(withAllowedCharacters: allowed) ?? filename
    }

    private static let attrRegex = try! NSRegularExpression(
        pattern: "(\\b(?:src|poster|data|href)\\s*=\\s*)(\"([^\"]*)\"|'([^']*)'|([^\\s>\"']+))",
        options: [.caseInsensitive])
    private static let cssURLRegex = try! NSRegularExpression(
        pattern: "url\\(\\s*(?:\"([^\"]*)\"|'([^']*)'|([^)\\s]*))\\s*\\)", options: [.caseInsensitive])
    private static let schemeRegex = try! NSRegularExpression(pattern: "^[a-zA-Z][a-zA-Z0-9+.-]*:")

    private func rewrite(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") || trimmed.hasPrefix("/") { return nil }
        if Self.schemeRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil { return nil }
        guard let name = resolve(trimmed) else { return nil }
        return Self.encode(name)
    }

    /// Rewrites `src=`, `poster=`, `data=`, `href=` and CSS `url()` references to existing media files
    /// into properly percent-encoded relative URLs.
    public func rewriteReferences(in html: String) -> String {
        var out = HTMLText.replace(Self.attrRegex, in: html) { g in
            let prefix = g[1] ?? ""
            let value = g[3] ?? g[4] ?? g[5] ?? ""
            guard let encoded = rewrite(value) else { return g[0] ?? "" }
            return "\(prefix)\"\(encoded)\""
        }
        if out.range(of: "url(", options: .caseInsensitive) != nil {
            out = rewriteCSS(out)
        }
        return out
    }

    public func rewriteCSS(_ css: String) -> String {
        HTMLText.replace(Self.cssURLRegex, in: css) { g in
            let value = g[1] ?? g[2] ?? g[3] ?? ""
            guard let encoded = rewrite(value) else { return g[0] ?? "" }
            return "url(\"\(encoded)\")"
        }
    }
}
