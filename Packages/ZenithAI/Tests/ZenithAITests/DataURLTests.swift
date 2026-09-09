import Testing

@testable import ZenithAI

@Suite("DataURL")
struct DataURLTests {
    @Test("parses a well-formed data URL")
    func wellFormed() {
        let parsed = DataURL.parse("data:image/png;base64,aGVsbG8=")
        #expect(parsed?.mimeType == "image/png")
        #expect(parsed?.data == "aGVsbG8=")
    }

    @Test("rejects a string without the data: prefix")
    func missingPrefix() {
        #expect(DataURL.parse("image/png;base64,aGVsbG8=") == nil)
    }

    @Test("rejects a non-base64 data URL")
    func nonBase64() {
        #expect(DataURL.parse("data:text/plain,hello") == nil)
    }

    @Test("rejects a data URL with empty payload")
    func emptyPayload() {
        #expect(DataURL.parse("data:image/png;base64,") == nil)
    }
}
