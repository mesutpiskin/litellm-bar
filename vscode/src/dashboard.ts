import * as crypto from 'crypto';
import * as vscode from 'vscode';
import type { Range, Scope, UsageState } from './extension';

export interface DashboardHost {
  state: UsageState;
  refresh(): Promise<void>;
  setRange(range: Range): Promise<void>;
  setScope(scope: Scope): Promise<void>;
  login(): Promise<void>;
  logout(): Promise<void>;
}

export class DashboardPanel {
  private static current?: DashboardPanel;

  static show(extensionUri: vscode.Uri, host: DashboardHost) {
    if (DashboardPanel.current) {
      DashboardPanel.current.panel.reveal();
    } else {
      DashboardPanel.current = new DashboardPanel(extensionUri, host);
    }
    DashboardPanel.update(host.state);
  }

  static update(state: UsageState) {
    void DashboardPanel.current?.panel.webview.postMessage({ type: 'state', state });
  }

  private constructor(extensionUri: vscode.Uri, private readonly host: DashboardHost) {
    this.panel = vscode.window.createWebviewPanel('litellmUsage', 'LiteLLM Kullanım', vscode.ViewColumn.Active, {
      enableScripts: true,
      retainContextWhenHidden: true,
      localResourceRoots: [extensionUri],
    });
    this.panel.iconPath = vscode.Uri.joinPath(extensionUri, 'media', 'icon.png');
    this.panel.webview.html = html(crypto.randomBytes(16).toString('hex'), this.panel.webview.cspSource);
    this.panel.onDidDispose(() => { DashboardPanel.current = undefined; });
    this.panel.webview.onDidReceiveMessage(msg => {
      switch (msg?.type) {
        case 'ready': DashboardPanel.update(this.host.state); break;
        case 'refresh': void this.host.refresh(); break;
        case 'range': void this.host.setRange(msg.value); break;
        case 'scope': void this.host.setScope(msg.value); break;
        case 'login': void this.host.login(); break;
        case 'logout': void this.host.logout(); break;
      }
    });
  }

  private readonly panel: vscode.WebviewPanel;
}

