import AppKit

@MainActor
final class RegionSelectionController: NSObject {
    private let window: RegionSelectionWindow
    private var completion: ((CGRect?) -> Void)?

    init(screen: NSScreen) {
        self.window = RegionSelectionWindow(screen: screen)
        super.init()
        self.window.onComplete = { [weak self] rect in
            self?.finish(rect)
        }
    }

    func begin(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(_ rect: CGRect?) {
        window.orderOut(nil)
        completion?(rect)
        completion = nil
    }
}

@MainActor
final class RegionSelectionWindow: NSWindow {
    var onComplete: ((CGRect?) -> Void)?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = false

        let view = RegionSelectionView(frame: screen.frame)
        view.onComplete = onComplete
        contentView = view

        view.onComplete = { [weak self] rect in
            self?.onComplete?(rect)
        }
    }

    override var canBecomeKey: Bool { true }
}

@MainActor
final class RegionSelectionView: NSView {
    var onComplete: ((CGRect?) -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.24).setFill()
        bounds.fill()

        guard let rect = selectedRect else { return }

        NSColor.clear.setFill()
        rect.fill(using: .clear)

        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)

        guard let rect = selectedRect, let window else {
            onComplete?(nil)
            return
        }

        let screenRect = window.convertToScreen(rect)
        onComplete?(screenRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onComplete?(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    private var selectedRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }

        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }
}
