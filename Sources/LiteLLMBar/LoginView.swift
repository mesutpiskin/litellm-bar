import SwiftUI

struct LoginView: View {
    @EnvironmentObject var store: UsageStore
    @State private var baseURL = ""
    @State private var mode: AuthMode = .apiKey
    @State private var apiKey = ""
    @State private var username = ""
    @State private var password = ""
    @State private var rememberPassword = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.33percent").font(.title2)
                VStack(alignment: .leading) {
                    Text("LiteLLM Bar").font(.headline)
                    Text("Model ve token kullanımınızı görün").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.isConfigured {
                    Button("Vazgeç") { store.screen = .dashboard }.buttonStyle(.borderless)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Sunucu adresi").font(.caption).foregroundStyle(.secondary)
                TextField("https://litellm.sirket.com", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            Picker("", selection: $mode) {
                ForEach(AuthMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == .apiKey {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sanal anahtar (sk-…)").font(.caption).foregroundStyle(.secondary)
                    SecureField("sk-...", text: $apiKey).textFieldStyle(.roundedBorder)
                    Text("LiteLLM arayüzünde \"Virtual Keys\" sayfasından oluşturduğunuz anahtar.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Kullanıcı adı / e-posta", text: $username).textFieldStyle(.roundedBorder)
                    SecureField("Şifre", text: $password).textFieldStyle(.roundedBorder)
                    Toggle("Şifreyi Anahtar Zinciri'nde sakla (oturum yenileme için)", isOn: $rememberPassword)
                        .font(.caption)
                    Text("LiteLLM UI kullanıcı adı/şifresi. SSO kullanılıyorsa API anahtarı ile giriş yapın.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Toggle("Self-signed / kurumsal sertifikalara güven", isOn: $store.allowInsecureTLS)
                .font(.caption)

            if let err = store.errorMessage {
                Text(err).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Çık") { NSApp.terminate(nil) }.buttonStyle(.borderless)
                Spacer()
                if store.isLoading { ProgressView().controlSize(.small) }
                Button("Giriş Yap") { Task { await submit() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit || store.isLoading)
            }
        }
        .padding(16)
        .onAppear {
            baseURL = store.baseURLString
            mode = store.authMode
            username = store.username
        }
    }

    private var canSubmit: Bool {
        guard !baseURL.isEmpty else { return false }
        return mode == .apiKey ? !apiKey.isEmpty : (!username.isEmpty && !password.isEmpty)
    }

    private func submit() async {
        if mode == .apiKey {
            _ = await store.loginWithAPIKey(baseURL: baseURL, apiKey: apiKey)
        } else {
            _ = await store.loginWithPassword(baseURL: baseURL, username: username, password: password,
                                              remember: rememberPassword)
        }
    }
}
