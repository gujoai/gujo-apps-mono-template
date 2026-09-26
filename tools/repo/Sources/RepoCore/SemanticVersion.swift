import Foundation

/// A `major.minor.patch` version: app VERSION files, template editions, and the Swift compiler.
public struct SemanticVersion: Comparable, CustomStringConvertible, Hashable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Exactly `x.y.z` with decimal numbers; anything else is nil.
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
            let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2])
        else {
            return nil
        }
        self.init(major: major, minor: minor, patch: patch)
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    /// Reads the compiler version from `swift --version` output, e.g.
    /// `swift-driver version: 1.120.5 Apple Swift version 6.1 (swiftlang-6.1.0.110.21 clang-1700.0.13.3)`.
    public static func parseSwiftVersion(_ output: String) -> SemanticVersion? {
        guard let marker = output.range(of: "Swift version ") else {
            return nil
        }
        let token = output[marker.upperBound...].prefix { ($0.isASCII && $0.isNumber) || $0 == "." }
        let numbers = token.split(separator: ".").compactMap { Int($0) }
        guard let major = numbers.first else {
            return nil
        }
        return SemanticVersion(
            major: major,
            minor: numbers.count > 1 ? numbers[1] : 0,
            patch: numbers.count > 2 ? numbers[2] : 0
        )
    }
}
