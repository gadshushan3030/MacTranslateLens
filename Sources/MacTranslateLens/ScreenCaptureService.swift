import AppKit
import CoreGraphics

enum ScreenCaptureError: LocalizedError {
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .captureFailed:
            "Could not capture the selected screen area. Check Screen Recording permission in System Settings."
        }
    }
}

struct ScreenCaptureService {
    func capture(rect: CGRect, on screen: NSScreen) throws -> CGImage {
        let scale = screen.backingScaleFactor
        let screenFrame = screen.frame

        let localRect = CGRect(
            x: rect.minX - screenFrame.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )

        let pixelRect = CGRect(
            x: localRect.minX * scale,
            y: localRect.minY * scale,
            width: localRect.width * scale,
            height: localRect.height * scale
        ).integral

        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let image = CGDisplayCreateImage(displayID, rect: pixelRect) else {
            throw ScreenCaptureError.captureFailed
        }

        return image
    }
}
