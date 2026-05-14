import Foundation

struct ModelUsage: Codable, Identifiable {
    let model: String
    let usage: [UsageEntry]

    var id: String { model }

    var totalTokens: Int {
        usage.filter { $0.type != "REQUEST" }.reduce(0) { $0 + Int(Double($1.amount) ?? 0) }
    }

    var cacheHitTokens: Int { Int(Double(usage.first { $0.type == "PROMPT_CACHE_HIT_TOKEN" }?.amount ?? "0") ?? 0) }
    var cacheMissTokens: Int { Int(Double(usage.first { $0.type == "PROMPT_CACHE_MISS_TOKEN" }?.amount ?? "0") ?? 0) }
    var responseTokens: Int { Int(Double(usage.first { $0.type == "RESPONSE_TOKEN" }?.amount ?? "0") ?? 0) }

    var cacheHitPercent: Double {
        let total = cacheHitTokens + cacheMissTokens
        guard total > 0 else { return 0 }
        return Double(cacheHitTokens) / Double(total) * 100
    }
}

struct UsageEntry: Codable {
    let type: String
    let amount: String
}
import Foundation
import Observation

enum DisplayMode: String, CaseIterable {
    case today = "今日"
    case monthly = "本月"
}

@MainActor
@Observable
final class DashboardViewModel {
    var isLoading = false
    var sectionErrors: [String: String] = [:]
    var lastUpdated: Date?
    var balance: Double = 0
    var balanceCurrency: String = "CNY"
    var monthlyCost: Double = 0
    var todayCost: Double = 0
    var todayTokens: Int = 0
    var monthlyTokens: Int = 0
    var displayMode: DisplayMode = .today {
        didSet { onMenuBarNeedsUpdate?() }
    }
    var todayUsage: [ModelUsage] = []
    var monthlyUsage: [ModelUsage] = []
    var isLoggedIn = false
    var onMenuBarNeedsUpdate: (() -> Void)?

    var platformUsage: [ModelUsage] {
        displayMode == .today ? todayUsage : monthlyUsage
    }

    private let apiClient = PlatformAPIClient()
    private let authService = PlatformAuthService()
    private var refreshTask: Task<Void, Never>?

    var balanceBadgeText: String {
        return formatBalance(balance, currency: balanceCurrency)
    }

    var totalTokensText: String {
        let tokens = displayMode == .today ? todayTokens : monthlyTokens
        if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
        if tokens >= 1_000 { return String(format: "%.1fK", Double(tokens) / 1_000) }
        return "\(tokens)"
    }

    func checkLoginStatus() {
        isLoggedIn = PlatformAuthService.hasToken
    }

    func login() {
        isLoggedIn = false
        isLoading = true
        authService.startLogin { [weak self] token in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLoggedIn = true
                self.isLoading = false
                await self.refreshAll()
                self.startAutoRefresh()
            }
        }
    }

    func logout() {
        PlatformAuthService.logout()
        isLoggedIn = false
        stopAutoRefresh()
        balance = 0; monthlyTokens = 0; monthlyCost = 0; todayCost = 0; todayTokens = 0
        todayUsage = []; monthlyUsage = []
        lastUpdated = nil
        onMenuBarNeedsUpdate?()
    }

    func onAppear() async {
        checkLoginStatus()
        guard isLoggedIn else { return }
        await refreshAll()
        startAutoRefresh()
    }

    func onDisappear() {
        stopAutoRefresh()
    }

    func refreshAll() async {
        isLoading = true
        defer {
            isLoading = false
            onMenuBarNeedsUpdate?()
        }

        do {
            let result = try await apiClient.fetchAllData()
            balance = result.balance
            balanceCurrency = result.currency
            monthlyTokens = result.monthlyTokens
            monthlyCost = result.monthlyCost
            todayCost = result.todayCost
            todayTokens = result.todayTokens
            todayUsage = result.todayModels
            monthlyUsage = result.monthlyModels
            lastUpdated = Date()
            sectionErrors["api"] = nil
        } catch APIError.unauthorized {
            sectionErrors["api"] = "登录已过期，请重新登录"
            PlatformAuthService.logout()
            isLoggedIn = false
        } catch {
            sectionErrors["api"] = error.localizedDescription
        }
    }

    func clearError() {
        sectionErrors["api"] = nil
    }

    func handleLoginSuccess() {
        isLoggedIn = true
        isLoading = false
        Task { await refreshAll(); startAutoRefresh() }
    }

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self.refreshAll()
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func formatBalance(_ value: Double, currency: String?) -> String {
        switch currency?.uppercased() {
        case "USD": return String(format: "$%.1f", value)
        case "CNY": return String(format: "¥%.1f", value)
        default: return String(format: "%.1f", value)
        }
    }
}
import SwiftUI
import WebKit

