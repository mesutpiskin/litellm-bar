import * as vscode from 'vscode';
import { addMetrics, ApiError, DailyEntry, emptyMetrics, KeyInfo, LiteLLMClient, Metrics, UserInfoResponse } from './client';
import { DashboardPanel } from './dashboard';

type AuthMode = 'apiKey' | 'password';
export type Range = 1 | 7 | 30 | 90;
export type Scope = 'user' | 'key';

export interface UsageState {
  configured: boolean;
  loading: boolean;
  host: string;
  error?: string;
  lastUpdated?: string;
  range: Range;
  scope: Scope;
  keyInfo?: KeyInfo;
  userInfo?: UserInfoResponse;
  models: string[];
  days: { date: string; metrics: Metrics }[];
  modelUsage: { name: string; metrics: Metrics }[];
  totals: Metrics;
  today: Metrics;
  activityUnsupported: boolean;
}

const SECRET_API_KEY = 'litellm.apiKey';
const SECRET_SESSION_KEY = 'litellm.sessionKey';
const SECRET_PASSWORD = 'litellm.password';

let controller: UsageController | undefined;

export function activate(context: vscode.ExtensionContext) {
  controller = new UsageController(context);
  context.subscriptions.push(
    controller,
    vscode.commands.registerCommand('litellm.showDashboard', () => controller!.showDashboard()),
    vscode.commands.registerCommand('litellm.login', () => controller!.login()),
    vscode.commands.registerCommand('litellm.logout', () => controller!.logout()),
    vscode.commands.registerCommand('litellm.refresh', () => controller!.refresh()),
  );
  void controller.refresh();
}

export function deactivate() {
  controller = undefined;
}

class UsageController implements vscode.Disposable {
  private readonly statusItem: vscode.StatusBarItem;
  private timer?: NodeJS.Timeout;
  private readonly disposables: vscode.Disposable[] = [];
  state: UsageState;

  constructor(private readonly context: vscode.ExtensionContext) {
    this.statusItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
    this.statusItem.command = 'litellm.showDashboard';
    this.statusItem.show();

    this.state = {
      configured: false,
      loading: false,
      host: '',
      range: context.globalState.get<Range>('range', 7),
      scope: context.globalState.get<Scope>('scope', 'user'),
      models: [],
      days: [],
      modelUsage: [],
      totals: emptyMetrics(),
      today: emptyMetrics(),
      activityUnsupported: false,
    };

    this.disposables.push(vscode.workspace.onDidChangeConfiguration(e => {
      if (e.affectsConfiguration('litellm')) {
        this.scheduleTimer();
        void this.refresh();
      }
    }));
    this.scheduleTimer();
    this.render();
  }

  dispose() {
    if (this.timer) { clearInterval(this.timer); }
    this.statusItem.dispose();
    this.disposables.forEach(d => d.dispose());
  }

  private get config() { return vscode.workspace.getConfiguration('litellm'); }
  private get authMode(): AuthMode { return this.context.globalState.get<AuthMode>('authMode', 'apiKey'); }
  private get username(): string { return this.context.globalState.get<string>('username', ''); }

  private async effectiveKey(): Promise<string | undefined> {
    return this.context.secrets.get(this.authMode === 'apiKey' ? SECRET_API_KEY : SECRET_SESSION_KEY);
  }

  private client(key?: string): LiteLLMClient | undefined {
    const base = LiteLLMClient.normalize(this.config.get<string>('baseUrl'));
    return base ? new LiteLLMClient(base, key, this.config.get<boolean>('allowInsecureTLS', false)) : undefined;
  }

  private scheduleTimer() {
    if (this.timer) { clearInterval(this.timer); }
    const minutes = Math.max(1, this.config.get<number>('refreshMinutes', 5));
    this.timer = setInterval(() => void this.refresh(), minutes * 60_000);
  }

  // MARK: Commands

  showDashboard() {
    DashboardPanel.show(this.context.extensionUri, this);
  }

  async setRange(range: Range) {
    this.state.range = range;
    await this.context.globalState.update('range', range);
    await this.refresh();
  }

  async setScope(scope: Scope) {
    this.state.scope = scope;
    await this.context.globalState.update('scope', scope);
    await this.refresh();
  }

