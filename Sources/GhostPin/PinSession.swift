import AppKit
import ScreenCaptureKit
import CoreMedia

/// One pinned window: a floating panel showing a live ScreenCaptureKit mirror
/// of the target window.
final class PinSession: NSObject {
    let windowID: CGWindowID
    let appName: String
    let title: String

    private let panel: NSPanel
    private let mirrorView: MirrorView
    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "ghostpin.frames")

    // Holds the buffer whose IOSurface the layer is currently displaying, so the
    // capture pool cannot recycle it mid-display.
    private var displayedBuffer: CMSampleBuffer?

    private(set) var isGhost = false
    private var baseAlpha: CGFloat = 1.0
    private var sourceAspect: CGFloat
    private var closed = false

    var onClosed: ((PinSession) -> Void)?

    init(scWindow: SCWindow, cascadeIndex: Int) {
        windowID = scWindow.windowID
        appName = scWindow.owningApplication?.applicationName ?? "App"
        title = scWindow.title ?? ""

        let sourceFrame = scWindow.frame
        sourceAspect = max(sourceFrame.width, 1) / max(sourceFrame.height, 1)

        let width = min(max(sourceFrame.width * 0.35, 240), 560)
        let height = width / sourceAspect
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let offset = CGFloat(cascadeIndex % 5) * 32
        let origin = CGPoint(x: screen.maxX - width - 24 - offset,
                             y: screen.minY + 24 + offset)

        panel = NSPanel(contentRect: CGRect(origin: origin, size: CGSize(width: width, height: height)),
                        styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        mirrorView = MirrorView(frame: CGRect(x: 0, y: 0, width: width, height: height))

        super.init()

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentAspectRatio = CGSize(width: sourceAspect, height: 1)
        panel.minSize = CGSize(width: 160, height: 160 / sourceAspect)
        panel.contentView = mirrorView
        mirrorView.delegate = self
        mirrorView.sourceAspect = sourceAspect

        panel.orderFrontRegardless()
        startCapture(scWindow: scWindow)
    }

    // MARK: - Capture

    private func startCapture(scWindow: SCWindow) {
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCStreamConfiguration()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        config.width = max(Int(scWindow.frame.width * scale), 2)
        config.height = max(Int(scWindow.frame.height * scale), 2)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 5
        config.showsCursor = false
        config.scalesToFit = true

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        } catch {
            fail(error)
            return
        }
        stream.startCapture { [weak self] error in
            if let error {
                DispatchQueue.main.async { self?.fail(error) }
            }
        }
    }

    private func fail(_ error: Error) {
        NSLog("GhostPin capture failed for \(appName): \(error.localizedDescription)")
        close()
    }

    // MARK: - Controls

    func setGhost(_ on: Bool) {
        isGhost = on
        panel.ignoresMouseEvents = on
        panel.alphaValue = on ? min(baseAlpha, 0.65) : baseAlpha
        mirrorView.setGhostAppearance(on)
    }

    func close() {
        guard !closed else { return }
        closed = true
        stream?.stopCapture()
        stream = nil
        panel.orderOut(nil)
        onClosed?(self)
    }

    private func updateAspectIfNeeded(_ aspect: CGFloat) {
        guard abs(aspect - sourceAspect) > 0.01 else { return }
        sourceAspect = aspect
        mirrorView.sourceAspect = aspect
        // A zero aspect ratio means the user Shift-resized to a free shape; track
        // the source's aspect but stop snapping the panel to it.
        guard panel.contentAspectRatio != .zero else { return }
        panel.contentAspectRatio = CGSize(width: aspect, height: 1)
        panel.minSize = CGSize(width: 160, height: 160 / aspect)
        var frame = panel.frame
        let newHeight = frame.width / aspect
        frame.origin.y += frame.height - newHeight
        frame.size.height = newHeight
        panel.setFrame(frame, display: true, animate: false)
    }
}

// MARK: - SCStreamOutput / SCStreamDelegate

extension PinSession: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let statusRaw = info[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }

        var contentsRect: CGRect?
        var aspect: CGFloat?
        if let rectValue = info[.contentRect],
           let rect = CGRect(dictionaryRepresentation: rectValue as! CFDictionary),
           let scaleFactor = info[.scaleFactor] as? CGFloat,
           rect.width > 1, rect.height > 1 {
            let bufferWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
            let bufferHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
            contentsRect = CGRect(x: rect.minX * scaleFactor / bufferWidth,
                                  y: rect.minY * scaleFactor / bufferHeight,
                                  width: rect.width * scaleFactor / bufferWidth,
                                  height: rect.height * scaleFactor / bufferHeight)
            aspect = rect.width / rect.height
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, !self.closed else { return }
            self.displayedBuffer = sampleBuffer
            self.mirrorView.display(surface: surface, contentsRect: contentsRect)
            if let aspect { self.updateAspectIfNeeded(aspect) }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.close()
        }
    }
}

// MARK: - MirrorViewDelegate

extension PinSession: MirrorViewDelegate {
    func mirrorViewDidToggleGhost() { setGhost(!isGhost) }

    func mirrorViewDidRequestUnpin() { close() }

    func mirrorViewDidChangeOpacity(_ value: CGFloat) {
        baseAlpha = value
        panel.alphaValue = isGhost ? min(value, 0.65) : value
    }

    func mirrorViewDidRequestSizeToggle() {
        let small: CGFloat = 220
        let large = min(max(panel.frame.width * 2, 480), 800)
        let targetWidth = panel.frame.width <= small + 1 ? large : small
        var frame = panel.frame
        let anchorTopRight = CGPoint(x: frame.maxX, y: frame.maxY)
        frame.size = CGSize(width: targetWidth, height: targetWidth / sourceAspect)
        frame.origin = CGPoint(x: anchorTopRight.x - frame.width, y: anchorTopRight.y - frame.height)
        panel.setFrame(frame, display: true, animate: true)
    }
}
