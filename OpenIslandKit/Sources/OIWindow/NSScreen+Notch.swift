@preconcurrency package import AppKit

// MARK: - NSScreen + Notch

package extension NSScreen {
    /// The size of the hardware notch on this screen, or `nil` if there is no notch.
    ///
    /// Uses the `safeAreaInsets` top inset as a proxy: screens with a notch have a
    /// non-zero top safe area inset. The notch width is derived from `auxiliaryTopLeftArea`
    /// and `auxiliaryTopRightArea`, with safety padding to ensure closed-state modules
    /// never overlap the physical camera housing.
    var notchSize: CGSize? {
        guard self.hasPhysicalNotch else { return nil }

        let topInset = safeAreaInsets.top
        guard topInset > 0 else { return nil }

        let paddedWidth = self.reservedNotchExclusionWidth
        guard paddedWidth > 0 else { return nil }
        return CGSize(width: paddedWidth, height: topInset)
    }

    /// Conservatively reserved center width where closed-state content should never render.
    ///
    /// Adds `notchSafetyPadding` on each side of the raw exclusion width to guarantee
    /// visual clearance from the camera housing.
    var reservedNotchExclusionWidth: CGFloat {
        let leftWidth = auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = auxiliaryTopRightArea?.width ?? 0
        let baseWidth = frame.width - leftWidth - rightWidth
        guard baseWidth > 0 else { return 0 }
        return baseWidth + Self.notchSafetyPadding * 2
    }

    var hasPhysicalNotch: Bool {
        self.isBuiltinDisplay && safeAreaInsets.top > 0
    }

    /// `CGDisplayIsBuiltin` checks the display hardware connection type.
    var isBuiltinDisplay: Bool {
        let displayID = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let displayID else { return false }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    static var builtin: NSScreen? {
        screens.first { $0.isBuiltinDisplay }
    }

    // MARK: Private

    /// Per-side safety padding added to the raw notch exclusion width.
    ///
    /// The raw width from `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` defines the exact
    /// camera exclusion zone. Adding 12pt per side provides a visual safety margin so
    /// closed-state modules never crowd the physical camera housing.
    private static let notchSafetyPadding: CGFloat = 12
}