function html(nonce: string, cspSource: string): string {
  return /* html */ `<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy"
      content="default-src 'none'; img-src ${cspSource} data:; style-src ${cspSource} 'unsafe-inline'; script-src 'nonce-${nonce}';">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  body { font-family: var(--vscode-font-family); font-size: var(--vscode-font-size); color: var(--vscode-foreground);
         padding: 16px 20px; max-width: 980px; }
  h1 { font-size: 1.4em; margin: 0; } h2 { font-size: 1.05em; margin: 22px 0 8px; }
  .muted { color: var(--vscode-descriptionForeground); }
  .row { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
  .spacer { flex: 1; }
  button { background: var(--vscode-button-secondaryBackground); color: var(--vscode-button-secondaryForeground);
           border: none; padding: 4px 10px; border-radius: 3px; cursor: pointer; font: inherit; }
  button:hover { background: var(--vscode-button-secondaryHoverBackground); }
  button.primary { background: var(--vscode-button-background); color: var(--vscode-button-foreground); }
  button.active { background: var(--vscode-button-background); color: var(--vscode-button-foreground); }
  .card { background: var(--vscode-editorWidget-background); border: 1px solid var(--vscode-widget-border, transparent);
          border-radius: 6px; padding: 12px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: 10px; }
  .big { font-size: 1.6em; font-weight: 600; font-variant-numeric: tabular-nums; }
  .error { color: var(--vscode-errorForeground); margin: 10px 0; white-space: pre-wrap; }
  .bar { height: 6px; border-radius: 3px; background: var(--vscode-editorWidget-border, #8884); overflow: hidden; }
  .bar > div { height: 100%; background: var(--vscode-progressBar-background); }
  table { width: 100%; border-collapse: collapse; font-variant-numeric: tabular-nums; }
  th, td { text-align: right; padding: 5px 8px; border-bottom: 1px solid var(--vscode-widget-border, #8883); }
  th:first-child, td:first-child { text-align: left; }
  th { color: var(--vscode-descriptionForeground); font-weight: normal; }
  svg .b { fill: var(--vscode-charts-blue, var(--vscode-progressBar-background)); }
  svg text { fill: var(--vscode-descriptionForeground); font-size: 10px; }
  code { font-family: var(--vscode-editor-font-family); }
  .chips { display: flex; flex-wrap: wrap; gap: 6px; }
  .chips code { background: var(--vscode-textCodeBlock-background); padding: 2px 6px; border-radius: 3px; }
</style>
</head>
<body>
<div id="root" class="muted">Yükleniyor…</div>
<script nonce="${nonce}">
const vscode = acquireVsCodeApi();
let chartMetric = 'spend';
let state;

const money = v => !v ? '$0' : v < 0.01 ? '$' + v.toFixed(4) : v < 100 ? '$' + v.toFixed(2) : '$' + v.toFixed(0);
const tokens = v => v >= 1e9 ? (v/1e9).toFixed(1)+'B' : v >= 1e6 ? (v/1e6).toFixed(1)+'M' : v >= 1e3 ? (v/1e3).toFixed(1)+'K' : String(v);
const num = v => (v ?? 0).toLocaleString('tr-TR');
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const fmtDate = iso => { if (!iso) return ''; const d = new Date(iso); return isNaN(d) ? esc(iso) : d.toLocaleString('tr-TR'); };

window.addEventListener('message', e => { if (e.data?.type === 'state') { state = e.data.state; render(); } });
document.addEventListener('click', e => {
  const t = e.target.closest('[data-action]'); if (!t) return;
  const a = t.dataset.action;
  if (a === 'chart') { chartMetric = t.dataset.value; render(); return; }
  vscode.postMessage({ type: a, value: t.dataset.value && (isNaN(+t.dataset.value) ? t.dataset.value : +t.dataset.value) });
});
vscode.postMessage({ type: 'ready' });

function chart(days) {
  if (days.length < 2) return '';
  const val = m => chartMetric === 'spend' ? m.spend : chartMetric === 'tokens' ? m.total_tokens : m.api_requests;
  const fmt = chartMetric === 'spend' ? money : tokens;
  const W = 900, H = 160, pad = 40, max = Math.max(...days.map(d => val(d.metrics)), 1e-9);
  const bw = (W - pad) / days.length;
  const bars = days.map((d, i) => {
    const h = (val(d.metrics) / max) * (H - 30);
    const x = pad + i * bw;
    const label = days.length <= 31 || i % Math.ceil(days.length / 30) === 0
      ? '<text x="' + (x + bw/2) + '" y="' + (H - 4) + '" text-anchor="middle">' + d.date.slice(5) + '</text>' : '';
    return '<rect class="b" x="' + (x + 1) + '" y="' + (H - 18 - h) + '" width="' + Math.max(1, bw - 2) + '" height="' + h + '" rx="2">'
      + '<title>' + d.date + ': ' + fmt(val(d.metrics)) + '</title></rect>' + label;
  }).join('');
  const axis = '<text x="0" y="12">' + fmt(max) + '</text><text x="0" y="' + (H - 18) + '">0</text>';
  const btn = (k, l) => '<button data-action="chart" data-value="' + k + '" class="' + (chartMetric === k ? 'active' : '') + '">' + l + '</button>';
  return '<h2 class="row">Günlük <span class="spacer"></span>' + btn('spend','Harcama') + btn('tokens','Token') + btn('requests','İstek') + '</h2>'
    + '<div class="card"><svg viewBox="0 0 ' + W + ' ' + H + '" width="100%">' + axis + bars + '</svg></div>';
}

function render() {
  const root = document.getElementById('root');
  const s = state;
  if (!s.configured) {
    root.innerHTML = '<h1>LiteLLM Kullanım</h1><p class="muted">Model ve token kullanımınızı görmek için giriş yapın.</p>'
      + '<button class="primary" data-action="login">Giriş Yap</button>';
    root.classList.remove('muted');
    return;
  }
  root.classList.remove('muted');
  const ui = s.userInfo?.user_info, ki = s.keyInfo ?? {};
  const spend = ui?.spend ?? ki.spend ?? 0;
  const budget = ki.max_budget ?? ui?.max_budget;
  const reset = ki.budget_reset_at ?? ui?.budget_reset_at;
  const t = s.totals;
  const rangeBtn = (v, l) => '<button data-action="range" data-value="' + v + '" class="' + (s.range === v ? 'active' : '') + '">' + l + '</button>';
  const scopeBtn = (v, l) => '<button data-action="scope" data-value="' + v + '" class="' + (s.scope === v ? 'active' : '') + '">' + l + '</button>';

  let h = '<div class="row"><h1>' + esc(ki.key_alias || ui?.user_email || 'LiteLLM') + '</h1><span class="muted">' + esc(s.host) + '</span>'
    + '<span class="spacer"></span>' + (s.loading ? '<span class="muted">Yenileniyor…</span>' : '')
    + '<button data-action="refresh">Yenile</button><button data-action="login">Hesabı değiştir</button><button data-action="logout">Çıkış</button></div>';
  if (s.error) h += '<div class="error">⚠ ' + esc(s.error) + '</div>';

  h += '<h2>Bütçe</h2><div class="card"><div class="row"><span class="big">' + money(spend) + '</span>'
    + (budget ? '<span class="muted">/ ' + money(budget) + '</span>' : '<span class="muted">bütçe limiti yok</span>')
    + '<span class="spacer"></span>'
    + (ki.rpm_limit ? '<span class="muted">RPM ' + num(ki.rpm_limit) + '</span>' : '')
    + (ki.tpm_limit ? '<span class="muted">TPM ' + tokens(ki.tpm_limit) + '</span>' : '') + '</div>';
  if (budget) h += '<div class="bar" style="margin-top:8px"><div style="width:' + Math.min(100, spend / budget * 100).toFixed(1) + '%"></div></div>';
  if (reset) h += '<div class="muted" style="margin-top:6px">Sıfırlanma: ' + fmtDate(reset) + '</div>';
  h += '</div>';

  h += '<h2 class="row">Kullanım <span class="spacer"></span>' + rangeBtn(1,'Bugün') + rangeBtn(7,'7 gün') + rangeBtn(30,'30 gün') + rangeBtn(90,'90 gün')
    + '<span style="width:12px"></span>' + scopeBtn('user','Kullanıcı') + scopeBtn('key','Bu anahtar') + '</h2>';
  h += '<div class="grid">'
    + '<div class="card"><div class="muted">Harcama</div><div class="big">' + money(t.spend) + '</div></div>'
    + '<div class="card"><div class="muted">Toplam token</div><div class="big">' + tokens(t.total_tokens) + '</div></div>'
    + '<div class="card"><div class="muted">Girdi / Çıktı</div><div class="big">' + tokens(t.prompt_tokens) + ' / ' + tokens(t.completion_tokens) + '</div></div>'
    + '<div class="card"><div class="muted">İstek</div><div class="big">' + num(t.api_requests) + '</div>'
    + (t.failed_requests ? '<div class="error" style="margin:0">' + num(t.failed_requests) + ' başarısız</div>' : '') + '</div></div>';

  if (s.activityUnsupported) {
    h += '<p class="muted">Bu LiteLLM sürümü /user/daily/activity uç noktasını desteklemiyor; günlük ve model bazlı kırılım gösterilemiyor.</p>';
  } else {
    h += chart(s.days);
    h += '<h2>Modeller</h2>';
    if (!s.modelUsage.length) {
      h += '<p class="muted">Bu aralıkta kullanım yok.</p>';
    } else {
      const maxSpend = Math.max(...s.modelUsage.map(m => m.metrics.spend), 1e-9);
      h += '<table><tr><th>Model</th><th>Harcama</th><th>Token</th><th>Girdi</th><th>Çıktı</th><th>İstek</th><th style="width:22%"></th></tr>'
        + s.modelUsage.map(m => '<tr><td><code>' + esc(m.name) + '</code></td><td>' + money(m.metrics.spend) + '</td><td>' + tokens(m.metrics.total_tokens)
          + '</td><td>' + tokens(m.metrics.prompt_tokens) + '</td><td>' + tokens(m.metrics.completion_tokens) + '</td><td>' + num(m.metrics.api_requests)
          + '</td><td><div class="bar"><div style="width:' + (m.metrics.spend / maxSpend * 100).toFixed(1) + '%"></div></div></td></tr>').join('')
        + '</table>';
    }
  }

  const keys = s.userInfo?.keys ?? [];
  if (keys.length > 1) {
    h += '<h2>Anahtarlarım</h2><table><tr><th>Anahtar</th><th>Harcama</th><th>Bütçe</th></tr>'
      + [...keys].sort((a, b) => (b.spend ?? 0) - (a.spend ?? 0)).map(k => '<tr><td>' + esc(k.key_alias || k.key_name || 'İsimsiz')
        + '</td><td>' + money(k.spend ?? 0) + '</td><td>' + (k.max_budget ? money(k.max_budget) : '—') + '</td></tr>').join('') + '</table>';
  }
  if (s.models.length) {
    h += '<h2>Erişilebilir modeller (' + s.models.length + ')</h2><div class="chips">' + s.models.map(m => '<code>' + esc(m) + '</code>').join('') + '</div>';
  }
  if (s.lastUpdated) h += '<p class="muted" style="margin-top:20px">Son güncelleme: ' + fmtDate(s.lastUpdated) + '</p>';
  root.innerHTML = h;
}
</script>
</body>
</html>`;
}
