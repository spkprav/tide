import Foundation
import Darwin
import SwiftTerm

@MainActor
func killTerminalProcessTree(_ view: LocalProcessTerminalView) {
    let pid = view.process.shellPid
    sendKillEscalation(toProcessGroup: pid)
    view.terminate()
}

nonisolated func sendKillEscalation(toProcessGroup pid: pid_t) {
    guard pid > 0 else { return }
    DispatchQueue.global(qos: .userInitiated).async {
        _ = Darwin.kill(-pid, SIGINT)
        usleep(400_000)
        if Darwin.kill(pid, 0) == 0 {
            _ = Darwin.kill(-pid, SIGTERM)
            usleep(800_000)
            if Darwin.kill(pid, 0) == 0 {
                _ = Darwin.kill(-pid, SIGKILL)
            }
        }
    }
}
