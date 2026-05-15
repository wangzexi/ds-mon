import Foundation

enum PlatformAuthService {
    static var token: String? {
        get { UserDefaults.standard.string(forKey: "token") }
        set { UserDefaults.standard.set(newValue, forKey: "token") }
    }

    static var hasToken: Bool { token != nil }

    static func logout() {
        token = nil
    }
}

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

        let todayModels = parseModels(from: todayModelData(from: amount, today: today))
        let monthlyModels = parseMonthlyModels(from: amount)
        let todayCost = parseTodayCost(from: cost, today: today)
        let todayTokens = todayModels.reduce(0) { $0 + $1.totalTokens }

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

    private func todayModelData(from json: [String: Any], today: String) -> [[String: Any]] {
        guard let data = json["data"] as? [String: Any],
              let bizData = data["biz_data"] as? [String: Any],
              let days = bizData["days"] as? [[String: Any]],
              let todayData = days.first(where: { ($0["date"] as? String) == today }),
              let models = todayData["data"] as? [[String: Any]] else { return [] }
        return models
    }

    private func parseMonthlyModels(from json: [String: Any]) -> [ModelUsage] {
        guard let data = json["data"] as? [String: Any],
              let bizData = data["biz_data"] as? [String: Any],
              let total = bizData["total"] as? [[String: Any]] else { return [] }
        return parseModels(from: total)
    }

    private func parseModels(from models: [[String: Any]]) -> [ModelUsage] {
        models.compactMap { m in
            guard let model = m["model"] as? String,
                  let usage = m["usage"] as? [[String: Any]] else { return nil }
            let toks = usage.filter { u in (u["type"] as? String) != "REQUEST" }
                .reduce(0) { $0 + (Int(Double(($1["amount"] as? String) ?? "0") ?? 0)) }
            guard toks > 0 else { return nil }
            return ModelUsage(model: model, usage: usage.map { u in
                UsageEntry(type: u["type"] as? String ?? "", amount: u["amount"] as? String ?? "0")
            })
        }
        .sorted { $0.totalTokens > $1.totalTokens }
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
