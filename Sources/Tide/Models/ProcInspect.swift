import Foundation
import Darwin

struct ProcSnapshot: Hashable {
    let startSec: UInt64
    let startUsec: UInt64
    let execPath: String
}

enum ProcInspect {
    private static let PROC_PIDTBSDINFO: Int32 = 3
    private static let PROC_PIDPATHINFO_MAXSIZE: Int = 4096

    static func isAlive(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        let r = Darwin.kill(pid, 0)
        if r == 0 { return true }
        return errno == EPERM
    }

    static func snapshot(pid: pid_t) -> ProcSnapshot? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let rc = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, ptr, size)
        }
        guard rc == size else { return nil }
        var pathBuf = [CChar](repeating: 0, count: PROC_PIDPATHINFO_MAXSIZE)
        let pr = proc_pidpath(pid, &pathBuf, UInt32(PROC_PIDPATHINFO_MAXSIZE))
        let path: String
        if pr > 0 {
            path = pathBuf.withUnsafeBufferPointer { buf in
                buf.baseAddress.map { String(cString: $0) } ?? ""
            }
        } else {
            path = ""
        }
        return ProcSnapshot(
            startSec: UInt64(info.pbi_start_tvsec),
            startUsec: UInt64(info.pbi_start_tvusec),
            execPath: path
        )
    }
}
