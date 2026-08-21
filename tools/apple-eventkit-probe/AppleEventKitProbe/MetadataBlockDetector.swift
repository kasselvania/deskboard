import Foundation

enum MetadataBlockDetector {
    static let openingDelimiter = "[deskboard:v1]"
    static let closingDelimiter = "[/deskboard]"

    static func inspect(_ notes: String?) -> MetadataBlockObservation? {
        guard let notes else { return nil }

        let openingRanges = ranges(of: openingDelimiter, in: notes)
        let closingRanges = ranges(of: closingDelimiter, in: notes)
        let unsupportedVersion = notes.contains("[deskboard:") && openingRanges.isEmpty
        let paired = openingRanges.count == 1
            && closingRanges.count == 1
            && openingRanges[0].upperBound <= closingRanges[0].lowerBound

        let proseBefore: Bool
        let proseAfter: Bool
        if paired {
            proseBefore = !notes[..<openingRanges[0].lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            proseAfter = !notes[closingRanges[0].upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            proseBefore = false
            proseAfter = false
        }

        return MetadataBlockObservation(
            openingDelimiterPresent: !openingRanges.isEmpty,
            closingDelimiterPresent: !closingRanges.isEmpty,
            pairedBlockPresent: paired,
            malformed: (!openingRanges.isEmpty || !closingRanges.isEmpty) && !paired,
            proseBeforePresent: proseBefore,
            proseAfterPresent: proseAfter,
            multipleOpeningDelimiters: openingRanges.count > 1,
            multipleClosingDelimiters: closingRanges.count > 1,
            unsupportedVersionDelimiterPresent: unsupportedVersion
        )
    }

    private static func ranges(of needle: String, in haystack: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var searchRange = haystack.startIndex ..< haystack.endIndex
        while let match = haystack.range(of: needle, range: searchRange) {
            result.append(match)
            searchRange = match.upperBound ..< haystack.endIndex
        }
        return result
    }
}
