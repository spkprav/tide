import Foundation

struct GHError: Error {
    let message: String
}

enum GitHubClient {
    struct Issue: Identifiable, Hashable {
        let id: Int
        let title: String
        let labels: [String]
        let state: String           // OPEN/CLOSED
        let createdAt: String
        let updatedAt: String
        let url: String
        let author: String
        let assignees: [String]
        let milestone: String?
        let commentsCount: Int
    }

    struct PR: Identifiable, Hashable {
        let id: Int
        let title: String
        let state: String           // OPEN/CLOSED/MERGED
        let head: String
        let createdAt: String
        let updatedAt: String
        let url: String
        let author: String
        let isDraft: Bool
        let reviewDecision: String  // APPROVED/CHANGES_REQUESTED/REVIEW_REQUIRED/empty
        let mergeable: String       // MERGEABLE/CONFLICTING/UNKNOWN
        let commentsCount: Int
        let additions: Int
        let deletions: Int
    }

    nonisolated static func ghBinaryAvailable() -> Bool {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        for p in candidates where FileManager.default.fileExists(atPath: p) {
            return true
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["gh"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return false }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }

    struct RepoRef: Hashable {
        let label: String
        let path: String
        let repo: String
        let isMain: Bool
    }

    nonisolated static func detectAllRepos(at base: String) -> [RepoRef] {
        var out: [RepoRef] = []
        if let main = detectRepo(at: base) {
            out.append(RepoRef(label: "main", path: base, repo: main, isMain: true))
        }
        for sub in detectSubmodulePaths(at: base) {
            let full = "\(base)/\(sub)"
            if let repo = detectRepo(at: full) {
                if out.contains(where: { $0.repo == repo }) { continue }
                out.append(RepoRef(label: sub, path: full, repo: repo, isMain: false))
            }
        }
        return out
    }

    nonisolated static func detectSubmodulePaths(at base: String) -> [String] {
        let gmPath = "\(base)/.gitmodules"
        guard FileManager.default.fileExists(atPath: gmPath) else { return [] }
        guard let content = try? String(contentsOfFile: gmPath, encoding: .utf8) else { return [] }
        var paths: [String] = []
        for raw in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("path") {
                let parts = t.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let p = parts[1].trimmingCharacters(in: .whitespaces)
                    if !p.isEmpty { paths.append(p) }
                }
            }
        }
        return paths
    }

    nonisolated static func detectRepo(at path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["-C", path, "remote", "get-url", "origin"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        let url = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let regex = try? NSRegularExpression(pattern: #"github\.com[:/]([\w\-.]+)/([\w\-.]+?)(\.git)?$"#) else {
            return nil
        }
        let ns = url as NSString
        guard let m = regex.firstMatch(in: url, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 3 else { return nil }
        return "\(ns.substring(with: m.range(at: 1)))/\(ns.substring(with: m.range(at: 2)))"
    }

    static func fetchIssues(repo: String) async -> Result<[Issue], GHError> {
        let result = await runGH(args: [
            "issue", "list", "--repo", repo,
            "--json", "number,title,labels,state,createdAt,updatedAt,url,author,assignees,milestone,comments",
            "--limit", "30",
        ])
        switch result {
        case .failure(let err): return .failure(err)
        case .success(let data):
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return .failure(GHError(message: "Bad JSON"))
            }
            let issues: [Issue] = arr.compactMap { (dict: [String: Any]) -> Issue? in
                guard let n = dict["number"] as? Int,
                      let t = dict["title"] as? String,
                      let s = dict["state"] as? String,
                      let url = dict["url"] as? String else { return nil }
                let labels = (dict["labels"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
                let createdAt = dict["createdAt"] as? String ?? ""
                let updatedAt = dict["updatedAt"] as? String ?? ""
                let author = (dict["author"] as? [String: Any])?["login"] as? String ?? ""
                let assignees = (dict["assignees"] as? [[String: Any]])?.compactMap { $0["login"] as? String } ?? []
                let milestone = (dict["milestone"] as? [String: Any])?["title"] as? String
                let commentsCount: Int = {
                    if let n = dict["comments"] as? Int { return n }
                    if let arr = dict["comments"] as? [Any] { return arr.count }
                    return 0
                }()
                return Issue(
                    id: n, title: t, labels: labels, state: s,
                    createdAt: createdAt, updatedAt: updatedAt, url: url, author: author,
                    assignees: assignees, milestone: milestone, commentsCount: commentsCount
                )
            }
            return .success(issues)
        }
    }

    static func fetchPRs(repo: String) async -> Result<[PR], GHError> {
        let result = await runGH(args: [
            "pr", "list", "--repo", repo,
            "--json", "number,title,state,headRefName,createdAt,updatedAt,url,author,isDraft,reviewDecision,mergeable,comments,additions,deletions",
            "--limit", "30",
        ])
        switch result {
        case .failure(let err): return .failure(err)
        case .success(let data):
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return .failure(GHError(message: "Bad JSON"))
            }
            let prs: [PR] = arr.compactMap { (dict: [String: Any]) -> PR? in
                guard let n = dict["number"] as? Int,
                      let t = dict["title"] as? String,
                      let s = dict["state"] as? String,
                      let url = dict["url"] as? String else { return nil }
                let head = dict["headRefName"] as? String ?? ""
                let createdAt = dict["createdAt"] as? String ?? ""
                let updatedAt = dict["updatedAt"] as? String ?? ""
                let author = (dict["author"] as? [String: Any])?["login"] as? String ?? ""
                let isDraft = dict["isDraft"] as? Bool ?? false
                let reviewDecision = dict["reviewDecision"] as? String ?? ""
                let mergeable = dict["mergeable"] as? String ?? ""
                let commentsCount: Int = {
                    if let n = dict["comments"] as? Int { return n }
                    if let arr = dict["comments"] as? [Any] { return arr.count }
                    return 0
                }()
                let additions = dict["additions"] as? Int ?? 0
                let deletions = dict["deletions"] as? Int ?? 0
                return PR(
                    id: n, title: t, state: s, head: head,
                    createdAt: createdAt, updatedAt: updatedAt, url: url, author: author,
                    isDraft: isDraft, reviewDecision: reviewDecision, mergeable: mergeable,
                    commentsCount: commentsCount, additions: additions, deletions: deletions
                )
            }
            return .success(prs)
        }
    }

    nonisolated static func runGH(args: [String]) async -> Result<Data, GHError> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                proc.arguments = ["gh"] + args
                var env = ProcessInfo.processInfo.environment
                let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
                let current = env["PATH"] ?? ""
                env["PATH"] = (extraPaths + [current]).filter { !$0.isEmpty }.joined(separator: ":")
                proc.environment = env
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                    let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                    if proc.terminationStatus != 0 {
                        let msg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "gh exited \(proc.terminationStatus)"
                        continuation.resume(returning: .failure(GHError(message: msg)))
                    } else {
                        continuation.resume(returning: .success(outData))
                    }
                } catch {
                    continuation.resume(returning: .failure(GHError(message: error.localizedDescription)))
                }
            }
        }
    }
}
