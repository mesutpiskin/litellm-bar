const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { LiteLLMClient, ApiError } = require('../out/client');

let server;
afterEach(() => server?.close());

/** Starts a mock proxy; `handler(req, url)` returns [status, body]. */
async function mock(handler) {
  server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    const [status, body] = handler(req, url);
    res.writeHead(status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(body));
  });
  await new Promise(r => server.listen(0, r));
  return new LiteLLMClient(LiteLLMClient.normalize(`http://localhost:${server.address().port}`));
}

const fast = { pollIntervalMs: 5, timeoutMs: 2000 };

test('hardened flow: start, open browser URL, poll with secret until ready', async () => {
  let polls = 0;
  const client = await mock((req, url) => {
    if (url.pathname === '/sso/cli/start' && req.method === 'POST') {
      return [200, { login_id: 'login123', poll_secret: 's3cret', user_code: 'ABCD-EFGH', expires_in: 600, verification_uri_complete: 'x' }];
    }
    if (url.pathname === '/sso/cli/poll/login123') {
      if (req.headers['x-litellm-cli-poll-secret'] !== 's3cret') { return [403, { detail: 'bad secret' }]; }
      return ++polls < 3 ? [200, { status: 'pending' }] : [200, { status: 'ready', key: 'sk-cli-jwt', user_id: 'dev@example.com', team_id: 't1' }];
    }
    return [404, {}];
  });

  const session = await client.startSso();
  const browser = new URL(session.browserUrl);
  assert.equal(browser.pathname, '/sso/key/generate');
  assert.equal(browser.searchParams.get('source'), 'litellm-cli');
  assert.equal(browser.searchParams.get('key'), 'login123');
  assert.equal(browser.searchParams.get('user_code'), 'ABCD-EFGH');
  assert.equal(session.userCode, 'ABCD-EFGH');

  const result = await client.waitForSso(session, fast);
  assert.deepEqual(result, { kind: 'ready', key: 'sk-cli-jwt', userId: 'dev@example.com', teamId: 't1' });
  assert.equal(polls, 3);
});

test('team selection: returns teams, then re-polls with team_id', async () => {
  const client = await mock((req, url) => {
    if (url.pathname === '/sso/cli/start') { return [200, { login_id: 'L', poll_secret: 'P', user_code: 'C' }]; }
    if (url.pathname === '/sso/cli/poll/L') {
      const team = url.searchParams.get('team_id');
      return team
        ? [200, { status: 'ready', key: `jwt-for-${team}`, user_id: 'u1' }]
        : [200, { status: 'ready', requires_team_selection: true, teams: ['t1', 't2'], team_details: [{ team_id: 't1', team_alias: 'Platform' }, { team_id: 't2' }] }];
    }
    return [404, {}];
  });
  const session = await client.startSso();
  assert.equal(new URL(session.browserUrl).searchParams.get('user_code'), null, 'code not pre-filled unless the proxy allows it');

  const first = await client.waitForSso(session, fast);
  assert.deepEqual(first, { kind: 'selectTeam', teams: [{ id: 't1', alias: 'Platform' }, { id: 't2', alias: undefined }] });
  const second = await client.waitForSso(session, { ...fast, teamId: 't2' });
  assert.equal(second.kind, 'ready');
  assert.equal(second.key, 'jwt-for-t2');
});

test('legacy proxies: client-chosen sk- session id, no secret, tolerates 404 while waiting', async () => {
  let polls = 0;
  const client = await mock((req, url) => {
    if (url.pathname === '/sso/cli/start') { return [404, { detail: 'Not Found' }]; }
    if (url.pathname.startsWith('/sso/cli/poll/sk-')) {
      assert.equal(req.headers['x-litellm-cli-poll-secret'], undefined);
      return ++polls < 3 ? [404, { detail: 'not yet' }] : [200, { status: 'ready', key: 'sk-legacy' }];
    }
    return [404, {}];
  });
  const session = await client.startSso();
  assert.match(session.loginId, /^sk-[0-9a-f-]{36}$/);
  assert.equal(session.pollSecret, undefined);
  assert.equal(new URL(session.browserUrl).searchParams.get('key'), session.loginId);
  const result = await client.waitForSso(session, fast);
  assert.equal(result.key, 'sk-legacy');
});

test('hardened flow: a rejected session fails fast', async () => {
  const client = await mock((req, url) => url.pathname === '/sso/cli/start'
    ? [200, { login_id: 'L', poll_secret: 'P', user_code: 'C' }]
    : [410, { detail: 'login session expired' }]);
  const session = await client.startSso();
  await assert.rejects(client.waitForSso(session, fast), e => e instanceof ApiError && e.status === 410);
});

test('user id falls back to the JWT claims and cancellation stops polling', async () => {
  const jwt = 'h.' + Buffer.from(JSON.stringify({ user_id: 'from-jwt' })).toString('base64url') + '.s';
  let ready = true;
  const client = await mock((req, url) => url.pathname === '/sso/cli/start'
    ? [200, { login_id: 'L', poll_secret: 'P', user_code: 'C' }]
    : [200, ready ? { status: 'ready', key: jwt } : { status: 'pending' }]);
  const session = await client.startSso();
  assert.equal((await client.waitForSso(session, fast)).userId, 'from-jwt');

  ready = false;
  let n = 0;
  await assert.rejects(client.waitForSso(session, { ...fast, isCancelled: () => ++n > 2 }), /cancelled/);
});
