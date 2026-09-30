import * as http from 'http';
import * as https from 'https';

export interface Metrics {
  spend: number;
  prompt_tokens: number;
  completion_tokens: number;
  total_tokens: number;
  api_requests: number;
  successful_requests: number;
  failed_requests: number;
}

export interface KeyInfo {
  token?: string;
  key_alias?: string;
  key_name?: string;
  spend?: number;
  max_budget?: number | null;
  budget_reset_at?: string | null;
  user_id?: string | null;
  team_id?: string | null;
  tpm_limit?: number | null;
  rpm_limit?: number | null;
}

export interface UserKey {
  token?: string;
  key_alias?: string | null;
  key_name?: string | null;
  spend?: number;
  max_budget?: number | null;
}

export interface UserInfoResponse {
  user_id?: string;
  user_info?: {
    user_email?: string | null;
    user_role?: string | null;
    spend?: number;
    max_budget?: number | null;
    budget_reset_at?: string | null;
  } | null;
  keys?: UserKey[];
}

export interface DailyEntry {
  date: string;
  metrics: Partial<Metrics>;
  breakdown?: { models?: Record<string, { metrics: Partial<Metrics> }> };
}

export interface SessionInfo {
  key: string;
  userId?: string;
  userEmail?: string;
}

export class ApiError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
  }
  get unauthorized() { return this.status === 401 || this.status === 403; }
}

interface RawResponse {
  status: number;
  headers: http.IncomingHttpHeaders;
  body: string;
}

export function emptyMetrics(): Metrics {
  return {
    spend: 0, prompt_tokens: 0, completion_tokens: 0, total_tokens: 0,
    api_requests: 0, successful_requests: 0, failed_requests: 0,
  };
}

export function addMetrics(a: Metrics, b: Partial<Metrics>): Metrics {
  const total = b.total_tokens || (b.prompt_tokens ?? 0) + (b.completion_tokens ?? 0);
  return {
    spend: a.spend + (b.spend ?? 0),
    prompt_tokens: a.prompt_tokens + (b.prompt_tokens ?? 0),
    completion_tokens: a.completion_tokens + (b.completion_tokens ?? 0),
    total_tokens: a.total_tokens + total,
    api_requests: a.api_requests + (b.api_requests ?? 0),
    successful_requests: a.successful_requests + (b.successful_requests ?? 0),
    failed_requests: a.failed_requests + (b.failed_requests ?? 0),
  };
}

export class LiteLLMClient {
  constructor(
    private readonly base: URL,
    private readonly apiKey?: string,
    private readonly allowInsecureTLS = false,
  ) {}

