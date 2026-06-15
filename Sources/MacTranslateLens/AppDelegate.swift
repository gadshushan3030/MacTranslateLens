import AppKit
import CoreGraphics

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var selectionController: RegionSelectionController?
    private let translator = TranslationService()
    private let ocr = OCRService()
    private let capture = ScreenCaptureService()
    private let hotKeyManager = HotKeyManager()
    private var hotKeySpec: HotKeySpec?

    /// Default global shortcut. Three modifiers keep it from clashing with app
    /// shortcuts; override with the `MAC_TRANSLATE_LENS_HOTKEY` env var or the
    /// `hotkey` user default (e.g. "cmd+shift+t").
    private static let defaultHotKey = "ctrl+opt+cmd+t"

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("MacTranslateLens runs from the menu bar.")
        registerGlobalHotKey()
        configureMenuBar()
        // Preload the model in the background so even the first translation is warm.
        Task { await translator.warmUp() }
        // Screen Recording is requested lazily, only when the user picks
        // "Translate Screen Region" — the clipboard flow needs no permission.
    }

    private func registerGlobalHotKey() {
        let raw = ProcessInfo.processInfo.environment["MAC_TRANSLATE_LENS_HOTKEY"]
            ?? UserDefaults.standard.string(forKey: "hotkey")
            ?? Self.defaultHotKey

        let spec = HotKeyManager.parse(raw) ?? HotKeyManager.parse(Self.defaultHotKey)
        hotKeySpec = spec

        guard let spec else { return }
        hotKeyManager.register(spec) { [weak self] in
            Task { @MainActor in self?.translateClipboard() }
        }
    }

    private func configureMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Lens"

        let menu = NSMenu()

        let clipboardItem = NSMenuItem(
            title: "Translate Clipboard",
            action: #selector(translateClipboard),
            keyEquivalent: hotKeySpec?.keyEquivalent ?? ""
        )
        clipboardItem.keyEquivalentModifierMask = hotKeySpec?.modifierMask ?? []
        menu.addItem(clipboardItem)

        if let display = hotKeySpec?.display {
            let hint = NSMenuItem(title: "Global shortcut: \(display)", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Translate Screen Region…", action: #selector(translateScreenRegion), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        for menuItem in menu.items where menuItem.action != nil {
            menuItem.target = self
        }

        item.menu = menu
        statusItem = item
    }

    @objc private func translateScreenRegion() {
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            ResultWindow.show(
                title: "Screen Recording Required",
                body: "Enable Screen Recording for MacTranslateLens in System Settings, then quit and reopen the app."
            )
            return
        }

        guard let screen = NSScreen.main else {
            ResultWindow.show(title: "MacTranslateLens", body: "No active screen found.")
            return
        }

        let controller = RegionSelectionController(screen: screen)
        selectionController = controller

        controller.begin { [weak self] rect in
            guard let self else { return }
            self.selectionController = nil

            guard let rect, rect.width > 8, rect.height > 8 else { return }
            Task { await self.translateRegion(rect, on: screen) }
        }
    }

    @objc private func translateClipboard() {
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            ResultWindow.show(title: "Clipboard", body: "Clipboard does not contain text.")
            return
        }

        Task { await translateText(text, source: "Clipboard") }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    /// Keep running in the menu bar after the result window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func translateRegion(_ rect: CGRect, on screen: NSScreen) async {
        do {
            let image = try capture.capture(rect: rect, on: screen)
            let text = try await ocr.recognizeText(in: image)

            guard !text.isEmpty else {
                await MainActor.run {
                    ResultWindow.show(title: "OCR", body: "No text found in the selected area.")
                }
                return
            }

            await translateText(text, source: "Screen Region")
        } catch {
            await MainActor.run {
                ResultWindow.show(title: "Capture Failed", body: error.localizedDescription)
            }
        }
    }

    private func translateText(_ text: String, source: String) async {
        ResultWindow.show(title: source, body: "מתרגם…")

        do {
            let result = try await translator.translateToHebrew(text)
            ResultWindow.show(
                title: source,
                body: result.text,
                thinking: result.thinking,
                stats: Self.formatStats(result)
            )
        } catch {
            ResultWindow.show(
                title: "Local Model Error",
                body: "\(error.localizedDescription)\n\nStart Ollama or LM Studio locally, then try again."
            )
        }
    }

    /// Builds the footer line: response time, throughput, and memory footprint.
    private static func formatStats(_ result: TranslationResult) -> String {
        var parts: [String] = []
        if result.totalSeconds > 0 {
            parts.append(String(format: "⏱ %.1fs", result.totalSeconds))
        }
        if let tps = result.tokensPerSecond {
            parts.append(String(format: "%.0f tok/s", tps))
        }
        if let bytes = result.modelMemoryBytes {
            let gb = Double(bytes) / 1_000_000_000
            let total = Double(ProcessInfo.processInfo.physicalMemory)
            let percent = total > 0 ? Int((Double(bytes) / total * 100).rounded()) : 0
            parts.append(String(format: "🧠 %.1f GB · %d%% RAM", gb, percent))
        }
        parts.append(result.model)
        return parts.joined(separator: "   ·   ")
    }
}
