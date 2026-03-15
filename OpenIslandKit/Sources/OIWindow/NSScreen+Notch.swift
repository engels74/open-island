@preconcurrency package import AppKit

// MARK: - NSScreen + Notch

package extension NSScreen {
    /// The size of the hardware notch on this screen, or `nil` if there is no notch.
    ///
    /// Uses the `safeAreaInsets` top inset as a proxy: screens with a notch have a
    /// non-zero top safe area inset. The notch width is derived from `auxiliaryTopLeftArea`
    /// and `auxiliaryTopRightArea`.
    var notchSize: CGSize? {
        guard self.hasPhysicalNotch else { return nil }

        let topInset = safeAreaInsets.top
        guard topInset > 0 else { return nil }

        // The notch width = screen width - left aux area width - right aux area width.
        let leftWidth = auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = auxiliaryTopRightArea?.width ?? 0
        let notchWidth = frame.width - leftWidth - rightWidth

        guard notchWidth > 0 else { return nil }
        return CGSize(width: notchWidth, height: topInset)
    }

    /// Whether this screen has a physical notch (built-in display with top safe area inset).
    var hasPhysicalNotch: Bool {
        self.isBuiltinDisplay && safeAreaInsets.top > 0
    }

    /// Whether this screen is the built-in display (not an external monitor).
    ///
    /// Uses `CGDisplayIsBuiltin` which checks the display hardware connection type.
    var isBuiltinDisplay: Bool {
        let displayID = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let displayID else { return false }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    /// The built-in display, if currently connected.
    static var builtin: NSScreen? {
        screens.first { $0.isBuiltinDisplay }
    }
}
