import AppKit
import IOSurface

protocol MirrorViewDelegate: AnyObject {
    func mirrorViewDidToggleGhost()
    func mirrorViewDidRequestUnpin()
    func mirrorViewDidChangeOpacity(_ value: CGFloat)
    func mirrorViewDidRequestSizeToggle()
}

final class MirrorView: NSView {
    weak var delegate: MirrorViewDelegate?

    private let videoLayer = CALayer()
    private let controlStrip = NSVisualEffectView()
    private let opacitySlider = NSSlider(value: 1.0, minValue: 0.25, maxValue: 1.0, target: nil, action: nil)
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true

        videoLayer.contentsGravity = .resizeAspect
        videoLayer.frame = bounds
        videoLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(videoLayer)

        setUpControlStrip()

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
        doubleClick.numberOfClicksRequired = 2
        doubleClick.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(doubleClick)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { true }

    // MARK: - Frames

    func display(surface: IOSurfaceRef, contentsRect: CGRect?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.contents = surface
        if let contentsRect { videoLayer.contentsRect = contentsRect }
        CATransaction.commit()
    }

    func setGhostAppearance(_ ghost: Bool) {
        layer?.borderWidth = ghost ? 2 : 0
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
        if ghost { controlStrip.alphaValue = 0 }
    }

    // MARK: - Control strip

    private func setUpControlStrip() {
        controlStrip.material = .hudWindow
        controlStrip.state = .active
        controlStrip.wantsLayer = true
        controlStrip.layer?.cornerRadius = 8
        controlStrip.layer?.masksToBounds = true
        controlStrip.alphaValue = 0

        let ghostButton = stripButton(symbol: "eye.slash", tooltip: "Ghost mode — click-through (⌥⌘G)", action: #selector(ghostTapped))
        let unpinButton = stripButton(symbol: "pin.slash", tooltip: "Unpin", action: #selector(unpinTapped))

        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged)
        opacitySlider.controlSize = .mini
        opacitySlider.translatesAutoresizingMaskIntoConstraints = false
        opacitySlider.widthAnchor.constraint(equalToConstant: 64).isActive = true
        opacitySlider.toolTip = "Opacity"

        let stack = NSStackView(views: [ghostButton, opacitySlider, unpinButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false

        controlStrip.translatesAutoresizingMaskIntoConstraints = false
        controlStrip.addSubview(stack)
        addSubview(controlStrip)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: controlStrip.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: controlStrip.trailingAnchor),
            stack.topAnchor.constraint(equalTo: controlStrip.topAnchor),
            stack.bottomAnchor.constraint(equalTo: controlStrip.bottomAnchor),
            controlStrip.centerXAnchor.constraint(equalTo: centerXAnchor),
            controlStrip.topAnchor.constraint(equalTo: topAnchor, constant: 8),
        ])
    }

    private func stripButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.contentTintColor = .white
        return button
    }

    @objc private func ghostTapped() { delegate?.mirrorViewDidToggleGhost() }
    @objc private func unpinTapped() { delegate?.mirrorViewDidRequestUnpin() }
    @objc private func opacityChanged() { delegate?.mirrorViewDidChangeOpacity(CGFloat(opacitySlider.doubleValue)) }
    @objc private func handleDoubleClick() { delegate?.mirrorViewDidRequestSizeToggle() }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            controlStrip.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            controlStrip.animator().alphaValue = 0
        }
    }
}
