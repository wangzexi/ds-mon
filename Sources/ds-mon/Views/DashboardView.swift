import SwiftUI

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
                            Divider().padding(.horizontal, 16)
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
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "person.circle").font(.system(size: 32)).foregroundColor(.secondary)
            Text("未登录").font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
            Text("登录后可查看 DeepSeek API 用量").font(.system(size: 10)).foregroundColor(.secondary)
            Button("登录 DeepSeek") { vm.login() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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
        HStack(spacing: 4) {
            Text("今日消费 ¥\(String(format: "%.1f", vm.todayCost))")
            Spacer()
            Text("余额 \(vm.balanceBadgeText)")
        }
        .font(.system(size: 9)).foregroundColor(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }
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
