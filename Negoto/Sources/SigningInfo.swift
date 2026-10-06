import Foundation

/// How this copy of the app was signed, read from the embedded provisioning profile.
struct SigningInfo: Equatable {
    enum Kind: Equatable {
        /// No embedded profile: App Store or TestFlight.
        case appStore
        case development
        case adHoc
        case enterprise
        /// No profile and no signature information (simulator / unsigned build).
        case unknown
    }

    var kind: Kind
    var teamName: String?
    var teamID: String?
    var profileName: String?
    var creationDate: Date?
    var expirationDate: Date?
    /// iCloud containers granted by the profile (empty when signed with a free Apple ID).
    var iCloudContainers: [String]
    var hasICloudDocuments: Bool

    /// Free Apple ID ("Personal Team") profiles can't include iCloud and expire after 7 days.
    var looksLikeFreeAccount: Bool {
        guard kind == .development, let created = creationDate, let exp = expirationDate else { return false }
        return exp.timeIntervalSince(created) <= 8 * 86_400
    }

    var title: String {
        switch kind {
        case .appStore: return "App Store / TestFlight"
        case .development: return looksLikeFreeAccount ? "個人用（無料Apple ID・サイドロード）" : "開発用（Development）"
        case .adHoc: return "Ad Hoc"
        case .enterprise: return "Enterprise"
        case .unknown: return "不明（未署名またはシミュレータ）"
        }
    }

    static let current: SigningInfo = load()

    static func load(bundle: Bundle = .main) -> SigningInfo {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else {
            #if targetEnvironment(simulator)
            return SigningInfo(kind: .unknown, iCloudContainers: [], hasICloudDocuments: false)
            #else
            // Store / TestFlight builds don't carry a profile.
            let receipt = bundle.appStoreReceiptURL?.lastPathComponent
            let kind: Kind = receipt == nil ? .unknown : .appStore
            return SigningInfo(kind: kind, iCloudContainers: [], hasICloudDocuments: kind == .appStore)
            #endif
        }
        return parse(profile: data)
    }

    /// The profile is a CMS-signed plist; the XML is stored verbatim inside it.
    static func parse(profile data: Data) -> SigningInfo {
        let empty = SigningInfo(kind: .unknown, iCloudContainers: [], hasICloudDocuments: false)
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return empty }
        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any] else { return empty }
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        let kind: Kind
        if plist["ProvisionsAllDevices"] as? Bool == true {
            kind = .enterprise
        } else if plist["ProvisionedDevices"] != nil {
            kind = entitlements["get-task-allow"] as? Bool == true ? .development : .adHoc
        } else {
            kind = .appStore
        }
        let containers = (entitlements["com.apple.developer.icloud-container-identifiers"] as? [String]) ?? []
        let services = (entitlements["com.apple.developer.icloud-services"] as? [String])
            ?? ((entitlements["com.apple.developer.icloud-services"] as? String).map { [$0] } ?? [])
        return SigningInfo(
            kind: kind,
            teamName: plist["TeamName"] as? String,
            teamID: (plist["TeamIdentifier"] as? [String])?.first,
            profileName: plist["Name"] as? String,
            creationDate: plist["CreationDate"] as? Date,
            expirationDate: plist["ExpirationDate"] as? Date,
            iCloudContainers: containers,
            hasICloudDocuments: !containers.isEmpty && (services.isEmpty || services.contains { $0 == "CloudDocuments" || $0 == "*" }))
    }
}
