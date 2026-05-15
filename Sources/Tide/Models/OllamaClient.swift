import Foundation

enum OllamaClient {
    static let defaultURL = URL(string: "http://localhost:11434/api/generate")!

    enum Verdict {
        case done
        case notDone
        case unknown
    }

    static func askIfDone(model: String, task: String, output: String) async -> Verdict {
        let trimmedOutput = String(output.suffix(3000))
        let prompt = """
        You are watching a terminal session.
        The user's task: "\(task)"

        Recent terminal output:
        ----
        \(trimmedOutput)
        ----

        Is the task complete and the terminal idle (waiting for new input, no work in progress)?
        Reply with exactly one word: YES or NO.
        """

        var req = URLRequest(url: defaultURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 45
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": 0.0],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .unknown
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = obj["response"] as? String else {
                return .unknown
            }
            let answer = raw.uppercased()
            if answer.contains("YES") && !answer.contains("NOT YES") {
                return .done
            }
            if answer.contains("NO") {
                return .notDone
            }
            return .unknown
        } catch {
            return .unknown
        }
    }
}
