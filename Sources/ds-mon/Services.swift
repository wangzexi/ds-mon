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
import Foundation

actor PlatformAPIClient {
    private let session = URLSession.shared

    private var token: String? { PlatformAuthService.token }

    func fetchAllData() async throws -> (balance: Double, currency: String, monthlyTokens: Int, monthlyCost: Double, todayCost: Double, todayTokens: Int, monthlyModels: [ModelUsage], todayModels: [ModelUsage]) {
        let now = Date()
        let cal = Calendar.current
        let month = cal.component(.month, from: now)
        let year = cal.component(.year, from: now)
        let today = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: now)
        }()

        let summary = try await getJSON(path: "/api/v0/users/get_user_summary")
        let amount = try await getJSON(path: "/api/v0/usage/amount", query: ["month": "\(month)", "year": "\(year)"])
        let cost = try await getJSON(path: "/api/v0/usage/cost", query: ["month": "\(month)", "year": "\(year)"])

        guard let summaryData = summary["data"] as? [String: Any],
              let bizData = summaryData["biz_data"] as? [String: Any] else {
            throw APIError.badResponse("summary")
        }
        let wallets = (bizData["normal_wallets"] as? [[String: Any]]) ?? []
        let costs = (bizData["monthly_costs"] as? [[String: Any]]) ?? []

        let balance = Double(wallets.first?["balance"] as? String ?? "0") ?? 0
        let currency = wallets.first?["currency"] as? String ?? "CNY"
        let monthlyTokens = Int(bizData["monthly_token_usage"] as? String ?? "0") ?? 0
        let monthlyCost = Double(costs.first?["amount"] as? String ?? "0") ?? 0

        let todayModels = parseTodayModels(from: amount, today: today)
        let monthlyModels = parseMonthlyModels(from: amount)
        let todayCost = parseTodayCost(from: cost, today: today)
        let todayTokens = parseTodayTokens(from: amount, today: today)

        return (balance, currency, monthlyTokens, monthlyCost, todayCost, todayTokens, monthlyModels, todayModels)
    }

    private func getJSON(path: String, query: [String: String] = [:]) async throws -> [String: Any] {
        guard let token else { throw APIError.notLoggedIn }
        var components = URLComponents(string: "https://platform.deepseek.com\(path)")!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: components.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.network }
        if http.statusCode == 401 { throw APIError.unauthorized }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["code"] as? Int) == 0 else {
            throw APIError.badResponse(path)
        }
        return json
    }

    private func parseTodayModels(from json: [String: Any], today: String) -> [ModelUsage] {
        guard let data = json["data"] as? [String: Any],
              let bizData = data["biz_data"] as? [String: Any],
              let days = bizData["days"] as? [[String: Any]],
              let todayData = days.first(where: { ($0["date"] as? String) == today }),
              let models = todayData["data"] as? [[String: Any]] else { return [] }
        return models.compactMap { m in
            guard let model = m["model"] as? String,
                  let usage = m["usage"] as? [[String: Any]] else { return nil }
            return ModelUsage(model: model, usage: usage.map { u in
                UsageEntry(type: u["type"] as? String ?? "", amount: u["amount"] as? String ?? "0")
            })
        }
        .sorted { $0.totalTokens > $1.totalTokens }
    }

    private func parseMonthlyModels(from json: [String: Any]) -> [ModelUsage] {
        guard let data = json["data"] as? [String: Any],
              let bizData = data["biz_data"] as? [String: Any],
              let total = bizData["total"] as? [[String: Any]] else { return [] }
        return total.compactMap { m in
            guard let model = m["model"] as? String,
                  let usage = m["usage"] as? [[String: Any]] else { return nil }
            return ModelUsage(model: model, usage: usage.map { u in
                UsageEntry(type: u["type"] as? String ?? "", amount: u["amount"] as? String ?? "0")
            })
        }
        .sorted { $0.totalTokens > $1.totalTokens }
    }

    private func parseTodayTokens(from json: [String: Any], today: String) -> Int {
        guard let data = json["data"] as? [String: Any],
              let bizData = data["biz_data"] as? [String: Any],
              let days = bizData["days"] as? [[String: Any]] else { return 0 }
        for day in days {
            guard (day["date"] as? String) == today else { continue }
            guard let models = day["data"] as? [[String: Any]] else { continue }
            var total = 0
            for model in models {
                guard let usage = model["usage"] as? [[String: Any]] else { continue }
                for entry in usage {
                    guard (entry["type"] as? String) != "REQUEST" else { continue }
                    total += Int(Double(entry["amount"] as? String ?? "0") ?? 0)
                }
            }
            return total
        }
        return 0
    }

    private func parseTodayCost(from json: [String: Any], today: String) -> Double {
        guard let data = json["data"] as? [String: Any],
              let bizData = data["biz_data"] as? [[String: Any]],
              let days = bizData.first?["days"] as? [[String: Any]] else { return 0 }
        var total = 0.0
        for day in days {
            guard (day["date"] as? String) == today else { continue }
            guard let models = day["data"] as? [[String: Any]] else { continue }
            for model in models {
                guard let usage = model["usage"] as? [[String: Any]] else { continue }
                for entry in usage {
                    guard (entry["type"] as? String) != "REQUEST" else { continue }
                    total += Double(entry["amount"] as? String ?? "0") ?? 0
                }
            }
        }
        return total
    }
}

enum APIError: Error, LocalizedError {
    case notLoggedIn, unauthorized, network, badResponse(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: "未登录"
        case .unauthorized: "登录已过期，请重新登录"
        case .network: "网络错误"
        case .badResponse(let s): "数据错误: \(s)"
        }
    }
}
