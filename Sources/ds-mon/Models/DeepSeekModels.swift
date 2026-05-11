import Foundation

struct ModelUsage: Codable, Identifiable {
    let model: String
    let usage: [UsageEntry]

    var id: String { model }

    var totalTokens: Int {
        usage.filter { $0.type != "REQUEST" }.reduce(0) { $0 + (Int($1.amount) ?? 0) }
    }

    var cacheHitTokens: Int { Int(usage.first { $0.type == "PROMPT_CACHE_HIT_TOKEN" }?.amount ?? "0") ?? 0 }
    var cacheMissTokens: Int { Int(usage.first { $0.type == "PROMPT_CACHE_MISS_TOKEN" }?.amount ?? "0") ?? 0 }
    var responseTokens: Int { Int(usage.first { $0.type == "RESPONSE_TOKEN" }?.amount ?? "0") ?? 0 }

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
