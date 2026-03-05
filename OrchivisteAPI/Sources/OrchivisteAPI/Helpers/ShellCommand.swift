import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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
        currentDirectory: URL? = nil,
        timeoutSeconds: TimeInterval? = nil,
        captureOutput: Bool = true
    ) -> ShellCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        if captureOutput {
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }

        do {
            try process.run()
        } catch {
            if captureOutput {
                stdoutPipe.fileHandleForWriting.closeFile()
                stderrPipe.fileHandleForWriting.closeFile()
            }
            return ShellCommandResult(
                stdout: "",
                stderr: "command_failed: \(error.localizedDescription)",
                exitCode: 127
            )
        }
        if captureOutput {
            stdoutPipe.fileHandleForWriting.closeFile()
            stderrPipe.fileHandleForWriting.closeFile()
        }

        var outData = Data()
        var errData = Data()
        let readGroup = DispatchGroup()
        if captureOutput {
            readGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                readGroup.leave()
            }
            readGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                readGroup.leave()
            }
        }

        let didTimeout = waitForProcess(process, timeoutSeconds: timeoutSeconds)
        if captureOutput {
            readGroup.wait()
        }
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        if didTimeout {
            let timeoutDetail: String
            if let timeoutSeconds {
                timeoutDetail = String(format: "timeout_exceeded_after_%.1fs", timeoutSeconds)
            } else {
                timeoutDetail = "timeout_exceeded"
            }
            let mergedErr = err.isEmpty ? timeoutDetail : "\(err)\n\(timeoutDetail)"
            return ShellCommandResult(
                stdout: out,
                stderr: mergedErr,
                exitCode: 124
            )
        }
        return ShellCommandResult(
            stdout: out,
            stderr: err,
            exitCode: process.terminationStatus
        )
    }

    private static func waitForProcess(_ process: Process, timeoutSeconds: TimeInterval?) -> Bool {
        guard let timeoutSeconds, timeoutSeconds > 0 else {
            process.waitUntilExit()
            return false
        }

        let timeoutDate = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning {
            if Date() >= timeoutDate {
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        guard process.isRunning else {
            process.waitUntilExit()
            return false
        }

        process.terminate()
        let terminateDeadline = Date().addingTimeInterval(1.0)
        while process.isRunning {
            if Date() >= terminateDeadline {
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
        return true
    }
}
