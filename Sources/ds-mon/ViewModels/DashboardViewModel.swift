import Foundation
import Observation

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
    var monthlyTokens: Int = 0
    var platformUsage: [ModelUsage] = []
    var isLoggedIn = false
    var onMenuBarNeedsUpdate: (() -> Void)?

    private let apiClient = PlatformAPIClient()
    private let authService = PlatformAuthService()
    private var refreshTask: Task<Void, Never>?

    var balanceBadgeText: String {
        return formatBalance(balance, currency: balanceCurrency)
    }

    var totalTokensText: String {
        if monthlyTokens >= 1_000_000 { return String(format: "%.1fM", Double(monthlyTokens) / 1_000_000) }
        if monthlyTokens >= 1_000 { return String(format: "%.1fK", Double(monthlyTokens) / 1_000) }
        return "\(monthlyTokens)"
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
                isLoggedIn = true
                isLoading = false
                await refreshAll()
                startAutoRefresh()
            }
        }
    }

    func logout() {
        PlatformAuthService.logout()
        isLoggedIn = false
        stopAutoRefresh()
        balance = 0; monthlyTokens = 0; monthlyCost = 0; todayCost = 0
        platformUsage = []
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
            platformUsage = result.models
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
