import { createHmac, timingSafeEqual } from 'node:crypto';
import { ApiError, positiveId } from './store.mjs';
export function equalSecret(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const x = Buffer.from(a), y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}
export function telegramUser(initData, botToken, now = Math.floor(Date.now() / 1000)) {
  if (typeof initData !== 'string' || initData.length > 8192) throw new ApiError(401, 'telegram_auth_required');
  const params = new URLSearchParams(initData);
  if ([...params.keys()].length !== new Set(params.keys()).size) throw new ApiError(401, 'invalid_telegram_auth');
  const received = params.get('hash');
  params.delete('hash');
  const text = [...params.entries()].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([k, v]) => `${k}=${v}`).join('\n');
  const secret = createHmac('sha256', 'WebAppData').update(botToken).digest();
  const expected = createHmac('sha256', secret).update(text).digest('hex');
  if (!equalSecret(received, expected)) throw new ApiError(401, 'invalid_telegram_auth');
  const date = Number(params.get('auth_date'));
  if (!Number.isSafeInteger(date) || date > now + 30 || date < now - 3600) throw new ApiError(401, 'telegram_auth_expired');
  try { const user = JSON.parse(params.get('user')); positiveId(user.id); return user; }
  catch { throw new ApiError(401, 'invalid_telegram_auth'); }
}
