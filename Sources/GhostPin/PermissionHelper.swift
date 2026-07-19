import AppKit

enum PermissionHelper {
    static func ensureScreenRecordingAccess() {
        guard !CGPreflightScreenCaptureAccess() else { return }
        CGRequestScreenCaptureAccess()
    }

    static func promptForScreenRecording() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = "GhostPin mirrors windows using screen capture, so macOS requires Screen Recording permission.\n\nEnable GhostPin in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen GhostPin."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
