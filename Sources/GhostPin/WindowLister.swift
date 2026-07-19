import AppKit
import CoreGraphics

struct WindowInfo {
    let windowID: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
}

enum WindowLister {
    /// Front-to-back list of normal on-screen windows belonging to other apps.
    static func onScreenWindows() -> [WindowInfo] {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        return raw.compactMap { dict in
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = dict[kCGWindowNumber as String] as? Int,
                  let pid = dict[kCGWindowOwnerPID as String] as? Int, pid != myPID,
                  let appName = dict[kCGWindowOwnerName as String] as? String,
                  let bounds = dict[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) >= 80, (bounds["Height"] ?? 0) >= 60
            else { return nil }
            let title = dict[kCGWindowName as String] as? String ?? ""
            return WindowInfo(windowID: CGWindowID(number), pid: pid_t(pid), appName: appName, title: title)
        }
    }

    static func frontmostWindowOfActiveApp() -> WindowInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return onScreenWindows().first { $0.pid == app.processIdentifier }
    }
}
