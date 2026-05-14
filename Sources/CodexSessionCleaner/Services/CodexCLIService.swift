import Foundation

struct CodexCLIError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

struct CodexCLIService {
    var scriptPath: URL = CodexCLIService.resolveScriptPath()

    func listSessions(codexHome: String, limit: Int = 500) async throws -> [SessionItem] {
        let data = try await run(
            arguments: [
                scriptPath.path,
                "--codex-home", codexHome,
                "list",
                "--limit", String(limit),
                "--json"
            ]
        )
        return try JSONDecoder().decode([SessionItem].self, from: data)
    }

    func previewDelete(codexHome: String, threadId: String) async throws -> DeletePlan {
        let data = try await run(
            arguments: [
                scriptPath.path,
                "--codex-home", codexHome,
                "delete",
                "--id", threadId,
                "--dry-run",
                "--json"
            ]
        )
        return try JSONDecoder().decode(DeletePlan.self, from: data)
    }

    func deleteSession(codexHome: String, threadId: String) async throws -> DeletePlan {
        let data = try await run(
            arguments: [
                scriptPath.path,
                "--codex-home", codexHome,
                "delete",
                "--id", threadId,
                "--yes",
                "--json"
            ]
        )
        return try JSONDecoder().decode(DeletePlan.self, from: data)
    }

    private func run(arguments: [String]) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let tempDirectory = FileManager.default.temporaryDirectory
            let runID = UUID().uuidString
            let stdoutURL = tempDirectory.appendingPathComponent("codex-session-cleaner-\(runID).out")
            let stderrURL = tempDirectory.appendingPathComponent("codex-session-cleaner-\(runID).err")
            FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
            defer {
                try? FileManager.default.removeItem(at: stdoutURL)
                try? FileManager.default.removeItem(at: stderrURL)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3"] + arguments

            let stdout = try FileHandle(forWritingTo: stdoutURL)
            let stderr = try FileHandle(forWritingTo: stderrURL)
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            process.waitUntilExit()
            try? stdout.close()
            try? stderr.close()

            let output = try Data(contentsOf: stdoutURL)
            let errorOutput = try Data(contentsOf: stderrURL)
            if process.terminationStatus != 0 {
                let message = String(data: errorOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw CodexCLIError(message: message?.isEmpty == false ? message! : "codex_session_delete.py failed")
            }
            return output
        }.value
    }

    static func resolveScriptPath() -> URL {
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("codex_session_delete.py"),
           FileManager.default.fileExists(atPath: resourceURL.path) {
            return resourceURL
        }

        let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("codex_session_delete.py")
        if FileManager.default.fileExists(atPath: cwdURL.path) {
            return cwdURL
        }

        return URL(fileURLWithPath: "codex_session_delete.py")
    }
}
