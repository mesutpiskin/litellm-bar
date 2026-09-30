const { test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');

// Minimal in-memory stand-in for the `vscode` module.
let settings = {};
const vscodeStub = {
  workspace: { getConfiguration: () => ({ get: key => settings[key] }) },
};
const originalLoad = Module._load;
Module._load = function (request, ...rest) {
  return request === 'vscode' ? vscodeStub : originalLoad.call(this, request, ...rest);
};
const { AccountStore } = require('../out/accounts');

function fakeContext() {
  const state = new Map();
  const secrets = new Map();
  return {
    secretsApi: secrets,
    secrets: {
      get: async k => secrets.get(k),
      store: async (k, v) => { secrets.set(k, v); },
      delete: async k => { secrets.delete(k); },
    },
    globalState: {
      get: (k, d) => (state.has(k) ? state.get(k) : d),
      update: async (k, v) => { v === undefined ? state.delete(k) : state.set(k, v); },
      set: (k, v) => state.set(k, v),
    },
  };
}

let ctx;
let store;
beforeEach(() => {
  settings = {};
  ctx = fakeContext();
  store = new AccountStore(ctx);
});

test('adds accounts, keeps credentials per account and tracks the active one', async () => {
  const a = await store.add({ label: 'Work', baseUrl: 'https://a.example.com/', authMode: 'apiKey' }, { apiKey: 'sk-a' });
  const b = await store.add({ label: 'Personal', baseUrl: 'https://b.example.com/', authMode: 'password', username: 'me' },
    { sessionKey: 'sk-session-b', password: 'pw' });

  assert.equal(store.list().length, 2);
  assert.equal(store.active.id, a.id, 'first account is active by default');
  assert.equal(await store.key(a), 'sk-a');
  assert.equal(await store.key(b), 'sk-session-b', 'password accounts use the session key');

  await store.setActive(b.id);
  assert.equal(store.active.id, b.id);

  await store.rename(b.id, 'Home');
  assert.equal(store.list().find(x => x.id === b.id).label, 'Home');
});

test('removing the active account deletes its secrets and falls back to another account', async () => {
  const a = await store.add({ label: 'A', baseUrl: 'https://a.example.com/', authMode: 'apiKey' }, { apiKey: 'sk-a' });
  const b = await store.add({ label: 'B', baseUrl: 'https://b.example.com/', authMode: 'apiKey' }, { apiKey: 'sk-b' });
  await store.setActive(b.id);

  await store.remove(b.id);
  assert.deepEqual(store.list().map(x => x.id), [a.id]);
  assert.equal(store.active.id, a.id);
  assert.equal(await store.key(b), undefined);
  assert.equal([...ctx.secretsApi.keys()].some(k => k.includes(b.id)), false);
});

test('migrates the pre-0.5 single account and removes the legacy secrets', async () => {
  settings['baseUrl'] = 'https://litellm.example.com';
  ctx.globalState.set('authMode', 'password');
  ctx.globalState.set('username', 'dev');
  ctx.secretsApi.set('litellm.sessionKey', 'sk-legacy');
  ctx.secretsApi.set('litellm.password', 'pw');

  await store.migrateLegacy();

  const [acc] = store.list();
  assert.equal(acc.label, 'dev @ litellm.example.com');
  assert.equal(acc.authMode, 'password');
  assert.equal(store.active.id, acc.id);
  assert.equal(await store.key(acc), 'sk-legacy');
  assert.equal(await store.secret(acc, 'password'), 'pw');
  assert.equal(ctx.secretsApi.has('litellm.sessionKey'), false);

  await store.migrateLegacy();
  assert.equal(store.list().length, 1, 'migration runs only once');
});

test('does nothing when there is no legacy sign-in', async () => {
  settings['baseUrl'] = 'https://litellm.example.com';
  await store.migrateLegacy();
  assert.equal(store.list().length, 0);
});
