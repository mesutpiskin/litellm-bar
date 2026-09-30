import SwiftUI

@main
struct LiteLLMBarApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environmentObject(store)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: store.errorMessage != nil && store.isConfigured
                  ? "exclamationmark.triangle"
                  : "gauge.with.dots.needle.33percent")
            if let text = store.menuBarText {
                Text(text).monospacedDigit()
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        Group {
            switch store.screen {
            case .login: LoginView()
            case .settings: SettingsView()
            case .dashboard: DashboardView()
            }
        }
        .frame(width: 400)
    }
}
