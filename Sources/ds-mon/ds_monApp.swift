import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let viewModel = DashboardViewModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusView = StatusBarItemView()
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        viewModel.onMenuBarNeedsUpdate = { [weak self] in
            self?.updateStatusItem()
        }

        setupPopover()
        setupStatusItem()
        observeAppearance()
        updateStatusItem()

        Task { await viewModel.onAppear() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.onDisappear()
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.delegate = self
        let hosting = NSHostingController(rootView: DashboardView().environment(viewModel))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "退出 DeepSeek Monitor", action: #selector(quitApp), keyEquivalent: "q"))
        statusView.onClick = { [weak self] in self?.togglePopover() }
        statusView.menu = menu
        button.addSubview(statusView)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    private func observeAppearance() {
        NotificationCenter.default.addObserver(
            forName: .menuBarAppearanceDidChange, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.updateStatusItem() } }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(button)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            Task { await viewModel.refreshAll() }
        }
    }

    private func updateStatusItem() {
        guard statusItem.button != nil else { return }
        let text = viewModel.isLoggedIn ? viewModel.totalTokensText : "--"
        statusView.configuration = StatusBarItemView.Configuration(
            text: text,
            image: Self.whaleImage()
        )
        statusItem.length = statusView.fittingWidth
        statusView.frame.size = NSSize(width: statusView.fittingWidth, height: NSStatusBar.system.thickness)
    }

    private static func whaleImage() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "deepseek-whale-official", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = false
        return image
    }
}

extension Notification.Name {
    static let menuBarAppearanceDidChange = Notification.Name("menuBarAppearanceDidChange")
}

private final class StatusBarItemView: NSView {
    struct Configuration {
        var text: String = "--"
        var image: NSImage?
    }

    var onClick: (() -> Void)?
    var configuration = Configuration() {
        didSet { needsDisplay = true }
    }

    var fittingWidth: CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let textWidth = configuration.text.isEmpty ? 0 : (configuration.text as NSString).size(withAttributes: [.font: font]).width
        return max(24, ceil(8 + 14 + 3 + textWidth + 8))
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 56, height: NSStatusBar.system.thickness))
        toolTip = "DeepSeek 用量监控"
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color: NSColor = .white
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let textSize = (configuration.text as NSString).size(withAttributes: [.font: font])
        let contentWidth = 14 + 3 + textSize.width
        var x = floor((bounds.width - contentWidth) / 2)
        let centerY = bounds.midY

        if let image = configuration.image {
            let iconRect = NSRect(x: x, y: floor(centerY - 7), width: 14, height: 14)
            Self.tintedImage(image, color: color).draw(in: iconRect)
            x += 14 + 3
        }

        let textRect = NSRect(x: x, y: floor(centerY - textSize.height / 2), width: textSize.width, height: textSize.height)
        (configuration.text as NSString).draw(in: textRect, withAttributes: [.font: font, .foregroundColor: color])
    }

    private static func tintedImage(_ image: NSImage, color: NSColor) -> NSImage {
        let tinted = NSImage(size: image.size)
        tinted.lockFocus()
        let rect = NSRect(origin: .zero, size: image.size)
        color.setFill()
        rect.fill()
        image.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }
}

@main
struct ds_monApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
