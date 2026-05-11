import AppKit
import WebKit

@MainActor
final class PlatformAuthService: NSObject {
    private var window: NSWindow?
    private weak var webView: WKWebView?
    private var tokenTimer: Timer?
    private var completion: ((String) -> Void)?

    nonisolated static var token: String? {
        get { UserDefaults.standard.string(forKey: "token") }
        set { UserDefaults.standard.set(newValue, forKey: "token") }
    }

    nonisolated static var hasToken: Bool { token != nil }

    nonisolated static func logout() {
        token = nil
    }

    func startLogin(completion: @escaping (String) -> Void) {
        self.completion = completion
        showWindow()
    }

    private func showWindow() {
        let rect = NSRect(x: 0, y: 0, width: 480, height: 680)
        let win = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        win.title = "登录 DeepSeek"
        win.center()

        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: rect, configuration: config)
        web.navigationDelegate = self
        win.contentView = web
        webView = web
        window = win

        web.load(URLRequest(url: URL(string: "https://platform.deepseek.com/login")!))

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func closeWindow() {
        tokenTimer?.invalidate()
        tokenTimer = nil
        window?.orderOut(nil)
        window = nil
    }

    private func startPolling() {
        tokenTimer?.invalidate()
        tokenTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkToken() }
        }
    }

    private func checkToken() {
        guard let web = webView else { return }
        web.evaluateJavaScript("localStorage.getItem('userToken')") { [weak self] result, error in
            guard let self else { return }
            guard let tokenStr = result as? String,
                  let data = tokenStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = obj["value"] as? String,
                  !token.isEmpty
            else { return }

            Task { @MainActor in
                Self.token = token
                self.closeWindow()
                let cb = self.completion
                self.completion = nil
                cb?(token)
            }
        }
    }
}

extension PlatformAuthService: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        startPolling()
    }
}
