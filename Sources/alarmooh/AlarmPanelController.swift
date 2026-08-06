import AlarmoohCore
import AppKit
import SwiftUI

/// Das schwebende Fenster unter dem Menueleisten-Icon.
@MainActor
final class AlarmPanelController {
    private var panel: NSPanel?

    func show(view: AlarmView, below iconFrame: NSRect?) {
        close()

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: view)
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 320, height: 160))
        position(panel, below: iconFrame)
        panel.orderFrontRegardless()   // ohne die App zu aktivieren
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Unter dem Icon; ist es nicht sichtbar (Menueleisten-Ueberlauf, Notch),
    /// oben mittig auf dem aktiven Bildschirm.
    private func position(_ panel: NSPanel, below iconFrame: NSRect?) {
        let size = panel.frame.size
        guard let screen = NSScreen.main else { return }

        if let iconFrame, screen.frame.intersects(iconFrame) {
            let x = min(
                max(iconFrame.midX - size.width / 2, screen.visibleFrame.minX + 8),
                screen.visibleFrame.maxX - size.width - 8
            )
            panel.setFrameOrigin(NSPoint(x: x, y: iconFrame.minY - size.height - 6))
        } else {
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.maxY - size.height - 12
            ))
        }
    }
}