  async login() {
    const baseUrl = await vscode.window.showInputBox({
      title: 'LiteLLM proxy URL',
      prompt: 'e.g. https://litellm.example.com',
      value: this.config.get<string>('baseUrl') ?? '',
      ignoreFocusOut: true,
      validateInput: v => LiteLLMClient.normalize(v) ? undefined : 'Invalid URL',
    });
    if (!baseUrl) { return; }
    const base = LiteLLMClient.normalize(baseUrl)!;

    const pick = await vscode.window.showQuickPick([
      { label: '$(key) API Key', description: 'Virtual key (sk-…)', mode: 'apiKey' as AuthMode },
      { label: '$(account) Username / Password', description: 'LiteLLM UI credentials', mode: 'password' as AuthMode },
    ], { title: 'Sign-in method', ignoreFocusOut: true });
    if (!pick) { return; }

    const insecure = this.config.get<boolean>('allowInsecureTLS', false);
    try {
      if (pick.mode === 'apiKey') {
        const key = (await vscode.window.showInputBox({
          title: 'LiteLLM virtual key', prompt: 'sk-...', password: true, ignoreFocusOut: true,
        }))?.trim();
        if (!key) { return; }
        await vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title: 'LiteLLM: verifying key…' },
          () => new LiteLLMClient(base, key, insecure).keyInfo());
        await this.context.secrets.store(SECRET_API_KEY, key);
      } else {
        const username = await vscode.window.showInputBox({
          title: 'Username / email', value: this.username, ignoreFocusOut: true,
        });
        if (!username) { return; }
        const password = await vscode.window.showInputBox({ title: 'Password', password: true, ignoreFocusOut: true });
        if (!password) { return; }
        const session = await vscode.window.withProgress(
          { location: vscode.ProgressLocation.Notification, title: 'LiteLLM: signing in…' },
          () => new LiteLLMClient(base, undefined, insecure).login(username, password));
        const remember = await vscode.window.showQuickPick(['Yes', 'No'], {
          title: 'Store the password in secure storage to renew the session automatically when it expires?',
          ignoreFocusOut: true,
        });
        await this.context.globalState.update('username', username);
        await this.context.secrets.store(SECRET_SESSION_KEY, session.key);
        if (remember === 'Yes') {
          await this.context.secrets.store(SECRET_PASSWORD, password);
        } else {
          await this.context.secrets.delete(SECRET_PASSWORD);
        }
      }
      await this.context.globalState.update('authMode', pick.mode);
      await this.config.update('baseUrl', base.toString().replace(/\/$/, ''), vscode.ConfigurationTarget.Global);
      await this.refresh();
      vscode.window.showInformationMessage('LiteLLM: signed in.');
    } catch (e) {
      vscode.window.showErrorMessage(`LiteLLM: ${(e as Error).message}`);
    }
  }

  async logout() {
    await Promise.all([SECRET_API_KEY, SECRET_SESSION_KEY, SECRET_PASSWORD].map(k => this.context.secrets.delete(k)));
    Object.assign(this.state, {
      configured: false, keyInfo: undefined, userInfo: undefined, models: [], days: [], modelUsage: [],
      totals: emptyMetrics(), today: emptyMetrics(), lastUpdated: undefined, error: undefined,
    });
    this.render();
  }

  // MARK: Refresh

  private async reloginIfPossible(): Promise<boolean> {
    const password = await this.context.secrets.get(SECRET_PASSWORD);
    const client = this.client();
    if (this.authMode !== 'password' || !password || !this.username || !client) { return false; }
    try {
      const session = await client.login(this.username, password);
      await this.context.secrets.store(SECRET_SESSION_KEY, session.key);
      return true;
    } catch {
      return false;
    }
  }

  async refresh(retried = false): Promise<void> {
    const key = await this.effectiveKey();
    const client = this.client(key);
    this.state.host = LiteLLMClient.normalize(this.config.get<string>('baseUrl'))?.host ?? '';
    this.state.configured = !!(key && client);
    if (!key || !client) { this.render(); return; }

    this.state.loading = true;
    this.render();
    try {
      const info = (await client.keyInfo()).info;
      this.state.keyInfo = info;

      const modelsP = client.models().catch(() => this.state.models);
      const userP = info.user_id ? client.userInfo(info.user_id).catch(() => undefined) : Promise.resolve(undefined);

      const [start, end] = dateBounds(this.state.range);
      try {
        const entries = await client.dailyActivity(start, end, this.state.scope === 'key' ? info.token : undefined);
        this.aggregate(entries, end);
        this.state.activityUnsupported = false;
      } catch (e) {
        if (!(e instanceof ApiError && e.status === 404)) { throw e; }
        this.state.activityUnsupported = true;
        this.aggregate([], end);
      }

      this.state.models = await modelsP;
      this.state.userInfo = await userP;
      this.state.lastUpdated = new Date().toISOString();
      this.state.error = undefined;
    } catch (e) {
      if (e instanceof ApiError && e.unauthorized && !retried && await this.reloginIfPossible()) {
        this.state.loading = false;
        return this.refresh(true);
      }
      this.state.error = (e as Error).message;
    } finally {
      this.state.loading = false;
      this.render();
    }
  }

  private aggregate(entries: DailyEntry[], todayStr: string) {
    const byDay = new Map<string, Metrics>();
    const byModel = new Map<string, Metrics>();
    for (const e of entries) {
      byDay.set(e.date, addMetrics(byDay.get(e.date) ?? emptyMetrics(), e.metrics));
      for (const [name, item] of Object.entries(e.breakdown?.models ?? {})) {
        byModel.set(name, addMetrics(byModel.get(name) ?? emptyMetrics(), item.metrics));
      }
    }
    this.state.days = [...byDay].map(([date, metrics]) => ({ date, metrics })).sort((a, b) => a.date.localeCompare(b.date));
    this.state.modelUsage = [...byModel].map(([name, metrics]) => ({ name, metrics }))
      .sort((a, b) => b.metrics.spend - a.metrics.spend || b.metrics.total_tokens - a.metrics.total_tokens);
    this.state.totals = [...byDay.values()].reduce((acc, m) => addMetrics(acc, m), emptyMetrics());
    this.state.today = byDay.get(todayStr) ?? emptyMetrics();
  }

  // MARK: Rendering

  private render() {
    const s = this.state;
    const item = this.statusItem;
    if (!s.configured) {
      item.text = '$(pulse) LiteLLM: Sign in';
      item.tooltip = 'Sign in to see your LiteLLM usage';
      item.command = 'litellm.login';
    } else {
      item.command = 'litellm.showDashboard';
      const icon = s.loading ? '$(sync~spin)' : s.error ? '$(warning)' : '$(pulse)';
      let text = '';
      switch (this.config.get<string>('statusBar', 'todaySpend')) {
        case 'todaySpend': text = money(s.today.spend); break;
        case 'todayTokens': text = tokens(s.today.total_tokens); break;
        case 'totalSpend': text = money(s.userInfo?.user_info?.spend ?? s.keyInfo?.spend ?? 0); break;
      }
      item.text = s.lastUpdated && text ? `${icon} ${text}` : icon;
      const tip = new vscode.MarkdownString(undefined, true);
      tip.appendMarkdown(`**LiteLLM** · ${s.host}\n\n`);
      if (s.error) { tip.appendMarkdown(`$(warning) ${s.error}\n\n`); }
      tip.appendMarkdown(`Today: **${money(s.today.spend)}** · ${tokens(s.today.total_tokens)} tokens · ${s.today.api_requests} requests\n\n`);
      tip.appendMarkdown(`Total spend: **${money(s.userInfo?.user_info?.spend ?? s.keyInfo?.spend ?? 0)}**`);
      const budget = s.keyInfo?.max_budget ?? s.userInfo?.user_info?.max_budget;
      if (budget) { tip.appendMarkdown(` / ${money(budget)}`); }
      tip.appendMarkdown('\n\n_Click to open the dashboard_');
      item.tooltip = tip;
    }
    DashboardPanel.update(s);
  }
}

function dateBounds(range: Range): [string, string] {
  const now = new Date();
  const start = new Date(now.getTime() - (range - 1) * 86_400_000);
  return [start.toISOString().slice(0, 10), now.toISOString().slice(0, 10)];
}

export function money(v: number): string {
  if (!v) { return '$0'; }
  if (v < 0.01) { return `$${v.toFixed(4)}`; }
  if (v < 100) { return `$${v.toFixed(2)}`; }
  return `$${v.toFixed(0)}`;
}

export function tokens(v: number): string {
  if (v >= 1e9) { return `${(v / 1e9).toFixed(1)}B`; }
  if (v >= 1e6) { return `${(v / 1e6).toFixed(1)}M`; }
  if (v >= 1e3) { return `${(v / 1e3).toFixed(1)}K`; }
  return String(v);
}
