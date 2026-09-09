import Foundation

/// Port of `lib/data-url.ts`. Splits a `data:<mime>;base64,<data>` URL into
/// its parts.
public enum DataURL {
    public static func parse(_ dataUrl: String) -> (mimeType: String, data: String)? {
        guard let commaIndex = dataUrl.firstIndex(of: ","),
            dataUrl.hasPrefix("data:")
        else { return nil }

        let header = dataUrl[dataUrl.index(dataUrl.startIndex, offsetBy: 5)..<commaIndex]
        guard header.hasSuffix(";base64") else { return nil }
        let mimeType = String(header.dropLast(";base64".count))
        guard !mimeType.isEmpty else { return nil }

        let data = String(dataUrl[dataUrl.index(after: commaIndex)...])
        guard !data.isEmpty else { return nil }

        return (mimeType, data)
    }
}