  static normalize(raw: string | undefined): URL | undefined {
    let s = (raw ?? '').trim().replace(/\/+$/, '');
    if (s.endsWith('/ui')) { s = s.slice(0, -3); }
    if (!s) { return undefined; }
    if (!/^https?:\/\//i.test(s)) { s = 'https://' + s; }
    try { return new URL(s); } catch { return undefined; }
  }

  keyInfo(): Promise<{ key?: string; info: KeyInfo }> {
    return this.get('key/info');
  }

  userInfo(userId: string): Promise<UserInfoResponse> {
    return this.get('user/info', { user_id: userId });
  }

  async models(): Promise<string[]> {
    const res = await this.get<{ data: { id: string }[] }>('v1/models');
    return res.data.map(m => m.id).sort();
  }

  async dailyActivity(start: string, end: string, apiKeyHash?: string): Promise<DailyEntry[]> {
    const all: DailyEntry[] = [];
    for (let page = 1; page <= 20; page++) {
      const q: Record<string, string> = { start_date: start, end_date: end, page: String(page), page_size: '100' };
      if (apiKeyHash) { q.api_key = apiKeyHash; }
      const res = await this.get<{ results: DailyEntry[]; metadata?: { has_more?: boolean; total_pages?: number } }>(
        'user/daily/activity', q);
      all.push(...res.results);
      const more = res.metadata?.has_more ?? (res.metadata?.total_pages ?? 1) > page;
      if (!more || res.results.length === 0) { break; }
    }
    return all;
  }

  /** Logs in with LiteLLM UI credentials and returns the session key embedded in the JWT cookie. */
  async login(username: string, password: string): Promise<SessionInfo> {
    const form = new URLSearchParams({ username, password }).toString();
    const r1 = await this.request('POST', 'login', undefined, form, { 'Content-Type': 'application/x-www-form-urlencoded' });
    const t1 = extractToken(r1);
    if (t1) { return decodeSession(t1); }
    if (r1.status === 401 || r1.status === 403) { throw new ApiError(r1.status, errorMessage(r1)); }

    const r2 = await this.request('POST', 'v2/login', undefined, JSON.stringify({ username, password }),
      { 'Content-Type': 'application/json' });
    const t2 = extractToken(r2);
    if (t2) { return decodeSession(t2); }
    if (r2.status >= 400) { throw new ApiError(r2.status, errorMessage(r2)); }
    throw new Error('Login succeeded but no session key was returned. If your proxy uses SSO, sign in with an API key instead.');
  }

  private async get<T>(path: string, query?: Record<string, string>): Promise<T> {
    const res = await this.request('GET', path, query);
    if (res.status < 200 || res.status >= 300) { throw new ApiError(res.status, errorMessage(res)); }
    try {
      return JSON.parse(res.body) as T;
    } catch {
      throw new Error(`${path}: response is not valid JSON`);
    }
  }

  private request(method: string, path: string, query?: Record<string, string>, body?: string,
                  extraHeaders: Record<string, string> = {}): Promise<RawResponse> {
    const url = new URL(this.base.pathname.replace(/\/$/, '') + '/' + path, this.base);
    for (const [k, v] of Object.entries(query ?? {})) { url.searchParams.set(k, v); }

    const headers: Record<string, string> = { Accept: 'application/json', ...extraHeaders };
    if (this.apiKey) { headers.Authorization = `Bearer ${this.apiKey}`; }
    if (body !== undefined) { headers['Content-Length'] = String(Buffer.byteLength(body)); }

    const isHttps = url.protocol === 'https:';
    const mod = isHttps ? https : http;
    const options: https.RequestOptions = { method, headers, timeout: 30_000 };
    if (isHttps && this.allowInsecureTLS) { options.rejectUnauthorized = false; }

    // Redirects are intentionally not followed so the login response keeps its Set-Cookie.
    return new Promise((resolve, reject) => {
      const req = mod.request(url, options, res => {
        const chunks: Buffer[] = [];
        res.on('data', c => chunks.push(c));
        res.on('end', () => resolve({
          status: res.statusCode ?? 0,
          headers: res.headers,
          body: Buffer.concat(chunks).toString('utf8'),
        }));
      });
      req.on('timeout', () => req.destroy(new Error('Request timed out')));
      req.on('error', reject);
      if (body !== undefined) { req.write(body); }
      req.end();
    });
  }
}

function extractToken(res: RawResponse): string | undefined {
  for (const c of res.headers['set-cookie'] ?? []) {
    const m = /^token=([^;]+)/.exec(c);
    if (m) { return decodeURIComponent(m[1]); }
  }
  try {
    const json = JSON.parse(res.body);
    for (const k of ['token', 'access_token', 'jwt']) {
      if (typeof json[k] === 'string' && json[k].split('.').length === 3) { return json[k]; }
    }
  } catch { /* not JSON */ }
  return undefined;
}

function decodeSession(jwt: string): SessionInfo {
  const payload = JSON.parse(Buffer.from(jwt.split('.')[1] ?? '', 'base64url').toString('utf8'));
  if (typeof payload.key !== 'string') { throw new Error('Session key not found in login token.'); }
  return { key: payload.key, userId: payload.user_id, userEmail: payload.user_email };
}

function errorMessage(res: RawResponse): string {
  let msg = res.body.slice(0, 300);
  try {
    const j = JSON.parse(res.body);
    msg = j?.error?.message ?? (typeof j?.detail === 'string' ? j.detail : j?.detail?.error) ?? msg;
  } catch { /* keep raw body */ }
  if (res.status === 401 || res.status === 403) {
    return `Unauthorized (${res.status}). Your key or session may be invalid or expired. ${msg}`;
  }
  return `Server error (${res.status}): ${msg}`;
}
