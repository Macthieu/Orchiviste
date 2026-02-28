import Foundation

struct ShellCommandResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum ShellCommand {
    @discardableResult
    static func run(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil
    ) -> ShellCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return ShellCommandResult(
                stdout: "",
                stderr: "command_failed: \(error.localizedDescription)",
                exitCode: 127
            )
        }

        process.waitUntilExit()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        return ShellCommandResult(
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }
}
