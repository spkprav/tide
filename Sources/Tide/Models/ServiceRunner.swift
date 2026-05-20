import Foundation
import Darwin
import Observation

@Observable
@MainActor
final class ServiceRunner {
    let service: Service
    var status: ServiceStatus = .stopped
    var pid: pid_t = 0
    var detectedPort: Int?
    var lastError: String?

    @ObservationIgnored private var watcher: DispatchSourceProcess?
    @ObservationIgnored private var portPollTimer: Timer?
    @ObservationIgnored private var stopRequested = false
    @ObservationIgnored private var downStarted = false
    @ObservationIgnored private var lastExitCode: Int32 = 0
    @ObservationIgnored private var pendingRestart = false
    @ObservationIgnored private var isOwnChild = false
    @ObservationIgnored private var stderrLogPath: String?
    @ObservationIgnored private weak var runtimeStore: ServiceRuntimeStore?

    init(service: Service, runtimeStore: ServiceRuntimeStore? = nil) {
        self.service = service
        self.runtimeStore = runtimeStore
    }

    func start() {
        guard pid == 0, status.isTerminal || status == .stopped else { return }
        status = .starting
        stopRequested = false
        downStarted = false
        lastError = nil
        detectedPort = nil
        stderrLogPath = nil

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.augmentedPath(env["PATH"])
        for (k, v) in service.env { env[k] = v }

        let cwd = service.expandedCwd
        if !FileManager.default.fileExists(atPath: cwd) {
            status = .failed("cwd does not exist: \(cwd)")
            return
        }

        let logPath = NSTemporaryDirectory() + "tide-service-\(service.id.uuidString).log"
        let result = SpawnHelper.spawnDetached(
            command: service.startCommand,
            cwd: cwd,
            env: env,
            stderrLogPath: logPath
        )

        switch result {
        case .success(let childPid):
            pid = childPid
            status = .running
            isOwnChild = true
            stderrLogPath = logPath
            attachWatcher(for: childPid, isOwnChild: true)
            persistRuntimeSnapshot()
            startPortPolling()
        case .failure(let err):
            pid = 0
            lastError = err
            status = .failed(err)
        }
    }

