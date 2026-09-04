import Foundation
import ZenithData

/// Port of `lib/ai/claude.ts`. There's no Swift SDK for
/// `@anthropic-ai/claude-agent-sdk` to lean on, so this talks to the
/// `claude` CLI's stream-json protocol directly via `Process`/`Pipe` — the
/// exact protocol (input: newline-delimited `SDKUserMessage`-shaped JSON on
/// stdin; output: newline-delimited messages on stdout, terminated by a
/// `type: "result"` message) was verified live against the installed CLI
/// during subtask 3 planning, not assumed from the SDK's minified bundle.
public actor ClaudeCLIClient {
    public static let shared = ClaudeCLIClient()

    /// The Messages API only accepts these four image media types.
    private static let imageMediaTypes: Set<String> = ["image/jpeg", "image/png", "image/gif", "image/webp"]

    public enum ContentBlock: Sendable {
        case text(String)
        case image(mediaType: String, base64Data: String)

        fileprivate var jsonValue: [String: Any] {
            switch self {
            case .text(let text):
                return ["type": "text", "text": text]
            case .image(let mediaType, let data):
                return ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": data]]
            }
        }
    }

    /// Builds an image content block, validating the mime type against
    /// what the Messages API actually accepts (pasted-in images can carry
    /// an arbitrary mime type off a data URL).
    public static func imageBlock(mimeType: String, data: String) throws -> ContentBlock {
        guard imageMediaTypes.contains(mimeType) else {
            throw ClaudeCliError(
                "Unsupported image type \"\(mimeType)\" — expected one of \(imageMediaTypes.sorted().joined(separator: ", "))."
            )
        }
        return .image(mediaType: mimeType, base64Data: data)
    }

    private var cachedPath: String?

    private static let fallbackPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    /// On-disk record of a previously resolved PATH, keyed by the `$SHELL`
    /// it was resolved for.
    private struct PathCache: Codable {
        var shell: String
        var path: String
    }

    private static var pathCacheURL: URL? {
        (try? AppConfig.configDirectory())?.appendingPathComponent("resolved-path.json")
    }

    /// A stable, app-owned working directory for the `claude` subprocess.
    /// The CLI does project/config discovery relative to its CWD at
    /// startup; pointing it here (inside Application Support, which is not
    /// a TCC-protected location) keeps it out of the user's real project
    /// tree and out of Documents/Desktop/Downloads, so it never triggers a
    /// folder-access prompt. Falls back to the temp dir if Application
    /// Support can't be created.
    private static func workingDirectory() -> URL {
        guard let base = try? AppConfig.configDirectory() else {
            return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        }
        let dir = base.appendingPathComponent("claude-cwd", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// True if a directory on `path` holds an executable named `claude` —
    /// used to reject a stale disk cache (e.g. the CLI was reinstalled
    /// elsewhere) without paying for another shell probe.
    private static func claudeIsResolvable(on path: String) -> Bool {
        path.split(separator: ":").contains { dir in
            FileManager.default.isExecutableFile(
                atPath: URL(fileURLWithPath: String(dir)).appendingPathComponent("claude").path)
        }
    }

    /// Discards the persisted PATH — called when a spawn fails with
    /// "claude not found" so the next attempt re-probes instead of being
    /// stuck on a cache that points at a since-moved install.
    private func invalidatePathCache() {
        cachedPath = nil
        if let url = Self.pathCacheURL { try? FileManager.default.removeItem(at: url) }
    }

    /// GUI-launched macOS apps often get a minimal PATH
    /// (`/usr/bin:/bin:/usr/sbin:/sbin`) that doesn't include wherever the
    /// `claude` CLI is actually installed (nvm/homebrew/etc, only set up in
    /// shell rc files). Fixed by asking the user's login shell what PATH it
    /// resolves to and adopting that — same technique as Electron's
    /// `fixPath()` (`electron/main.js`), for the same OS-level reason.
    ///
    /// The probe spawns a subprocess that sources the user's shell startup
    /// files. On an ad-hoc-signed build macOS re-prompts for any
    /// protected-folder access those files make and never remembers the
    /// grant, so this is done **at most once ever**: the result is written
    /// to `resolved-path.json` and reused on every later launch without
    /// spawning anything.
    ///
    /// A `-lc` (login, non-interactive) probe is tried first — it sources
    /// only `.zshenv`/`.zprofile`/`.zlogin`, where PATH belongs, skipping
    /// the interactive `.zshrc` plugin set that's the usual source of
    /// stray protected-folder access. Only if `claude` isn't on that PATH
    /// does it fall back to `-ilc` (some setups only extend PATH from
    /// `.zshrc`).
    private func resolvedPath() async -> String {
        if let cachedPath { return cachedPath }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        if let url = Self.pathCacheURL,
            let data = try? Data(contentsOf: url),
            let cache = try? JSONDecoder().decode(PathCache.self, from: data),
            cache.shell == shell, !cache.path.isEmpty,
            Self.claudeIsResolvable(on: cache.path)
        {
            cachedPath = cache.path
            return cache.path
        }

        let ownPath = ProcessInfo.processInfo.environment["PATH"]
        var finalPath = Self.fallbackPath
        for interactive in [false, true] {
            guard let probed = await Self.probeShellPath(shell: shell, interactive: interactive),
                !probed.isEmpty
            else { continue }
            finalPath = probed
            if Self.claudeIsResolvable(on: probed) { break }
        }
        if !Self.claudeIsResolvable(on: finalPath), let ownPath, !ownPath.isEmpty {
            finalPath = ownPath
        }

        cachedPath = finalPath
        if let url = Self.pathCacheURL,
            let encoded = try? JSONEncoder().encode(PathCache(shell: shell, path: finalPath))
        {
            try? encoded.write(to: url, options: .atomic)
        }
        return finalPath
    }

    private static func probeShellPath(shell: String, interactive: Bool) async -> String? {
        let marker = "___PATH_MARKER___"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = [interactive ? "-ilc" : "-lc", "echo -n \(marker); echo -n \"$PATH\""]
        // A non-protected CWD so the startup files can't wander into a
        // protected folder via a relative path / `$PWD`.
        process.currentDirectoryURL = workingDirectory()
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()  // discard — a broken rc file's warnings shouldn't leak into our output

        let resolved: String? = await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if let range = output.range(of: marker, options: .backwards) {
                    continuation.resume(returning: String(output[range.upperBound...]))
                } else {
                    continuation.resume(returning: nil)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }

        return resolved?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// These are pure text-in/JSON-or-text-out calls — no filesystem or
    /// network access wanted or needed — so `--tools ""` disables Claude
    /// Code's entire built-in toolset. That's the actual safety boundary;
    /// `--permission-mode bypassPermissions` + `--allow-dangerously-skip-
    /// permissions` just stop the subprocess from blocking on an
    /// interactive prompt that (with no tools available) should never fire
    /// anyway.
    private func baseArguments() -> [String] {
        // `--verbose` is required by the CLI whenever `--output-format
        // stream-json` is combined with `--print` — not a debug-logging
        // opt-in in this mode, just a mandatory pairing (verified directly
        // against the installed CLI, not assumed).
        ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
         "--tools", "", "--permission-mode", "bypassPermissions", "--allow-dangerously-skip-permissions"]
    }

    private struct QueryResult {
        let result: String
        let structuredOutput: Any?
    }

    private func runQuery(blocks: [ContentBlock], jsonSchema: [String: Any]?, timeout: TimeInterval) async throws -> QueryResult {
        var arguments = baseArguments()
        if let jsonSchema {
            let schemaData = try JSONSerialization.data(withJSONObject: jsonSchema)
            arguments += ["--json-schema", String(data: schemaData, encoding: .utf8) ?? "{}"]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude"] + arguments
        // Keep the CLI's project/config discovery inside an app-owned
        // directory (not a TCC-protected one, and not the user's project
        // tree) so it never provokes a folder-access prompt.
        process.currentDirectoryURL = Self.workingDirectory()
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = await resolvedPath()
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            invalidatePathCache()
            throw ClaudeCliError(
                "Claude Code CLI not found. Install it and run `claude login` (requires a Claude Pro/Max subscription)."
            )
        }

        let message: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": blocks.map(\.jsonValue)],
            "parent_tool_use_id": NSNull(),
        ]
        let messageData = try JSONSerialization.data(withJSONObject: message)
        stdin.fileHandleForWriting.write(messageData)
        stdin.fileHandleForWriting.write("\n".data(using: .utf8)!)
        try? stdin.fileHandleForWriting.close()

        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if process.isRunning { process.terminate() }
        }

        // Drain both pipes concurrently — reading them sequentially risks a
        // deadlock if the child writes enough to the pipe we're *not*
        // currently draining that its buffer fills and the child blocks.
        async let stdoutData = Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }.value
        async let stderrData = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }.value
        let (outputData, errorData) = await (stdoutData, stderrData)
        process.waitUntilExit()
        timeoutTask.cancel()

        if process.terminationStatus == 15 || process.terminationStatus == -15 {
            throw ClaudeCliError("Claude Code timed out after \(Int(timeout * 1000))ms.")
        }

        let stderrText = String(data: errorData, encoding: .utf8) ?? ""
        if process.terminationStatus == 127 || stderrText.lowercased().contains("command not found") || stderrText.contains("No such file or directory") {
            invalidatePathCache()
            throw ClaudeCliError(
                "Claude Code CLI not found. Install it and run `claude login` (requires a Claude Pro/Max subscription)."
            )
        }

        return try Self.parseStreamOutput(outputData)
    }

    private static func parseStreamOutput(_ data: Data) throws -> QueryResult {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ClaudeCliError("Claude Code produced no readable output.")
        }
        for line in text.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let type = object["type"] as? String
            else { continue }

            if type == "assistant", let errorCode = object["error"] as? String {
                throw ClaudeCliError(describeAssistantError(errorCode))
            }

            if type == "result" {
                let subtype = object["subtype"] as? String
                guard subtype == "success" else {
                    let errors = (object["errors"] as? [String])?.joined(separator: " ") ?? ""
                    throw ClaudeCliError("Claude Code didn't complete (\(subtype ?? "unknown")).\(errors.isEmpty ? "" : " \(errors)")")
                }
                let result = object["result"] as? String ?? ""
                return QueryResult(result: result, structuredOutput: object["structured_output"])
            }
        }
        throw ClaudeCliError("Claude Code exited without returning a result.")
    }

    private static func describeAssistantError(_ error: String) -> String {
        if error == "authentication_failed" {
            return "Claude Code isn't authenticated. Run `claude login` in a terminal on this machine (requires a Claude Pro/Max subscription)."
        }
        return "Claude Code returned an error: \(error)."
    }

    private static func stripCodeFences(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var body = trimmed
        if body.hasPrefix("```json") { body.removeFirst(7) } else { body.removeFirst(3) }
        if body.hasSuffix("```") { body.removeLast(3) }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Plain-prose calls (e.g. repo summarization) — no schema, just text.
    public func runText(_ prompt: String, timeout: TimeInterval) async throws -> String {
        let result = try await runQuery(blocks: [.text(prompt)], jsonSchema: nil, timeout: timeout)
        let trimmed = result.result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClaudeCliError("Claude returned an empty response.") }
        return trimmed
    }

    /// JSON-shaped calls. `jsonSchema` constrains the model toward the
    /// right shape (not a 100% guarantee — the caller's `decode` closure
    /// should still validate). Falls back to parsing `result` as JSON if
    /// `structured_output` isn't present (e.g. an older CLI). The Messages
    /// API requires a schema's root to be `type: "object"`, so
    /// array-shaped results are wrapped under `unwrapKey` and unwrapped
    /// here after decoding.
    public func runJSON<T>(
        blocks: [ContentBlock], jsonSchema: [String: Any], unwrapKey: String? = nil, timeout: TimeInterval,
        decode: (Any) throws -> T
    ) async throws -> T {
        let result = try await runQuery(blocks: blocks, jsonSchema: jsonSchema, timeout: timeout)

        var raw: Any? = result.structuredOutput
        if raw == nil {
            let stripped = Self.stripCodeFences(result.result)
            guard let data = stripped.data(using: .utf8),
                let parsed = try? JSONSerialization.jsonObject(with: data)
            else {
                throw ClaudeCliError("Claude's response wasn't valid JSON.")
            }
            raw = parsed
        }

        if let unwrapKey, let dict = raw as? [String: Any] {
            raw = dict[unwrapKey]
        }

        guard let raw else { throw ClaudeCliError("Claude's response didn't match the expected format.") }
        do {
            return try decode(raw)
        } catch {
            throw ClaudeCliError("Claude's response didn't match the expected format.")
        }
    }

    public func runJSON<T>(
        prompt: String, jsonSchema: [String: Any], unwrapKey: String? = nil, timeout: TimeInterval, decode: (Any) throws -> T
    ) async throws -> T {
        try await runJSON(blocks: [.text(prompt)], jsonSchema: jsonSchema, unwrapKey: unwrapKey, timeout: timeout, decode: decode)
    }
}

public struct ClaudeCliError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}
