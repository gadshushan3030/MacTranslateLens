import AppKit

/// Shows translation results in a single reusable floating Liquid Glass panel.
///
/// The panel is created once and reused, so repeated translations update in
/// place. It hides (never quits the app) when it loses focus or on Escape.
@MainActor
final class ResultWindow {
    private static var panel: TranslationPanel?

    static func show(title: String, body: String, thinking: String? = nil, stats: String? = nil) {
        let panel = panel ?? {
            let created = TranslationPanel()
            self.panel = created
            return created
        }()
        panel.update(title: title, body: body, thinking: thinking, stats: stats)
        panel.present()
    }
}

@MainActor
final class TranslationPanel: NSPanel {
    private let titleLabel = NSTextField(labelWithString: "")
    private let translationView = NSTextView()
    private let thinkingView = NSTextView()
    private let thinkingHeader = NSTextField(labelWithString: "💭  חשיבת המודל")
    private let statsLabel = NSTextField(labelWithString: "")

    private var thinkingScroll: NSScrollView!
    private var thinkingGroup: NSStackView!
    private var hasThinking = false

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        contentView = makeGlassBacking(content: makeContentStack())

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appResignedActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func update(title: String, body: String, thinking: String?, stats: String?) {
        titleLabel.stringValue = title
        translationView.string = body.isEmpty ? "No translation text was returned." : body

        hasThinking = (thinking?.isEmpty == false)
        thinkingView.string = thinking ?? ""
        thinkingGroup.isHidden = !hasThinking

        statsLabel.stringValue = stats ?? ""
        statsLabel.isHidden = (stats?.isEmpty ?? true)
    }

    func present() {
        resizeForContent()
        positionTopTrailing()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Escape closes the popup.
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    @objc private func appResignedActive() {
        orderOut(nil)
    }

    private func resizeForContent() {
        let height: CGFloat = hasThinking ? 470 : 280
        var frame = self.frame
        frame.size.height = height
        setFrame(frame, display: true)
    }

    private func positionTopTrailing() {
        guard let screen = NSScreen.main else {
            center()
            return
        }
        let visible = screen.visibleFrame
        let margin: CGFloat = 24
        setFrameOrigin(NSPoint(
            x: visible.maxX - frame.width - margin,
            y: visible.maxY - frame.height - margin
        ))
    }

    // MARK: - View construction

    /// Wraps `content` in a frosted-glass backing.
    ///
    /// True Liquid Glass uses `NSGlassEffectView` (macOS 26 SDK), but that symbol
    /// only compiles under the Xcode 26 toolchain; this project's command-line
    /// Swift is older, so we render a rounded translucent vibrancy card instead —
    /// visually glassy, and a drop-in swap point for `NSGlassEffectView` later.
    private func makeGlassBacking(content: NSView) -> NSView {
        content.translatesAutoresizingMaskIntoConstraints = false

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.isEmphasized = true
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 22
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        effect.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            content.topAnchor.constraint(equalTo: effect.topAnchor),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
        return effect
    }

    private func makeContentStack() -> NSView {
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.widthAnchor.constraint(equalToConstant: 520).isActive = true

        let translationScroll = makeScroll(for: translationView, fontSize: 19, rtl: true)
        translationScroll.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)

        // Thinking group: header + its own scroll, capped height, hidden by default.
        thinkingHeader.font = .systemFont(ofSize: 12, weight: .semibold)
        thinkingHeader.textColor = .secondaryLabelColor
        thinkingHeader.widthAnchor.constraint(equalToConstant: 520).isActive = true

        thinkingScroll = makeScroll(for: thinkingView, fontSize: 12, rtl: false)
        thinkingView.textColor = .secondaryLabelColor
        thinkingScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true

        thinkingGroup = NSStackView(views: [thinkingHeader, thinkingScroll])
        thinkingGroup.orientation = .vertical
        thinkingGroup.spacing = 4
        thinkingGroup.alignment = .leading
        thinkingGroup.isHidden = true

        statsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statsLabel.textColor = .tertiaryLabelColor
        statsLabel.lineBreakMode = .byTruncatingTail
        statsLabel.widthAnchor.constraint(equalToConstant: 520).isActive = true
        statsLabel.isHidden = true

        let stack = NSStackView(views: [titleLabel, translationScroll, thinkingGroup, statsLabel])
        stack.orientation = .vertical
        stack.distribution = .fill
        stack.spacing = 10
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeScroll(for textView: NSTextView, fontSize: CGFloat, rtl: Bool) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.baseWritingDirection = rtl ? .rightToLeft : .leftToRight
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 512, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView

        // Make the scroll fill the stack width.
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalToConstant: 520)
        ])
        return scroll
    }
}
