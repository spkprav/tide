import Foundation
import AppKit
import UserNotifications
import CoreServices

@MainActor
final class NotificationWatcher {
    static let notifyDir: String = {
        let home = NSHomeDirectory()
        let dir = "\(home)/.tide/notify"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    var onPaneDone: ((UUID, String?) -> Void)?
    private var eventStream: FSEventStreamRef?

    func start() {
        guard eventStream == nil else { return }
        let paths = [Self.notifyDir] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<NotificationWatcher>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async {
                watcher.scanDir()
            }
        }
        eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )
        if let s = eventStream {
            FSEventStreamSetDispatchQueue(s, .main)
            FSEventStreamStart(s)
        }
        scanDir()
    }

    func stop() {
        if let s = eventStream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            eventStream = nil
        }
    }

    private func scanDir() {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: Self.notifyDir) else { return }
        for file in files where !file.hasPrefix(".") {
            let fullPath = "\(Self.notifyDir)/\(file)"
            if let uuid = UUID(uuidString: file) {
                let raw = try? String(contentsOfFile: fullPath, encoding: .utf8)
                let msg = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
                onPaneDone?(uuid, (msg?.isEmpty == false) ? msg : nil)
            }
            try? FileManager.default.removeItem(atPath: fullPath)
        }
    }

    nonisolated static func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
        }
    }

    nonisolated static func deliver(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
    }
}
