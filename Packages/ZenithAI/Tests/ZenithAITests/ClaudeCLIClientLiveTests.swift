import Foundation
import Testing

@testable import ZenithAI

/// Exercises the real `claude` CLI — costs real API usage and requires the
/// user to already be `claude login`'d, so these are gated behind an env
/// var and skipped in normal `swift test` runs (including CI, if this
/// project ever gets one). Run explicitly with:
///   ZENITH_LIVE_AI_TESTS=1 swift test --filter ClaudeCLIClientLiveTests
@Suite("ClaudeCLIClient (live)", .enabled(if: ProcessInfo.processInfo.environment["ZENITH_LIVE_AI_TESTS"] == "1"))
struct ClaudeCLIClientLiveTests {
    @Test("runText returns a real response")
    func runText() async throws {
        let result = try await ClaudeCLIClient.shared.runText("Reply with exactly the word: pong", timeout: 60)
        #expect(result.lowercased().contains("pong"))
    }

    @Test("runJSON returns structured output matching the schema")
    func runJSON() async throws {
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["name": ["type": "string"], "age": ["type": "number"]],
            "required": ["name", "age"],
        ]
        struct Person { let name: String; let age: Int }
        let person: Person = try await ClaudeCLIClient.shared.runJSON(
            prompt: "Extract: My name is Bob and I am 30 years old.", jsonSchema: schema, timeout: 60
        ) { raw in
            guard let dict = raw as? [String: Any], let name = dict["name"] as? String, let age = dict["age"] as? Int else {
                throw AISchemaError.invalid("missing name/age")
            }
            return Person(name: name, age: age)
        }
        #expect(person.name == "Bob")
        #expect(person.age == 30)
    }

    @Test("a real Prompts.parseTaskFromText call round-trips end to end")
    func parseTaskFromTextLive() async throws {
        let task = try await Prompts.parseTaskFromText(text: "URGENT: fix the checkout 500 error on the payments repo by Friday", spaceContext: nil)
        #expect(!task.title.isEmpty)
        #expect(task.priority.rawValue == "high")
    }
}
