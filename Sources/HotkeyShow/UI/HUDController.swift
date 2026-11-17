import AppKit
import SwiftUI

enum HUDStyle {
    case peek
    case service
}

/// A borderless, click-through panel near the bottom of the focused screen.
///
/// It never becomes key or main, so showing it cannot steal focus from the
/// window you are working in, and `ignoresMouseEvents` lets clicks fall
/// through to whatever is underneath.
@MainActor
final class HUDController {
    private(set) var isVisible = false
    private(set) var style: HUDStyle = .peek

    private var panel: HUDWindow?

    func show(style: HUDStyle, content: AnyView) {
        let panel = panel ?? makePanel()
        self.panel = panel
        self.style = style

        let hosting = NSHostingView(rootView: content.fixedSize())
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.maskImage = Self.roundedMask(radius: 18)
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        var size = hosting.fittingSize
        if size.width < 10 || size.height < 10 {
            size = hosting.intrinsicContentSize
        }
        guard size.width >= 10, size.height >= 10 else {
            Log.write("hud: refusing to show an empty panel")
            return
        }

        panel.contentView = effect
        let screen = Self.targetScreen()
        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + max(56, visible.height * 0.06)
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        if isVisible {
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
        isVisible = true
        Log.write("hud shown: \(style) \(Int(size.width))x\(Int(size.height))")
    }

    func hide() {
        guard isVisible, let panel else { return }
        isVisible = false
        Log.write("hud hidden")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            guard let self, let panel, !self.isVisible else { return }
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }

    private func makePanel() -> HUDWindow {
        HUDWindow()
    }

    private static func targetScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private final class HUDWindow: NSPanel {
        init() {
            super.init(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            isFloatingPanel = true
            becomesKeyOnlyIfNeeded = true
            level = .floating
            backgroundColor = .clear
            isOpaque = false
            hasShadow = true
            ignoresMouseEvents = true
            hidesOnDeactivate = false
            animationBehavior = .none
            collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        }

        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
}
