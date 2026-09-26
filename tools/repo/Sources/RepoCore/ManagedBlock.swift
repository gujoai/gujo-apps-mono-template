import Foundation

/// The part of a file that belongs to the template: the lines between the begin and end markers.
/// Everything outside the markers belongs to the repository's owner.
public enum ManagedBlock {
    public static let beginMarker = "<!-- template:begin -->"
    public static let endMarker = "<!-- template:end -->"

    /// The text after the begin marker line and before the end marker line.
    /// Each marker must appear exactly once, on a line of its own, begin before end.
    public static func innerRange(of text: String, file: String) throws -> Range<String.Index> {
        var begins: [String.Index] = []
        var ends: [String.Index] = []
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            switch line.trimmingCharacters(in: .whitespaces) {
            case beginMarker:
                begins.append(line.endIndex == text.endIndex ? text.endIndex : text.index(after: line.endIndex))
            case endMarker:
                ends.append(line.startIndex)
            default:
                break
            }
        }
        guard begins.count == 1, ends.count == 1, let start = begins.first, let end = ends.first, start <= end
        else {
            throw RepoError.failure(
                "\(file): 템플릿 구역 표시가 없거나 짝이 맞지 않습니다. \(beginMarker) 와 \(endMarker) 가 한 줄씩, 이 순서로 있어야 합니다."
            )
        }
        return start..<end
    }

    /// Whether any line of `text` is a begin or end marker. `innerRange` checks that they pair up.
    public static func hasMarkers(_ text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed == beginMarker || trimmed == endMarker
        }
    }

    /// `current` with its template block replaced by the template block of `template`.
    /// Text outside the markers in `current` is kept exactly as it is.
    public static func replacingBlock(in current: String, with template: String, file: String) throws -> String {
        let currentRange = try innerRange(of: current, file: file)
        let templateRange = try innerRange(of: template, file: file)
        var result = current
        result.replaceSubrange(currentRange, with: template[templateRange])
        return result
    }
}
