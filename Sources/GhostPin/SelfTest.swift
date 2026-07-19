import AppKit
import ScreenCaptureKit
import CoreMedia

/// Headless diagnostic, run with: open GhostPin.app --args --selftest /path/to/out.txt
/// Verifies permission, window enumeration, and one captured frame, then exits.
enum SelfTest {
    private static var probe: CaptureProbe?
    private static var lines: [String] = []
    private static var outputPath = ""

    static func run(outputPath: String) {
        self.outputPath = outputPath
        lines.append("preflight=\(CGPreflightScreenCaptureAccess())")
        guard CGPreflightScreenCaptureAccess() else {
            finish()
            return
        }
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
            DispatchQueue.main.async {
                guard let content else {
                    lines.append("shareable=error:\(error.map { String(describing: $0) } ?? "unknown")")
                    finish()
                    return
                }
                let myPID = ProcessInfo.processInfo.processIdentifier
                let candidates = content.windows.filter {
                    $0.owningApplication?.processID != myPID && $0.isOnScreen
                        && $0.windowLayer == 0 && $0.frame.width >= 200 && $0.frame.height >= 150
                }
                lines.append("windows=\(candidates.count)")
                guard let target = candidates.first else {
                    finish()
                    return
                }
                lines.append("target=\(target.owningApplication?.applicationName ?? "?"):\(Int(target.frame.width))x\(Int(target.frame.height))")
                probe = CaptureProbe(window: target) { result in
                    lines.append(result)
                    finish()
                }
                probe?.start()
            }
        }
    }

    private static func finish() {
        try? lines.joined(separator: "\n").write(toFile: outputPath, atomically: true, encoding: .utf8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
    }
}

private final class CaptureProbe: NSObject, SCStreamOutput, SCStreamDelegate {
    private let window: SCWindow
    private let completion: (String) -> Void
    private var stream: SCStream?
    private var done = false
    private let queue = DispatchQueue(label: "ghostpin.selftest")

    init(window: SCWindow, completion: @escaping (String) -> Void) {
        self.window = window
        self.completion = completion
    }

    func start() {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = max(Int(window.frame.width), 2)
        config.height = max(Int(window.frame.height), 2)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.scalesToFit = true
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        } catch {
            report("frame=addOutputError:\(error)")
            return
        }
        stream.startCapture { [weak self] error in
            if let error { self?.report("frame=startError:\(error)") }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.report("frame=timeout")
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let statusRaw = info[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer
        else { return }
        report("frame=\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer)):ok")
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        report("frame=stopped:\(error)")
    }

    private func report(_ line: String) {
        DispatchQueue.main.async {
            guard !self.done else { return }
            self.done = true
            self.stream?.stopCapture()
            self.completion(line)
        }
    }
}
