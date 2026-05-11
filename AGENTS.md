# ds-mon

macOS 菜单栏工具，显示 DeepSeek API 平台用量。

## Build & Run

- Build: `swift build`
- Run: `swift run ds-mon`
- No third-party dependencies

## Architecture

```
Sources/ds-mon/
├── Views/           # SwiftUI (DashboardView, SettingsView)
├── ViewModels/      # DashboardViewModel (Observation)
├── Services/        # PlatformAPIClient, PlatformAuthService (WKWebView login)
├── Models/          # ModelUsage, UsageEntry
├── Extensions/      # Color theme
└── Resources/       # Whale icon assets
```

- Token stored in `UserDefaults.standard` (key: `"token"`)
- Login via WKWebView at `platform.deepseek.com/login`
- APIs: `get_user_summary`, `usage/amount`, `usage/cost`
- Auto-refresh every 60s, instant refresh on popover open

## Platform

- macOS 14+, Swift 6.0, SwiftUI
