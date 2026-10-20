import Darwin
import Foundation
import os

/// Runs a command-line tool by absolute path, without a shell, with a timeout. Output is read while the tool runs,
/// so a large answer can't block it on a full pipe.
enum ProcessRunner {
    struct Output: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
        let timedOut: Bool

        var succeeded: Bool { status == 0 && !timedOut }

        /// The tool's own error message, shortened for display.
        var errorMessage: String {
            if timedOut {
                return String(localized: "The tool didn't answer in time.",
                              comment: "Error when a command-line tool (docker, xcrun) times out")
            }
            let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = text.isEmpty ? stdout.trimmingCharacters(in: .whitespacesAndNewlines) : text
            let code = Int(status)
            return message.isEmpty
                ? String(localized: "Exit code \(code)", comment: "Error of a command-line tool that gave no message")
                : String(message.prefix(300))
        }
    }

    enum Failure: Error { case launch(String) }

    /// GUI apps don't inherit the shell PATH; tools such as docker look up their helpers through it. The system's
    /// own folders come first, and library-injection variables are dropped, as are git's and buildx's own
    /// (`GIT_DIR`, `BUILDX_BUILDER`, ... from a Terminal that started the app would point the tools somewhere else).
    private static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("DYLD_") && !$0.key.hasPrefix("LD_") && !$0.key.hasPrefix("GIT_")
                && !$0.key.hasPrefix("BUILDX_")
        }
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:\(NSHomeDirectory())/.docker/bin"
        return env
    }()

    /// More output than any of the tools gives; anything beyond it is dropped rather than kept in memory.
    private static let outputLimit = 64 * 1024 * 1024

    /// Asks the tool and the processes it started (docker's buildx, simctl under xcrun) to quit, and kills them when
    /// they are still running five seconds later, so a hung tool can't keep a scan or a cleanup waiting forever.
    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        let family = (descendants(of: pid) + [pid]).compactMap { member in startTime(member).map { (member, $0) } }
        for (member, _) in family { kill(member, SIGTERM) }
        Task.detached {
            try? await Task.sleep(for: .seconds(5))
            // The same processes only, also a helper whose parent already quit: a process number freed meanwhile
            // may belong to something else now, and a different start time tells it apart.
            for (member, started) in family where startTime(member) == started { kill(member, SIGKILL) }
        }
    }

    private static func startTime(_ pid: pid_t) -> UInt64? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbi_start_tvsec &* 1_000_000 &+ info.pbi_start_tvusec
    }

    /// Children first, then their children.
    private static func descendants(of pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 4096)
        let count = Int(proc_listchildpids(pid, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size)))
        let children = buffer.prefix(max(0, min(count, buffer.count))).filter { $0 > 0 }
        return children.flatMap { descendants(of: $0) + [$0] }
    }

    static func run(
        _ executable: String, _ arguments: [String], timeout: Duration, extraEnvironment: [String: String] = [:]
    ) async throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment.merging(extraEnvironment) { _, extra in extra }
        process.standardInput = FileHandle.nullDevice
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBuffer = OSAllocatedUnfairLock(initialState: Data())
        let stderrBuffer = OSAllocatedUnfairLock(initialState: Data())
        // Each pipe is read only here, until its end; the end is marked so the result waits for the last bytes.
        let ended = OSAllocatedUnfairLock(initialState: 0)
        for (pipe, buffer) in [(stdoutPipe, stdoutBuffer), (stderrPipe, stderrBuffer)] {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    ended.withLock { $0 += 1 }
                } else {
                    buffer.withLock { if $0.count < outputLimit { $0.append(data.prefix(outputLimit - $0.count)) } }
                }
            }
        }
        func stopReading() {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
        }
        let timedOut = OSAllocatedUnfairLock(initialState: false)
        let timer = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

        let status: Int32
        do {
            status = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { finished in
                        continuation.resume(returning: finished.terminationStatus)
                    }
                    do {
                        try process.run()
                    } catch {
                        process.terminationHandler = nil
                        continuation.resume(throwing: Failure.launch(error.localizedDescription))
                        return
                    }
                    // Cancelled while it was starting: the cancellation handler found nothing running yet.
                    if Task.isCancelled { stop(process) }
                    let task = Task.detached {
                        try? await Task.sleep(for: timeout)
                        if !Task.isCancelled, process.isRunning {
                            timedOut.withLock { $0 = true }
                            stop(process)
                        }
                    }
                    timer.withLock { $0 = task }
                }
            } onCancel: {
                stop(process)
            }
        } catch {
            stopReading()
            throw error
        }
        timer.withLock { $0?.cancel() }
        // The last output arrives right after the tool exits; a helper it started may keep a pipe open, so this
        // waits two seconds at most.
        for _ in 0..<100 {
            if ended.withLock({ $0 }) == 2 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        stopReading()
        let outData = stdoutBuffer.withLock { $0 }
        let errData = stderrBuffer.withLock { $0 }
        return Output(
            status: status,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self),
            timedOut: timedOut.withLock { $0 }
        )
    }

    static func firstExecutable(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
