import { DatabaseSync } from 'node:sqlite';
import { randomBytes, createCipheriv, createDecipheriv, createHash } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

// Catalog is server-owned. Changing it never changes the nominal of an existing code.
export const REWARDS = Object.freeze({ pirate_card_100: 100, pirate_card_500: 500, pirate_card_1000: 1000 });
export class ApiError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}
export function positiveId(value) {
  if (!Number.isSafeInteger(value) || value <= 0) throw new ApiError(400, 'invalid_id');
  return value;
}
export function normalizeCode(value) {
  if (typeof value !== 'string' || value.length > 100) throw new ApiError(400, 'invalid_code');
  const code = value.toUpperCase().replace(/[\s-]/g, '');
  if (!/^[A-F0-9]{32}$/.test(code)) throw new ApiError(400, 'invalid_code');
  return code;
}
const hash = code => createHash('sha256').update(code).digest('hex');
const format = code => code.match(/.{4}/g).join('-');

export class Store {
  constructor(path, encryptionKey) {
    if (!/^[a-f0-9]{64}$/i.test(encryptionKey || '')) throw new Error('CODE_ENCRYPTION_KEY must be 64 hex characters');
    this.key = Buffer.from(encryptionKey, 'hex');
    if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true });
    this.db = new DatabaseSync(path);
    this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=5000; PRAGMA foreign_keys=ON;
      CREATE TABLE IF NOT EXISTS rewards (
        id INTEGER PRIMARY KEY, issuer TEXT NOT NULL, drop_id TEXT NOT NULL,
        roblox_user_id INTEGER NOT NULL, reward_id TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount>0),
        code_hash TEXT NOT NULL UNIQUE, code_cipher TEXT NOT NULL, created_at INTEGER NOT NULL,
        redeemed_by INTEGER, redeemed_at INTEGER, UNIQUE(issuer, drop_id));
      CREATE INDEX IF NOT EXISTS rewards_owner ON rewards(issuer, roblox_user_id, id);
      CREATE TABLE IF NOT EXISTS balances (user_id INTEGER PRIMARY KEY, amount INTEGER NOT NULL CHECK(amount>=0));
      CREATE TABLE IF NOT EXISTS ledger (
        id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, reward_id INTEGER NOT NULL UNIQUE REFERENCES rewards(id),
        amount INTEGER NOT NULL CHECK(amount>0), created_at INTEGER NOT NULL);
      CREATE INDEX IF NOT EXISTS ledger_owner ON ledger(user_id, id);
      CREATE TABLE IF NOT EXISTS rate_limits (key TEXT PRIMARY KEY, bucket INTEGER NOT NULL, hits INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);`);
    // Fail fast instead of silently losing access to issued codes after a key change.
    const fingerprint = hash(encryptionKey);
    const old = this.db.prepare("SELECT value FROM metadata WHERE key='key_fingerprint'").get();
    if (old && old.value !== fingerprint) { this.db.close(); throw new Error('Encryption key does not match database'); }
    this.db.prepare("INSERT OR IGNORE INTO metadata VALUES ('key_fingerprint', ?)").run(fingerprint);
  }
  close() { this.db.close(); }
  transaction(fn) {
    this.db.exec('BEGIN IMMEDIATE');
    try { const result = fn(); this.db.exec('COMMIT'); return result; }
    catch (e) { this.db.exec('ROLLBACK'); throw e; }
  }
  encrypt(code) {
    const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const bytes = Buffer.concat([cipher.update(code, 'utf8'), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), bytes]).toString('base64');
  }
  decrypt(value) {
    const bytes = Buffer.from(value, 'base64'), cipher = createDecipheriv('aes-256-gcm', this.key, bytes.subarray(0, 12));
    cipher.setAuthTag(bytes.subarray(12, 28));
    return Buffer.concat([cipher.update(bytes.subarray(28)), cipher.final()]).toString('utf8');
  }
  card(row) {
    return { dropId: row.drop_id, robloxUserId: row.roblox_user_id, rewardId: row.reward_id,
      amount: row.amount, code: format(this.decrypt(row.code_cipher)),
      status: row.redeemed_by === null ? 'issued' : 'redeemed', createdAt: row.created_at };
  }
  issue(issuer, input) {
    const { dropId, robloxUserId, rewardId } = input;
    positiveId(robloxUserId);
    if (typeof dropId !== 'string' || !/^[A-Za-z0-9:_-]{8,128}$/.test(dropId)) throw new ApiError(400, 'invalid_drop_id');
    if (!Object.hasOwn(REWARDS, rewardId)) throw new ApiError(400, 'unknown_reward');
    return this.transaction(() => {
      const old = this.db.prepare('SELECT * FROM rewards WHERE issuer=? AND drop_id=?').get(issuer, dropId);
      if (old) {
        if (old.roblox_user_id !== robloxUserId || old.reward_id !== rewardId) throw new ApiError(409, 'drop_conflict');
        return this.card(old);
      }
      const code = randomBytes(16).toString('hex').toUpperCase();
      this.db.prepare(`INSERT INTO rewards(issuer,drop_id,roblox_user_id,reward_id,amount,code_hash,code_cipher,created_at)
        VALUES(?,?,?,?,?,?,?,?)`).run(issuer, dropId, robloxUserId, rewardId, REWARDS[rewardId], hash(code), this.encrypt(code), Date.now());
      return this.card(this.db.prepare('SELECT * FROM rewards WHERE issuer=? AND drop_id=?').get(issuer, dropId));
    });
  }
  cards(issuer, userId, after = 0) {
    positiveId(userId);
    if (!Number.isSafeInteger(after) || after < 0) throw new ApiError(400, 'invalid_cursor');
    const rows = this.db.prepare('SELECT * FROM rewards WHERE issuer=? AND roblox_user_id=? AND id>? ORDER BY id LIMIT 50').all(issuer, userId, after);
    return { cards: rows.map(r => this.card(r)), nextCursor: rows.length === 50 ? rows.at(-1).id : null };
  }
  balance(userId) { return this.db.prepare('SELECT amount FROM balances WHERE user_id=?').get(userId)?.amount || 0; }
  account(userId) {
    return { userId, balance: this.balance(userId), history: this.db.prepare(
      'SELECT amount,created_at AS createdAt FROM ledger WHERE user_id=? ORDER BY id DESC LIMIT 20').all(userId) };
  }
  redeem(userId, input) {
    positiveId(userId);
    const code = normalizeCode(input);
    return this.transaction(() => {
      const row = this.db.prepare('SELECT * FROM rewards WHERE code_hash=?').get(hash(code));
      if (!row) throw new ApiError(404, 'code_not_found');
      if (row.redeemed_by !== null) {
        if (row.redeemed_by !== userId) throw new ApiError(409, 'code_used');
        return { amount: row.amount, balance: this.balance(userId), alreadyRedeemed: true };
      }
      const balance = this.balance(userId) + row.amount;
      if (!Number.isSafeInteger(balance)) throw new ApiError(409, 'balance_limit');
      this.db.prepare('INSERT INTO balances VALUES (?,?) ON CONFLICT(user_id) DO UPDATE SET amount=excluded.amount').run(userId, balance);
      this.db.prepare('INSERT INTO ledger(user_id,reward_id,amount,created_at) VALUES(?,?,?,?)').run(userId, row.id, row.amount, Date.now());
      this.db.prepare('UPDATE rewards SET redeemed_by=?,redeemed_at=? WHERE id=?').run(userId, Date.now(), row.id);
      return { amount: row.amount, balance, alreadyRedeemed: false };
    });
  }
  limit(key, maximum, seconds = 60) {
    const bucket = Math.floor(Date.now() / (seconds * 1000));
    const row = this.db.prepare(`INSERT INTO rate_limits VALUES(?,?,1) ON CONFLICT(key) DO UPDATE SET
      bucket=excluded.bucket,hits=CASE WHEN rate_limits.bucket=excluded.bucket THEN rate_limits.hits+1 ELSE 1 END RETURNING hits`).get(key, bucket);
    if (row.hits > maximum) throw new ApiError(429, 'rate_limited');
  }
}
