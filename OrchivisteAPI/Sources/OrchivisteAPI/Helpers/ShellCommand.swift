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

        let outBuffer = ThreadSafeDataBuffer()
        let errBuffer = ThreadSafeDataBuffer()
        if captureOutput {
            let stdoutReader = stdoutPipe.fileHandleForReading
            stdoutReader.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                outBuffer.append(chunk)
            }

            let stderrReader = stderrPipe.fileHandleForReading
            stderrReader.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                errBuffer.append(chunk)
            }
        }

        let didTimeout = waitForProcess(process, timeoutSeconds: timeoutSeconds)
        if captureOutput {
            let stdoutReader = stdoutPipe.fileHandleForReading
            let stderrReader = stderrPipe.fileHandleForReading
            stdoutReader.readabilityHandler = nil
            stderrReader.readabilityHandler = nil
            outBuffer.append(stdoutReader.readDataToEndOfFile())
            errBuffer.append(stderrReader.readDataToEndOfFile())
        }
        let outData = outBuffer.snapshot()
        let errData = errBuffer.snapshot()
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

private final class ThreadSafeDataBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
