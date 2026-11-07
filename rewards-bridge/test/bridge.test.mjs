import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { createHmac } from 'node:crypto';
import { Worker } from 'node:worker_threads';
import { Store } from '../store.mjs';
import { telegramUser } from '../auth.mjs';
import { makeServer, configuration } from '../server.mjs';

const key = 'ab'.repeat(32), botToken = '123456:test_bot_token';
const input = { dropId: 'saved-drop-0001', robloxUserId: 42, rewardId: 'pirate_card_1000' };
function temp(t) {
  const dir = mkdtempSync(join(tmpdir(), 'pirate-bridge-'));
  return join(dir, 'test.sqlite');
}
function removeDb(path) { rmSync(dirname(path), { recursive: true, force: true }); }
function signed(userId, age = 0) {
  const values = { auth_date: String(Math.floor(Date.now() / 1000) - age), query_id: 'test-query', user: JSON.stringify({ id: userId, first_name: 'Капитан' }) };
  const secret = createHmac('sha256', 'WebAppData').update(botToken).digest();
  const hash = createHmac('sha256', secret).update(Object.keys(values).sort().map(k => `${k}=${values[k]}`).join('\n')).digest('hex');
  return new URLSearchParams({ ...values, hash }).toString();
}
test('same drop is idempotent across restart and nominal is server-owned', t => {
  const path = temp(t);
  t.after(() => removeDb(path));
  let store = new Store(path, key);
  const first = store.issue('u1', { ...input, amount: 999999 });
  assert.equal(first.amount, 1000);
  store.close(); store = new Store(path, key);
  assert.deepEqual(store.issue('u1', input), first);
  assert.throws(() => store.issue('u1', { ...input, robloxUserId: 99 }), { code: 'drop_conflict' });
  assert.throws(() => store.issue('u1', { ...input, rewardId: 'pirate_card_100' }), { code: 'drop_conflict' });
  assert.throws(() => store.issue('u1', { ...input, rewardId: '__proto__' }), { code: 'unknown_reward' });
  assert.notEqual(store.issue('u2', input).code, first.code);
  const row = store.db.prepare('SELECT code_cipher FROM rewards LIMIT 1').get();
  assert.ok(!row.code_cipher.includes(first.code.replaceAll('-', '')));
  store.close();
  assert.throws(() => new Store(path, 'cd'.repeat(32)), /does not match/);
});
test('redeem once; retry same user is successful; another user cannot spend it', t => {
  const path = temp(t), store = new Store(path, key); t.after(() => { store.close(); removeDb(path); });
  const card = store.issue('u1', input);
  assert.deepEqual(store.redeem(1, card.code.toLowerCase()), { amount: 1000, balance: 1000, alreadyRedeemed: false });
  assert.equal(store.redeem(1, card.code).alreadyRedeemed, true);
  assert.throws(() => store.redeem(2, card.code), { code: 'code_used' });
  assert.equal(store.balance(1), 1000); assert.equal(store.balance(2), 0);
  assert.equal(store.account(1).history.length, 1);
  assert.equal(store.cards('u1', 42).cards[0].status, 'redeemed');
  assert.equal(store.cards('u1', 43).cards.length, 0);
});
test('failed ledger insertion rolls back both balance and code consumption', t => {
  const path = temp(t), store = new Store(path, key); t.after(() => { store.close(); removeDb(path); });
  const card = store.issue('u1', input);
  store.db.exec("CREATE TRIGGER test_failure BEFORE INSERT ON ledger BEGIN SELECT RAISE(ABORT,'test disk failure'); END");
  assert.throws(() => store.redeem(1, card.code));
  assert.equal(store.balance(1), 0);
  assert.equal(store.cards('u1', 42).cards[0].status, 'issued');
  store.db.exec('DROP TRIGGER test_failure');
  assert.equal(store.redeem(1, card.code).balance, 1000);
});
test('two independent workers compete for one code: exactly one ledger credit', async t => {
  const path = temp(t), store = new Store(path, key);
  t.after(() => removeDb(path));
  const card = store.issue('u1', input);
  const moduleUrl = new URL('../store.mjs', import.meta.url).href;
  const work = userId => new Promise((resolve, reject) => {
    const worker = new Worker(`const {parentPort,workerData}=require('node:worker_threads');
      (async()=>{const {Store}=await import(workerData.moduleUrl); const s=new Store(workerData.path,workerData.key);
      try{parentPort.postMessage({ok:true,result:s.redeem(workerData.userId,workerData.code)})}
      catch(e){parentPort.postMessage({ok:false,error:e.code})}finally{s.close()}})();`,
    { eval: true, workerData: { moduleUrl, path, key, userId, code: card.code } });
    let result;
    worker.on('message', data => { result = data; }); worker.on('error', reject);
    worker.on('exit', code => code === 0 ? resolve(result) : reject(new Error(`Worker exit ${code}`)));
  });
  const results = await Promise.all([work(1), work(2), work(3), work(4)]);
  assert.equal(results.filter(x => x.ok).length, 1);
  assert.equal(store.db.prepare('SELECT SUM(amount) AS total FROM balances').get().total, 1000);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM ledger').get().n, 1);
  store.close();
});
test('Telegram HMAC authentication rejects tampering, expiry, duplicate fields and future dates', () => {
  assert.equal(telegramUser(signed(17), botToken).id, 17);
  assert.throws(() => telegramUser(signed(17).replace('17', '18'), botToken), { status: 401 });
  assert.throws(() => telegramUser(signed(17, 3601), botToken), { code: 'telegram_auth_expired' });
  assert.throws(() => telegramUser(signed(17, -120), botToken), { code: 'telegram_auth_expired' });
  assert.throws(() => telegramUser(signed(17) + '&auth_date=1', botToken), { status: 401 });
  assert.throws(() => telegramUser(signed(17), 'different'), { status: 401 });
});
async function httpFixture(t, demo = false) {
  const path = temp(t), store = new Store(path, key);
  const config = { port: 0, demo, issuer: '123', apiKey: 'test-secret-key-that-is-32-chars-long', botToken, publicUrl: 'https://rewards.example.com' };
  const server = makeServer(config, store);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  config.port = server.address().port;
  const base = `http://127.0.0.1:${config.port}`;
  if (demo) config.publicUrl = base;
  t.after(async () => { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); store.close(); removeDb(path); });
  const request = async (path, body, headers = {}) => {
    const res = await fetch(base + path, { method: body ? 'POST' : 'GET', headers: { 'Content-Type': 'application/json', ...headers }, body: body ? JSON.stringify(body) : undefined });
    return { status: res.status, body: await res.json() };
  };
  return { request, config, store, base };
}
test('real HTTP: issue -> lost-response retry -> redeem -> history; unauthorized minting is denied', async t => {
  const { request, config } = await httpFixture(t);
  const payload = { ...input, universeId: 123 };
  assert.equal((await request('/api/roblox/rewards/issue', payload)).status, 401);
  const headers = { 'X-API-Key': config.apiKey };
  const first = await request('/api/roblox/rewards/issue', payload, headers);
  assert.equal(first.status, 200);
  assert.deepEqual(await request('/api/roblox/rewards/issue', payload, headers), first);
  assert.equal((await request('/api/roblox/rewards/issue', { ...payload, universeId: 456 }, headers)).status, 403);
  assert.equal((await request('/api/roblox/rewards?userId=42', null, headers)).body.cards[0].code, first.body.code);
  assert.equal((await request('/api/redeem', { code: first.body.code })).status, 401);
  const user = { 'X-Telegram-Init-Data': signed(100) };
  assert.equal((await request('/api/redeem', { code: first.body.code, userId: 999, amount: 99999 }, user)).body.balance, 1000);
  assert.equal((await request('/api/redeem', { code: first.body.code }, user)).body.alreadyRedeemed, true);
  const me = await request('/api/me', null, user);
  assert.equal(me.body.userId, 100); assert.equal(me.body.history.length, 1);
  assert.equal((await request('/api/demo/issue', {}, user)).status, 404);
  assert.equal((await request('/api/redeem', { code: first.body.code }, { ...user, Origin: 'https://evil.example' })).status, 403);
  for (let i = 0; i < 8; i++) await request('/api/redeem', { code: 'bad' }, user);
  assert.equal((await request('/api/redeem', { code: first.body.code }, user)).status, 429);
});
test('local demo issues real database-backed codes; static UI and persistent balance', async t => {
  const { request, base } = await httpFixture(t, true);
  assert.equal((await request('/api/config')).body.demo, true);
  const card = await request('/api/demo/issue', { dropId: 'demo-drop-test', rewardId: 'pirate_card_500' });
  assert.equal(card.body.amount, 500);
  assert.equal((await request('/api/redeem', { code: card.body.code })).body.balance, 500);
  assert.equal((await request('/api/me')).body.balance, 500);
  assert.equal((await request('/api/demo/cards')).body.cards[0].status, 'redeemed');
  assert.equal((await fetch(base)).status, 200);
  assert.match(await (await fetch(base + '/app.js')).text(), /\/api\/redeem/);
});
test('production configuration fails closed without secrets or HTTPS', () => {
  assert.throws(() => configuration({}), /HTTPS/);
  assert.throws(() => configuration({ PUBLIC_URL: 'https://rewards.example.com' }), /ROBLOX_API_KEY/);
});
test('Studio uses the real Roblox endpoints with a server-only key, without Telegram', async t => {
  const { request, config } = await httpFixture(t, true);
  const payload = { ...input, universeId: 0 };
  assert.equal((await request('/api/roblox/rewards/issue', payload)).status, 401);
  const headers = { 'X-API-Key': config.apiKey };
  const first = await request('/api/roblox/rewards/issue', payload, headers);
  assert.equal(first.status, 200);
  assert.equal((await request('/api/roblox/rewards/issue', payload, headers)).body.code, first.body.code);
  assert.equal((await request('/api/roblox/rewards/issue', { ...payload, universeId: 1 }, headers)).status, 403);
  assert.equal((await request('/api/roblox/rewards?userId=42', null, headers)).body.cards[0].code, first.body.code);
  assert.equal((await request('/api/redeem', { code: first.body.code })).body.balance, 1000);
  assert.deepEqual((await request('/api/config')).body, { demo: true });
});
