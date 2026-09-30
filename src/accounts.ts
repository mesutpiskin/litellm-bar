import * as crypto from 'crypto';
import * as vscode from 'vscode';
import { LiteLLMClient } from './client';

export type AuthMode = 'apiKey' | 'password' | 'sso';
type SecretName = 'apiKey' | 'sessionKey' | 'password';

export interface Account {
  id: string;
  label: string;
  baseUrl: string;
  authMode: AuthMode;
  username?: string;
  /** LiteLLM user id, for SSO sessions whose token is not a regular virtual key. */
  userId?: string;
}

const ACCOUNTS = 'accounts';
const ACTIVE = 'activeAccount';

/** Account metadata lives in globalState; credentials live in SecretStorage, namespaced per account. */
export class AccountStore {
  constructor(private readonly context: vscode.ExtensionContext) {}

  list(): Account[] {
    return this.context.globalState.get<Account[]>(ACCOUNTS, []);
  }

  get active(): Account | undefined {
    const accounts = this.list();
    const id = this.context.globalState.get<string>(ACTIVE);
    return accounts.find(a => a.id === id) ?? accounts[0];
  }

  async setActive(id: string) {
    await this.context.globalState.update(ACTIVE, id);
  }

  async add(account: Omit<Account, 'id'>, secrets: Partial<Record<SecretName, string>>): Promise<Account> {
    const created: Account = { ...account, id: 'acc_' + crypto.randomBytes(6).toString('hex') };
    for (const [name, value] of Object.entries(secrets) as [SecretName, string | undefined][]) {
      await this.setSecret(created, name, value);
    }
    await this.context.globalState.update(ACCOUNTS, [...this.list(), created]);
    return created;
  }

  async rename(id: string, label: string) {
    await this.update(id, { label });
  }

  async update(id: string, patch: Partial<Omit<Account, 'id'>>) {
    await this.context.globalState.update(ACCOUNTS, this.list().map(a => a.id === id ? { ...a, ...patch } : a));
  }

  async remove(id: string) {
    const account = this.list().find(a => a.id === id);
    if (!account) { return; }
    await Promise.all((['apiKey', 'sessionKey', 'password'] as SecretName[]).map(n => this.setSecret(account, n, undefined)));
    await this.context.globalState.update(ACCOUNTS, this.list().filter(a => a.id !== id));
    if (this.context.globalState.get<string>(ACTIVE) === id) {
      await this.context.globalState.update(ACTIVE, this.list()[0]?.id);
    }
  }

  /** The bearer key used for API calls: the virtual key, or the session key from a UI / SSO login. */
  key(account: Account): Thenable<string | undefined> {
    return this.secret(account, account.authMode === 'apiKey' ? 'apiKey' : 'sessionKey');
  }

  secret(account: Account, name: SecretName): Thenable<string | undefined> {
    return this.context.secrets.get(secretKey(account, name));
  }

  async setSecret(account: Account, name: SecretName, value: string | undefined) {
    if (value) {
      await this.context.secrets.store(secretKey(account, name), value);
    } else {
      await this.context.secrets.delete(secretKey(account, name));
    }
  }

  /** Imports the single account stored by versions before 0.5.0. */
  async migrateLegacy() {
    if (this.list().length) { return; }
    const baseUrl = LiteLLMClient.normalize(vscode.workspace.getConfiguration('litellm').get<string>('baseUrl'));
    const secrets = this.context.secrets;
    const [apiKey, sessionKey, password] = await Promise.all(
      ['litellm.apiKey', 'litellm.sessionKey', 'litellm.password'].map(k => secrets.get(k)));
    const authMode = this.context.globalState.get<AuthMode>('authMode', 'apiKey');
    if (!baseUrl || !(authMode === 'apiKey' ? apiKey : sessionKey)) { return; }

    const username = this.context.globalState.get<string>('username') || undefined;
    const account = await this.add(
      { label: username ? `${username} @ ${baseUrl.host}` : baseUrl.host, baseUrl: baseUrl.href, authMode, username },
      { apiKey, sessionKey, password });
    await this.setActive(account.id);
    await Promise.all(['litellm.apiKey', 'litellm.sessionKey', 'litellm.password'].map(k => secrets.delete(k)));
  }
}

function secretKey(account: Account, name: SecretName) {
  return `litellm.account.${account.id}.${name}`;
}
