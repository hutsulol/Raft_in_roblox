import http from 'node:http';
import { readFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes, randomUUID } from 'node:crypto';
import { Store, ApiError } from './store.mjs';
import { telegramUser, equalSecret } from './auth.mjs';

const root = dirname(fileURLToPath(import.meta.url));
export function configuration(env = process.env, demo = false) {
  const port = Number(env.PORT || 8787);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT');
  if (demo) {
    const dataDir = resolve(env.DEMO_DATA_DIR || resolve(root, 'data/demo'));
    mkdirSync(dataDir, { recursive: true });
    const keyFile = resolve(dataDir, 'key');
    if (!existsSync(keyFile)) writeFileSync(keyFile, randomBytes(32).toString('hex'), { mode: 0o600, flag: 'wx' });
    const studioKeyFile = resolve(dataDir, 'studio.key');
    if (!existsSync(studioKeyFile)) writeFileSync(studioKeyFile, randomBytes(32).toString('hex'), { mode: 0o600, flag: 'wx' });
    return { demo: true, port, publicUrl: `http://127.0.0.1:${port}`, issuer: 'demo',
      dbPath: resolve(dataDir, 'rewards.sqlite'), encryptionKey: readFileSync(keyFile, 'utf8'), apiKey: readFileSync(studioKeyFile, 'utf8'), botToken: '' };
  }
  const { PUBLIC_URL, ROBLOX_API_KEY, CODE_ENCRYPTION_KEY, BOT_TOKEN, ROBLOX_UNIVERSE_ID } = env;
  if (!PUBLIC_URL || new URL(PUBLIC_URL).protocol !== 'https:') throw new Error('PUBLIC_URL must be HTTPS');
  if (!ROBLOX_API_KEY || ROBLOX_API_KEY.length < 32 || ROBLOX_API_KEY.includes('REPLACE')) throw new Error('Set ROBLOX_API_KEY (32+ characters)');
  if (!BOT_TOKEN || !/^\d+:[\w-]+$/.test(BOT_TOKEN)) throw new Error('Set BOT_TOKEN');
  if (!/^[1-9]\d*$/.test(ROBLOX_UNIVERSE_ID || '')) throw new Error('Set ROBLOX_UNIVERSE_ID');
  return { demo: false, port, publicUrl: new URL(PUBLIC_URL).origin, issuer: ROBLOX_UNIVERSE_ID,
    dbPath: resolve(env.DB_PATH || resolve(root, 'data/rewards.sqlite')),
    encryptionKey: CODE_ENCRYPTION_KEY, apiKey: ROBLOX_API_KEY, botToken: BOT_TOKEN };
}
async function jsonBody(req) {
  if (req.headers['content-type']?.split(';')[0] !== 'application/json') throw new ApiError(415, 'json_required');
  let length = 0;
  const chunks = [];
  for await (const chunk of req) {
    length += chunk.length;
    if (length > 16384) throw new ApiError(413, 'body_too_large');
    chunks.push(chunk);
  }
  try {
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (!body || Array.isArray(body) || typeof body !== 'object') throw new Error();
    return body;
  } catch { throw new ApiError(400, 'invalid_json'); }
}
export function makeServer(config, store) {
  const files = { '/': ['index.html', 'text/html; charset=utf-8'], '/app.js': ['app.js', 'text/javascript; charset=utf-8'], '/style.css': ['style.css', 'text/css; charset=utf-8'] };
  const server = http.createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self' https://telegram.org; style-src 'self'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'self'; frame-ancestors 'self' https://web.telegram.org");
    const send = (status, body) => {
      res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify(body));
    };
    try {
      // No CORS. Also block cross-site requests to the local development service.
      const origin = req.headers.origin;
      if (origin && origin !== config.publicUrl) throw new ApiError(403, 'origin_denied');
      if (config.demo && ![`127.0.0.1:${config.port}`, `localhost:${config.port}`].includes(req.headers.host)) throw new ApiError(403, 'host_denied');
      const url = new URL(req.url, 'http://localhost');
      if (req.method === 'GET' && files[url.pathname]) {
        const [file, type] = files[url.pathname];
        res.writeHead(200, { 'Content-Type': type });
        return res.end(readFileSync(resolve(root, 'public', file)));
      }
      if (req.method === 'GET' && url.pathname === '/health') {
        store.db.prepare('SELECT 1').get(); return send(200, { ok: true });
      }
      if (req.method === 'GET' && url.pathname === '/api/config') return send(200, { demo: config.demo });
      if (url.pathname.startsWith('/api/roblox/')) {
        if (!config.apiKey || !equalSecret(req.headers['x-api-key'], config.apiKey)) throw new ApiError(401, 'server_auth_required');
        store.limit(`issue:${config.issuer}`, 240);
        if (req.method === 'POST' && url.pathname === '/api/roblox/rewards/issue') {
          const body = await jsonBody(req);
          if (String(body.universeId) !== (config.demo ? '0' : config.issuer)) throw new ApiError(403, 'universe_denied');
          return send(200, store.issue(config.issuer, body));
        }
        if (req.method === 'GET' && url.pathname === '/api/roblox/rewards') {
          return send(200, store.cards(config.issuer, Number(url.searchParams.get('userId')), Number(url.searchParams.get('after') || 0)));
        }
        throw new ApiError(404, 'not_found');
      }
      const user = config.demo ? { id: 1, first_name: 'Капитан' } : telegramUser(req.headers['x-telegram-init-data'], config.botToken);
      if (req.method === 'GET' && url.pathname === '/api/me') {
        store.limit(`account:${user.id}`, 120);
        return send(200, { ...store.account(user.id), name: user.first_name || 'Капитан' });
      }
      if (req.method === 'POST' && url.pathname === '/api/redeem') {
        store.limit(`redeem:${user.id}`, 10);
        return send(200, store.redeem(user.id, (await jsonBody(req)).code));
      }
      if (config.demo && req.method === 'POST' && url.pathname === '/api/demo/issue') {
        store.limit('demo:issue', 20);
        const body = await jsonBody(req);
        return send(200, store.issue('demo', { dropId: body.dropId || randomUUID(), robloxUserId: 1, rewardId: body.rewardId }));
      }
      if (config.demo && req.method === 'GET' && url.pathname === '/api/demo/cards') return send(200, store.cards('demo', 1, Number(url.searchParams.get('after') || 0)));
      throw new ApiError(404, 'not_found');
    } catch (e) {
      if (e instanceof ApiError) {
        if (e.status === 429) res.setHeader('Retry-After', '60');
        return send(e.status, { error: e.code });
      }
      // Do not log request bodies, headers or codes.
      console.error('Request failed:', e.code || e.name);
      send(503, { error: 'temporarily_unavailable' });
    }
  });
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  server.timeout = 20000;
  return server;
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const config = configuration(process.env, process.argv.includes('--demo'));
  const store = new Store(config.dbPath, config.encryptionKey);
  const server = makeServer(config, store);
  // Deliberately loopback-only; production HTTPS is supplied by a reverse proxy.
  server.listen(config.port, '127.0.0.1', () => console.log(`${config.demo ? 'DEMO (separate test balance)' : 'API'}: ${config.publicUrl}`));
  const shutdown = () => server.close(() => { store.close(); process.exit(0); });
  process.on('SIGTERM', shutdown); process.on('SIGINT', shutdown);
}
