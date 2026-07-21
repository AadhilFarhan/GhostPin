import AppKit
import ScreenCaptureKit

final class PinManager {
    static let shared = PinManager()

    private(set) var sessions: [PinSession] = []
    private(set) var ghostAll = false
    private var pinningInFlight = Set<CGWindowID>()

    func isPinned(_ windowID: CGWindowID) -> Bool {
        sessions.contains { $0.windowID == windowID } || pinningInFlight.contains(windowID)
    }

    /// Pins the window, or unpins it if already pinned.
    func toggle(windowID: CGWindowID) {
        if let existing = sessions.first(where: { $0.windowID == windowID }) {
            existing.close()
            return
        }
        guard !pinningInFlight.contains(windowID) else { return }
        guard CGPreflightScreenCaptureAccess() else {
            PermissionHelper.promptForScreenRecording()
            return
        }
        pinningInFlight.insert(windowID)
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pinningInFlight.remove(windowID)
                guard let scWindow = content?.windows.first(where: { $0.windowID == windowID }) else {
                    if let error {
                        NSLog("GhostPin: shareable content error: \(error.localizedDescription)")
                    }
                    self.showAlert("Couldn't pin that window",
                                   "The window is no longer available for capture. If you just granted Screen Recording permission, quit and reopen GhostPin.")
                    return
                }
                let session = PinSession(scWindow: scWindow, cascadeIndex: self.sessions.count)
                session.onClosed = { [weak self] closedSession in
                    guard let self else { return }
                    self.sessions.removeAll { $0 === closedSession }
                    if self.sessions.isEmpty { self.ghostAll = false }
                }
                if self.ghostAll { session.setGhost(true) }
                self.sessions.append(session)
                session.start(scWindow: scWindow)
            }
        }
    }

    func toggleGhost(windowID: CGWindowID) {
        guard let session = sessions.first(where: { $0.windowID == windowID }) else { return }
        session.setGhost(!session.isGhost)
    }

    func unpinAll() {
        for session in sessions { session.close() }
        ghostAll = false
    }

    func toggleGhostAll() {
        ghostAll = !sessions.isEmpty && !ghostAll
        for session in sessions { session.setGhost(ghostAll) }
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
