import AppKit
import CoreGraphics

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var selectionController: RegionSelectionController?
    private let translator = TranslationService()
    private let ocr = OCRService()
    private let capture = ScreenCaptureService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("MacTranslateLens runs from the menu bar.")
        configureMenuBar()
        requestScreenRecordingPermissionIfNeeded()
    }

    private func configureMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Lens"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Translate Screen Region", action: #selector(translateScreenRegion), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Translate Clipboard", action: #selector(translateClipboard), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Request Screen Recording Permission", action: #selector(requestScreenRecordingPermission), keyEquivalent: "p"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        for menuItem in menu.items {
            menuItem.target = self
        }

        item.menu = menu
        statusItem = item
    }

    private func requestScreenRecordingPermissionIfNeeded() {
        guard !CGPreflightScreenCaptureAccess() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            _ = CGRequestScreenCaptureAccess()
        }
    }

    @objc private func requestScreenRecordingPermission() {
        if CGPreflightScreenCaptureAccess() {
            ResultWindow.show(title: "Screen Recording", body: "Screen Recording permission is already enabled.")
        } else {
            _ = CGRequestScreenCaptureAccess()
        }
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
        await MainActor.run {
            ResultWindow.show(title: source, body: "Translating locally...")
        }

        do {
            let translation = try await translator.translateToHebrew(text)
            await MainActor.run {
                ResultWindow.show(title: source, body: translation)
            }
        } catch {
            await MainActor.run {
                ResultWindow.show(
                    title: "Local Model Error",
                    body: "\(error.localizedDescription)\n\nStart Ollama or LM Studio locally, then try again."
                )
            }
        }
    }
}
