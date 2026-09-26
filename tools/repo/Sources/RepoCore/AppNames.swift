import Foundation

/// Every name derived from an app slug, and the template placeholders they replace.
public struct AppNames: Equatable, Sendable {
    public let slug: String
    public let name: String
    public let displayName: String
    public let bundleIdentifier: String
    public let dataEnvironmentKey: String

    public init(slug: String, displayName: String? = nil, bundlePrefix: String) throws {
        try Self.validateSlug(slug)
        self.slug = slug
        self.name = Self.pascalCase(slug)
        self.displayName = try displayName.map(Self.validateDisplayName) ?? Self.defaultDisplayName(slug)
        self.bundleIdentifier = "\(bundlePrefix).\(slug)"
        self.dataEnvironmentKey = Self.dataEnvironmentKey(slug)
    }

    /// Placeholder tokens and their values, in the order they are replaced.
    public var placeholders: [(token: String, value: String)] {
        [
            ("__DISPLAY_NAME__", displayName),
            ("__BUNDLE_ID__", bundleIdentifier),
            ("__DATA_ENV__", dataEnvironmentKey),
            ("__NAME__", name),
            ("__name__", slug),
        ]
    }

    /// `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`
    public static func isValidSlug(_ slug: String) -> Bool {
        guard let first = slug.first, isLowercaseLetter(first) else {
            return false
        }
        return slug.split(separator: "-", omittingEmptySubsequences: false).allSatisfy { part in
            !part.isEmpty && part.allSatisfy { isLowercaseLetter($0) || isDigit($0) }
        }
    }

    public static func validateSlug(_ slug: String) throws {
        guard isValidSlug(slug) else {
            throw RepoError.usage(
                "slug 형식이 틀렸습니다: '\(slug)'. 소문자로 시작하고 소문자·숫자·하이픈만 씁니다(예: memo-board)."
            )
        }
    }

    /// `memo-board` → `MemoBoard`
    public static func pascalCase(_ slug: String) -> String {
        words(slug).joined()
    }

    /// `memo-board` → `Memo Board`
    public static func defaultDisplayName(_ slug: String) -> String {
        words(slug).joined(separator: " ")
    }

    /// `memo-board` → `MEMO_BOARD_DATA_DIR`
    public static func dataEnvironmentKey(_ slug: String) -> String {
        slug.uppercased().replacingOccurrences(of: "-", with: "_") + "_DATA_DIR"
    }

    /// Display names end up in Info.plist, Swift string literals, and the `.app` file name,
    /// so characters that need escaping in any of those are rejected.
    public static func validateDisplayName(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let forbidden = CharacterSet(charactersIn: "\"\\/:<>&").union(.controlCharacters)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: forbidden) == nil else {
            throw RepoError.usage("표시 이름이 비었거나 쓸 수 없는 문자(\" \\ / : < > & 제어 문자)가 있습니다: '\(value)'")
        }
        return trimmed
    }

    private static func words(_ slug: String) -> [String] {
        slug.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    private static func isLowercaseLetter(_ character: Character) -> Bool {
        character.isASCII && character.isLetter && character.isLowercase
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }
}