struct DashboardView: View {
    @Environment(DashboardViewModel.self) private var vm

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if vm.isLoggedIn {
                if let error = vm.sectionErrors["api"] {
                    errorView(error)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !vm.platformUsage.isEmpty {
                            modelListSection
                            footerView
                        } else if vm.isLoading {
                            loadingView
                        } else {
                            Text("等待数据…").font(.system(size: 10)).foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
            } else {
                loginPrompt
            }
        }
        .frame(minWidth: 340)
    }

    // MARK: - Login

    private var loginPrompt: some View {
        LoginWebView { vm.handleLoginSuccess() }
    }

    // MARK: - Error

    private func errorView(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundColor(.yellow)
            Text(msg).font(.system(size: 10)).foregroundColor(.secondary)
            Spacer()
            if msg.contains("重新登录") {
                Button("重新登录") { vm.login() }.buttonStyle(.plain).font(.system(size: 10))
            } else {
                Button("知道了") { vm.clearError() }.buttonStyle(.plain).font(.system(size: 10))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(.yellow.opacity(0.08))
    }

    private var loadingView: some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.7)
            Text("加载中…").font(.system(size: 10)).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Models

    private var modelListSection: some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
            ForEach(vm.platformUsage) { model in
                GridRow {
                    Text(model.model.replacingOccurrences(of: "deepseek-", with: "").lowercased())
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.primary)
                        .gridColumnAlignment(.leading)
                    Text("↑ \(formatToken(model.cacheMissTokens))")
                        .font(.system(size: 8)).foregroundColor(.secondary)
                    Text("↓ \(formatToken(model.responseTokens))")
                        .font(.system(size: 8)).foregroundColor(.secondary)
                    HStack(spacing: 3) {
                        Text("缓存").font(.system(size: 8)).foregroundColor(.secondary)
                        Text(String(format: "%.1f%%", model.cacheHitPercent))
                            .font(.system(size: 8, weight: .medium)).foregroundColor(.secondary)
                    }
                    Text(model.totalTokensFormatted)
                        .font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 6) {
            pill("今日 \(formatCost(vm.todayCost))", isSelected: vm.displayMode == .today)
                .onTapGesture { vm.displayMode = .today }
            pill("本月 \(formatCost(vm.monthlyCost))", isSelected: vm.displayMode == .monthly)
                .onTapGesture { vm.displayMode = .monthly }
            Spacer()
            Text("余额 \(vm.balanceBadgeText)").font(.system(size: 9)).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
    }

    private func pill(_ text: String, isSelected: Bool) -> some View {
        Text(text)
            .font(.system(size: 9, weight: isSelected ? .medium : .regular))
            .foregroundColor(isSelected ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isSelected ? Color.primary.opacity(0.1) : .clear)
            .cornerRadius(6)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() }
                else { NSCursor.pop() }
            }
    }
}

struct LoginWebView: NSViewRepresentable {
    let onLogin: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 380, height: 500), configuration: config)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: URL(string: "https://platform.deepseek.com/login")!))
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onLogin: onLogin) }

    class Coordinator: NSObject, WKNavigationDelegate {
        let onLogin: () -> Void
        weak var webView: WKWebView?
        private var timer: Timer?

        init(onLogin: @escaping () -> Void) { self.onLogin = onLogin }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.checkToken()
            }
        }

        private func checkToken() {
            guard let web = webView else { return }
            web.evaluateJavaScript("localStorage.getItem('userToken')") { [weak self] (result: Any?, error: Error?) in
                guard let self else { return }
                guard let tokenStr = result as? String,
                      let data = tokenStr.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let token = obj["value"] as? String,
                      !token.isEmpty
                else { return }
                Task { @MainActor in
                    PlatformAuthService.token = token
                    self.timer?.invalidate()
                    self.timer = nil
                    self.onLogin()
                }
            }
        }
    }
}

private func formatCost(_ v: Double) -> String {
    String(format: "¥%.1f", v)
}

extension ModelUsage {
    var totalTokensFormatted: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(for: totalTokens) ?? "\(totalTokens)"
    }
}

private func formatToken(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
    return "\(n)"
}
