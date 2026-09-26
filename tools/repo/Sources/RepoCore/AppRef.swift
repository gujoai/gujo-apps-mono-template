import Foundation

/// An app the repo commands can build: the owner's `apps/<slug>`, or a brick `bricks/<tenant>/apps/<slug>`.
public struct AppRef: Hashable, Comparable, CustomStringConvertible, Sendable {
    /// nil for the owner's app.
    public let tenant: String?
    public let slug: String

    public init(tenant: String? = nil, slug: String) {
        self.tenant = tenant
        self.slug = slug
    }

    /// `<slug>` names an owner's app and `<tenant>/<slug>` a brick app.
    public static func parse(_ text: String) throws -> AppRef {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        switch parts.count {
        case 1:
            try AppNames.validateSlug(parts[0])
            return AppRef(slug: parts[0])
        case 2:
            try Tenants.validateName(parts[0])
            try AppNames.validateSlug(parts[1])
            return AppRef(tenant: parts[0], slug: parts[1])
        default:
            throw RepoError.usage("앱은 <slug> 나 <테넌트>/<slug> 로 적습니다: '\(text)'")
        }
    }

    public var description: String {
        tenant.map { "\($0)/\(slug)" } ?? slug
    }

    /// Path relative to the repository root.
    public var path: String {
        tenant.map { "\(Tenants.directory)/\($0)/apps/\(slug)" } ?? "apps/\(slug)"
    }

    /// `owner` for the owner's app, otherwise the tenant name.
    public var origin: String {
        tenant ?? AppRef.ownerOrigin
    }

    public static let ownerOrigin = "owner"

    /// Owner's apps first, then bricks by tenant and slug.
    public static func < (lhs: AppRef, rhs: AppRef) -> Bool {
        (lhs.tenant ?? "", lhs.slug) < (rhs.tenant ?? "", rhs.slug)
    }
}