    private static func augmentedPath(_ current: String?) -> String {
        let extras = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin"]
        var parts = (current ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        let existing = Set(parts)
        for e in extras where !existing.contains(e) {
            if FileManager.default.fileExists(atPath: e) { parts.insert(e, at: 0) }
        }
        return parts.joined(separator: ":")
    }

    private func readStderrTail(_ path: String?) -> String? {
        guard let path = path, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let max = 512
        let slice = data.count > max ? data.suffix(max) : data
        guard let s = String(data: slice, encoding: .utf8) else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func reattach(pid: pid_t, port: Int?) {
        guard pid > 0, ProcInspect.isAlive(pid: pid) else { return }
        self.pid = pid
        self.status = .running
        self.detectedPort = port
        self.stopRequested = false
        self.downStarted = false
        self.isOwnChild = false
        attachWatcher(for: pid, isOwnChild: false)
        startPortPolling()
    }

    func stop() {
        guard pid > 0 else { return }
        stopRequested = true
        status = .stopping
        sendKillEscalation(toProcessGroup: pid)
    }

    func kill() {
        guard pid > 0 else { return }
        stopRequested = true
        status = .stopping
        _ = Darwin.kill(-pid, SIGKILL)
    }

    func restart() {
        if pid > 0 {
            pendingRestart = true
            stop()
        } else {
            start()
        }
    }

    private func attachWatcher(for childPid: pid_t, isOwnChild: Bool) {
        let src = DispatchSource.makeProcessSource(identifier: childPid, eventMask: .exit, queue: .main)
        src.setEventHandler { [weak self, weak src] in
            guard let self = self else { return }
            var code: Int32 = 0
            if isOwnChild {
                var statusBits: Int32 = 0
                _ = Darwin.waitpid(childPid, &statusBits, 0)
                if (statusBits & 0x7f) == 0 {
                    code = (statusBits >> 8) & 0xff
                } else {
                    code = -(statusBits & 0x7f)
                }
            }
            src?.cancel()
            Task { @MainActor [weak self] in
                self?.onReap(code: code)
            }
        }
        src.resume()
        watcher = src
    }

    private func onReap(code: Int32) {
        stopPortPolling()
        watcher = nil
        pid = 0
        detectedPort = nil
        lastExitCode = code
        clearRuntimeSnapshot()

        let intentional = stopRequested
        let hasDown = (service.downCommand?.isEmpty == false)

        if intentional && hasDown && !downStarted {
            runDownCommand()
        } else {
            if intentional {
                status = .stopped
            } else {
                let tail = readStderrTail(stderrLogPath)
                if code != 0 {
                    if let tail = tail {
                        lastError = tail
                        status = .failed(tail.split(separator: "\n").first.map(String.init) ?? "exited (\(code))")
                    } else {
                        status = .exited(code)
                    }
                } else {
                    status = .exited(code)
                }
            }
            if let p = stderrLogPath { try? FileManager.default.removeItem(atPath: p) }
            stderrLogPath = nil
            if pendingRestart {
                pendingRestart = false
                start()
            }
        }
    }

    private func runDownCommand() {
        guard let cmd = service.downCommand, !cmd.isEmpty else {
            status = .stopped
            return
        }
        downStarted = true
        status = .down

        var env = ProcessInfo.processInfo.environment
        for (k, v) in service.env { env[k] = v }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", cmd]
        proc.currentDirectoryURL = URL(fileURLWithPath: service.expandedCwd)
        proc.environment = env
        proc.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        proc.standardError = FileHandle(forWritingAtPath: "/dev/null")
        proc.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        proc.terminationHandler = { [weak self] p in
            let code = p.terminationStatus
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if code == 0 {
                    self.status = .stopped
                } else {
                    self.lastError = "down command exited \(code)"
                    self.status = .failed("down command exited \(code)")
                }
                if self.pendingRestart {
                    self.pendingRestart = false
                    self.start()
                }
            }
        }
        do {
            try proc.run()
        } catch {
            status = .failed("Failed to run down command: \(error.localizedDescription)")
            lastError = error.localizedDescription
            if pendingRestart {
                pendingRestart = false
                start()
            }
        }
    }

    private func persistRuntimeSnapshot() {
        guard let runtimeStore = runtimeStore, pid > 0 else { return }
        let snap = ProcInspect.snapshot(pid: pid)
        let entry = ServiceRuntimeSnapshot(
            serviceID: service.id,
            pid: pid,
            startSec: snap?.startSec ?? 0,
            startUsec: snap?.startUsec ?? 0,
            execPath: snap?.execPath ?? "",
            detectedPort: detectedPort
        )
        runtimeStore.upsert(entry)
    }

    private func clearRuntimeSnapshot() {
        runtimeStore?.remove(serviceID: service.id)
    }

    private func startPortPolling() {
        stopPortPolling()
        guard pid > 0 else { return }
        let targetPid = pid
        let t = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollPortOnce(targetPid: targetPid)
            }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        portPollTimer = t
        Task { @MainActor [weak self] in self?.pollPortOnce(targetPid: targetPid) }
    }

    private func stopPortPolling() {
        portPollTimer?.invalidate()
        portPollTimer = nil
    }

    private func pollPortOnce(targetPid: pid_t) {
        guard pid == targetPid, status == .running else { return }
        DispatchQueue.global(qos: .utility).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            proc.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", "\(targetPid)"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle(forWritingAtPath: "/dev/null")
            do { try proc.run() } catch { return }
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let out = String(data: data, encoding: .utf8) else { return }
            let port = Self.parseFirstListenPort(lsofOutput: out)
            Task { @MainActor [weak self] in
                guard let self = self, self.pid == targetPid else { return }
                let changed = self.detectedPort != port
                self.detectedPort = port
                if changed { self.persistRuntimeSnapshot() }
            }
        }
    }

    nonisolated static func parseFirstListenPort(lsofOutput: String) -> Int? {
        for line in lsofOutput.split(separator: "\n") {
            guard line.contains("(LISTEN)") else { continue }
            guard let colonIdx = line.lastIndex(of: ":") else { continue }
            let after = line[line.index(after: colonIdx)...]
            let digits = after.prefix { $0.isNumber }
            if let n = Int(digits) { return n }
        }
        return nil
    }
}
