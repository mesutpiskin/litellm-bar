import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: UsageStore
    @State private var chartMetric: ChartMetric = .spend
    @State private var showAllModels = false
    @State private var showAvailableModels = false

    enum ChartMetric: String, CaseIterable, Identifiable {
        case spend = "Harcama", tokens = "Token", requests = "İstek"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let err = store.errorMessage {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    budgetCard
                    controls
                    statsGrid
                    if store.activityUnsupported {
                        Text("Bu LiteLLM sürümü /user/daily/activity uç noktasını desteklemiyor; günlük ve model bazlı kırılım gösterilemiyor.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        chart
                        modelsSection
                    }
                    keysSection
                    availableModelsSection
                }
                .padding(14)
            }
            .frame(maxHeight: 560)
            Divider()
            footer
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.33percent").font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.keyInfo?.keyAlias ?? store.userInfo?.userInfo?.userEmail ?? "LiteLLM")
                    .font(.headline).lineLimit(1)
                Text(store.host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if store.isLoading { ProgressView().controlSize(.small) }
            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Yenile")
                .keyboardShortcut("r")
            Button { store.screen = .settings } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).help("Ayarlar")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @ViewBuilder private var budgetCard: some View {
        let spend = store.userInfo?.userInfo?.spend ?? store.keyInfo?.spend ?? 0
        let maxBudget = store.keyInfo?.maxBudget ?? store.userInfo?.userInfo?.maxBudget
        let reset = store.keyInfo?.budgetResetAt ?? store.userInfo?.userInfo?.budgetResetAt
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Toplam harcama").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Fmt.money(spend)).font(.title2.weight(.semibold)).monospacedDigit()
                if let maxBudget {
                    Text("/ \(Fmt.money(maxBudget))").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if let maxBudget, maxBudget > 0 {
                let ratio = min(spend / maxBudget, 1)
                ProgressView(value: ratio)
                    .tint(ratio > 0.9 ? .red : ratio > 0.7 ? .orange : .accentColor)
            }
            HStack {
                if let reset = Fmt.date(reset) { Text("Sıfırlanma: \(reset)") }
                Spacer()
                if let rpm = store.keyInfo?.rpmLimit { Text("RPM \(rpm)") }
                if let tpm = store.keyInfo?.tpmLimit { Text("TPM \(Fmt.tokens(tpm))") }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
    }

    private var controls: some View {
        HStack {
            Picker("", selection: Binding(get: { store.range }, set: { store.range = $0 })) {
                ForEach(UsageRange.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            Picker("", selection: Binding(get: { store.scope }, set: { store.scope = $0 })) {
                ForEach(UsageScope.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden().frame(width: 110)
            .help("Kullanıcı: tüm anahtarlarınızın kullanımı · Bu anahtar: yalnızca giriş yaptığınız anahtar")
        }
    }

    private var statsGrid: some View {
        let t = store.totals
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            StatTile(title: "Harcama", value: Fmt.money(t.spend), icon: "dollarsign.circle")
            StatTile(title: "Toplam token", value: Fmt.tokens(t.totalTokens), icon: "text.word.spacing")
            StatTile(title: "Girdi / Çıktı", value: "\(Fmt.tokens(t.promptTokens)) / \(Fmt.tokens(t.completionTokens))",
                     icon: "arrow.left.arrow.right")
            StatTile(title: "İstek", value: Fmt.number(t.apiRequests),
                     subtitle: t.failedRequests > 0 ? "\(Fmt.number(t.failedRequests)) başarısız" : nil,
                     icon: "paperplane")
        }
    }

    @ViewBuilder private var chart: some View {
        if store.days.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Günlük").font(.subheadline.weight(.semibold))
                    Spacer()
                    Picker("", selection: $chartMetric) {
                        ForEach(ChartMetric.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                }
                Chart(store.days) { day in
                    BarMark(x: .value("Gün", day.date, unit: .day), y: .value(chartMetric.rawValue, value(day.metrics)))
                        .foregroundStyle(Color.accentColor.gradient)
                }
                .chartYAxis {
                    AxisMarks { v in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = v.as(Double.self) { Text(axisLabel(d)).font(.caption2) }
                        }
                    }
                }
                .frame(height: 120)
            }
        }
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Modeller").font(.subheadline.weight(.semibold))
            if store.modelUsage.isEmpty {
                Text("Bu aralıkta kullanım yok.").font(.caption).foregroundStyle(.secondary)
            } else {
                let maxSpend = max(store.modelUsage.map(\.metrics.spend).max() ?? 0, 0.000001)
                let maxTokens = max(store.modelUsage.map(\.metrics.totalTokens).max() ?? 0, 1)
                let list = showAllModels ? store.modelUsage : Array(store.modelUsage.prefix(6))
                ForEach(list) { m in
                    let ratio = maxSpend > 0.000001 ? m.metrics.spend / maxSpend
                        : Double(m.metrics.totalTokens) / Double(maxTokens)
                    ModelRow(usage: m, ratio: ratio)
                }
                if store.modelUsage.count > 6 {
                    Button(showAllModels ? "Daha az göster" : "Tümünü göster (\(store.modelUsage.count))") {
                        showAllModels.toggle()
                    }
                    .buttonStyle(.borderless).font(.caption)
                }
            }
        }
    }

    @ViewBuilder private var keysSection: some View {
        if let keys = store.userInfo?.keys, keys.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Anahtarlarım").font(.subheadline.weight(.semibold))
                ForEach(keys.sorted { ($0.spend ?? 0) > ($1.spend ?? 0) }) { k in
                    HStack {
                        Image(systemName: "key").foregroundStyle(.secondary)
                        Text(k.displayName).lineLimit(1)
                        Spacer()
                        Text(Fmt.money(k.spend ?? 0)).monospacedDigit()
                        if let mb = k.maxBudget { Text("/ \(Fmt.money(mb))").foregroundStyle(.secondary) }
                    }
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder private var availableModelsSection: some View {
        if !store.availableModels.isEmpty {
            DisclosureGroup(isExpanded: $showAvailableModels) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(store.availableModels, id: \.self) { name in
                        Text(name).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            } label: {
                Text("Erişilebilir modeller (\(store.availableModels.count))").font(.subheadline.weight(.semibold))
            }
        }
    }

    private var footer: some View {
        HStack {
            if let d = store.lastUpdated {
                Text("Güncellendi: \(d.formatted(date: .omitted, time: .shortened))")
            }
            Spacer()
            Button("Çık") { NSApp.terminate(nil) }.buttonStyle(.borderless).keyboardShortcut("q")
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: Helpers

    private func value(_ m: Metrics) -> Double {
        switch chartMetric {
        case .spend: return m.spend
        case .tokens: return Double(m.totalTokens)
        case .requests: return Double(m.apiRequests)
        }
    }

    private func axisLabel(_ d: Double) -> String {
        switch chartMetric {
        case .spend: return Fmt.money(d)
        case .tokens, .requests: return Fmt.tokens(Int(d))
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
    }
}

struct ModelRow: View {
    let usage: ModelUsage
    let ratio: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(usage.name).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(Fmt.money(usage.metrics.spend)).font(.caption).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Color.accentColor).frame(width: max(2, geo.size.width * ratio))
                }
            }
            .frame(height: 4)
            HStack {
                Text("\(Fmt.tokens(usage.metrics.totalTokens)) token")
                Text("·")
                Text("\(Fmt.number(usage.metrics.apiRequests)) istek")
                Spacer()
                Text("in \(Fmt.tokens(usage.metrics.promptTokens)) / out \(Fmt.tokens(usage.metrics.completionTokens))")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
