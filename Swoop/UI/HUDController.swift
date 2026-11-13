import AppKit
import SwiftUI

/// Brief non-activating message bubble (used for safe activation failures).
@MainActor
final class HUDController {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ message: String, on screen: NSScreen? = NSScreen.main) {
        hideTask?.cancel()
        let view = NSHostingView(rootView:
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true))
        let size = view.fittingSize
        let panel = self.panel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            p.level = .popUpMenu
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            return p
        }()
        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.state = .active
        bg.blendingMode = .behindWindow
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 14
        bg.layer?.masksToBounds = true
        view.frame = NSRect(origin: .zero, size: size)
        bg.addSubview(view)
        panel.contentView = bg
        let v = (screen ?? NSScreen.screens[0]).visibleFrame
        panel.setFrame(NSRect(x: v.midX - size.width / 2, y: v.minY + v.height * 0.18, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }
}
