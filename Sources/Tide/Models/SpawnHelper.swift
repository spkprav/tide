import Foundation
import Darwin

enum SpawnHelper {
    enum Result {
        case success(pid_t)
        case failure(String)
    }

    static func spawnDetached(
        command: String,
        cwd: String,
        env: [String: String],
        stderrLogPath: String? = nil
    ) -> Result {
        let shell = "/bin/sh"
        let argv: [String] = [shell, "-c", command]

        var fileActions: posix_spawn_file_actions_t? = nil
        guard posix_spawn_file_actions_init(&fileActions) == 0 else {
            return .failure("posix_spawn_file_actions_init failed")
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        "/dev/null".withCString { devNull in
            posix_spawn_file_actions_addopen(&fileActions, 0, devNull, O_RDONLY, 0)
            posix_spawn_file_actions_addopen(&fileActions, 1, devNull, O_WRONLY, 0)
        }

        if let logPath = stderrLogPath {
            FileManager.default.createFile(atPath: logPath, contents: nil)
            _ = logPath.withCString { p in
                posix_spawn_file_actions_addopen(&fileActions, 2, p, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            }
        } else {
            _ = "/dev/null".withCString { devNull in
                posix_spawn_file_actions_addopen(&fileActions, 2, devNull, O_WRONLY, 0)
            }
        }

        let chdirResult = cwd.withCString { posix_spawn_file_actions_addchdir_np(&fileActions, $0) }
        if chdirResult != 0 {
            return .failure("addchdir_np(\(cwd)) failed: errno=\(chdirResult)")
        }

        var attrs: posix_spawnattr_t? = nil
        guard posix_spawnattr_init(&attrs) == 0 else {
            return .failure("posix_spawnattr_init failed")
        }
        defer { posix_spawnattr_destroy(&attrs) }

        var flags: Int16 = 0
        flags |= Int16(POSIX_SPAWN_SETPGROUP)
        posix_spawnattr_setflags(&attrs, flags)
        posix_spawnattr_setpgroup(&attrs, 0)

        let argvPtrs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
        defer { for p in argvPtrs where p != nil { free(p) } }

        var envPairs: [String] = []
        for (k, v) in env { envPairs.append("\(k)=\(v)") }
        let envpPtrs: [UnsafeMutablePointer<CChar>?] = envPairs.map { strdup($0) } + [nil]
        defer { for p in envpPtrs where p != nil { free(p) } }

        var pid: pid_t = 0
        let rc = shell.withCString { path in
            argvPtrs.withUnsafeBufferPointer { argvBuf in
                envpPtrs.withUnsafeBufferPointer { envpBuf in
                    posix_spawn(&pid, path, &fileActions, &attrs, argvBuf.baseAddress, envpBuf.baseAddress)
                }
            }
        }
        if rc != 0 {
            return .failure("posix_spawn failed: rc=\(rc) errno=\(errno) (\(String(cString: strerror(errno))))")
        }
        return .success(pid)
    }
}
