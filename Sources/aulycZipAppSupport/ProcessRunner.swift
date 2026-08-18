import Darwin
import Foundation

enum ProcessRunner {
    enum RunError: Error, Equatable {
        case launchFailed
        case timedOut
        case invalidConfiguration
    }

    struct Result: Equatable {
        let terminationStatus: Int32
        let output: String
        let outputWasTruncated: Bool
    }

    static func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval = 120,
        outputLimit: Int = 1024 * 1024
    ) throws -> Result {
        guard timeout > 0, outputLimit >= 0 else {
            throw RunError.invalidConfiguration
        }
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        let accumulator = CappedProcessOutput(limit: outputLimit)
        let readers = DispatchGroup()
        drain(standardOutput, into: accumulator, group: readers)
        drain(standardError, into: accumulator, group: readers)

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }
        do {
            try process.run()
        } catch {
            try? standardOutput.fileHandleForReading.close()
            try? standardError.fileHandleForReading.close()
            throw RunError.launchFailed
        }

        guard terminated.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            if terminated.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = terminated.wait(timeout: .now() + 1)
            }
            try? standardOutput.fileHandleForReading.close()
            try? standardError.fileHandleForReading.close()
            _ = readers.wait(timeout: .now() + 1)
            throw RunError.timedOut
        }

        if readers.wait(timeout: .now() + 1) == .timedOut {
            try? standardOutput.fileHandleForReading.close()
            try? standardError.fileHandleForReading.close()
            _ = readers.wait(timeout: .now() + 1)
        }
        let captured = accumulator.result()
        return Result(
            terminationStatus: process.terminationStatus,
            output: String(decoding: captured.data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            outputWasTruncated: captured.truncated
        )
    }

    private static func drain(
        _ pipe: Pipe,
        into accumulator: CappedProcessOutput,
        group: DispatchGroup
    ) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { group.leave() }
            while true {
                do {
                    guard let chunk = try pipe.fileHandleForReading.read(upToCount: 64 * 1024),
                          !chunk.isEmpty else { return }
                    accumulator.append(chunk)
                } catch {
                    return
                }
            }
        }
    }
}

private final class CappedProcessOutput: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var data = Data()
    private var truncated = false

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        let remaining = max(0, limit - data.count)
        if remaining > 0 { data.append(chunk.prefix(remaining)) }
        if chunk.count > remaining { truncated = true }
    }

    func result() -> (data: Data, truncated: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, truncated)
    }
}
