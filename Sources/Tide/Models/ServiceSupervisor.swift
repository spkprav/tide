import Foundation
import Darwin
import Observation

@Observable
@MainActor
final class ServiceSupervisor {
    @ObservationIgnored private var runners: [UUID: ServiceRunner] = [:]
    @ObservationIgnored let store: ServiceStore
    @ObservationIgnored let runtimeStore: ServiceRuntimeStore

    var version: Int = 0

    init(store: ServiceStore) {
        self.store = store
        self.runtimeStore = ServiceRuntimeStore()
        restoreFromRuntime()
    }

    private func restoreFromRuntime() {
        for snap in runtimeStore.snapshots.values {
            guard let service = store.service(id: snap.serviceID) else {
                runtimeStore.remove(serviceID: snap.serviceID)
                continue
            }
            guard ProcInspect.isAlive(pid: snap.pid) else {
                runtimeStore.remove(serviceID: snap.serviceID)
                continue
            }
            if snap.startSec != 0, let cur = ProcInspect.snapshot(pid: snap.pid) {
                if cur.startSec != snap.startSec || cur.startUsec != snap.startUsec {
                    runtimeStore.remove(serviceID: snap.serviceID)
                    continue
                }
            }
            let r = ServiceRunner(service: service, runtimeStore: runtimeStore)
            r.reattach(pid: snap.pid, port: snap.detectedPort)
            runners[service.id] = r
        }
    }

    func runner(for service: Service) -> ServiceRunner {
        if let existing = runners[service.id] { return existing }
        let r = ServiceRunner(service: service, runtimeStore: runtimeStore)
        runners[service.id] = r
        return r
    }

    func discardRunner(serviceID: UUID) {
        if let r = runners[serviceID], r.pid > 0 { r.kill() }
        runners.removeValue(forKey: serviceID)
        runtimeStore.remove(serviceID: serviceID)
        version &+= 1
    }

    var runningCount: Int {
        var count = 0
        for r in runners.values {
            switch r.status {
            case .running, .starting: count += 1
            default: break
            }
        }
        return count
    }

    func startAutoStart() {
        for service in store.services where service.autoStart {
            let r = runner(for: service)
            if r.pid == 0 { r.start() }
        }
    }

    func stopAll(timeout: TimeInterval) {
        let pids: [pid_t] = runners.values.compactMap { $0.pid > 0 ? $0.pid : nil }
        guard !pids.isEmpty else { return }

        for p in pids { _ = Darwin.kill(-p, SIGINT) }

        let deadline = Date().addingTimeInterval(timeout)
        var remaining = pids
        while Date() < deadline, !remaining.isEmpty {
            remaining = remaining.filter { Darwin.kill($0, 0) == 0 }
            if remaining.isEmpty { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        for p in remaining { _ = Darwin.kill(-p, SIGKILL) }
    }

    func notifyServicesChanged() {
        version &+= 1
    }
}
