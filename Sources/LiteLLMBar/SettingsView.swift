import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { store.screen = .dashboard } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text("Ayarlar").font(.headline)
                Spacer()
            }

            GroupBox("Hesap") {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Sunucu", value: store.host)
                    LabeledContent("Giriş türü", value: store.authMode.label)
                    if store.authMode == .password {
                        LabeledContent("Kullanıcı", value: store.username)
                    }
                    HStack {
                        Button("Hesabı değiştir") { store.screen = .login }
                        Spacer()
                        Button("Çıkış yap", role: .destructive) { store.logout() }
                    }
                }
                .padding(4)
            }

            GroupBox("Görünüm") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Menü çubuğunda", selection: Binding(
                        get: { store.menuBarDisplay }, set: { store.menuBarDisplay = $0 })) {
                        ForEach(MenuBarDisplay.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Yenileme aralığı", selection: $store.refreshMinutes) {
                        ForEach([1, 5, 15, 30, 60], id: \.self) { Text("\($0) dk").tag($0) }
                    }
                    Toggle("Oturum açılışında başlat", isOn: Binding(
                        get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 }))
                    Toggle("Self-signed / kurumsal sertifikalara güven", isOn: $store.allowInsecureTLS)
                }
                .padding(4)
            }

            if let err = store.errorMessage {
                Text(err).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Sürüm \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Link("GitHub", destination: URL(string: "https://github.com/mesutpiskin/litellm-bar")!)
                    .font(.caption)
            }
        }
        .padding(16)
    }
}
