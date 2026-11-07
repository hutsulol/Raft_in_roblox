// Optional standalone worker. Run ONE instance per bot token; no webhook at the same time.
import { configuration } from './server.mjs';
import { Store, ApiError } from './store.mjs';
const config = configuration();
const store = new Store(config.dbPath, config.encryptionKey);
let stopping = false;
process.on('SIGINT', () => { stopping = true; });
process.on('SIGTERM', () => { stopping = true; });
async function telegram(method, body) {
  const res = await fetch(`https://api.telegram.org/bot${config.botToken}/${method}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(40000)
  });
  const data = await res.json();
  if (!data.ok) throw new Error(`Telegram ${method}: ${data.error_code}`);
  return data.result;
}
const errorText = { invalid_code: 'Проверьте код на карточке.', code_not_found: 'Код не найден.', code_used: 'Код уже использован.', rate_limited: 'Слишком много попыток. Подождите минуту.' };
async function handle(update) {
  const message = update.message;
  if (!message || message.chat.type !== 'private' || !message.from || message.from.is_bot || typeof message.text !== 'string') return;
  const userId = message.from.id, text = message.text.trim();
  let reply;
  try {
    store.limit(`bot:${userId}`, 20);
    if (/^\/start(?:\s|$)/.test(text)) {
      return await telegram('sendMessage', { chat_id: message.chat.id,
        text: 'Пришлите код с карточки Roblox, чтобы получить пиратов. Баланс: /balance',
        reply_markup: { inline_keyboard: [[{ text: 'Открыть кошелёк', web_app: { url: config.publicUrl } }]] } });
    }
    if (text === '/balance') reply = `Ваш баланс: ${store.balance(userId)} пиратов.`;
    else {
      // Shared limiter and transaction for BOTH chat and Mini App.
      store.limit(`redeem:${userId}`, 10);
      const result = store.redeem(userId, text.replace(/^\/redeem\s+/, ''));
      reply = result.alreadyRedeemed ? `Вы уже получили эту награду. Баланс: ${result.balance}.`
        : `Начислено ${result.amount} пиратов! Баланс: ${result.balance}.`;
    }
  } catch (e) {
    if (!(e instanceof ApiError)) throw e;
    reply = errorText[e.code] || 'Не удалось активировать код.';
  }
  await telegram('sendMessage', { chat_id: message.chat.id, text: reply });
}
try {
  const webhook = await telegram('getWebhookInfo', {});
  if (webhook.url) throw new Error('Bot has a webhook. Use another bot for this prototype, or explicitly remove its webhook first.');
  console.log('Bot polling started (token is not logged).');
  while (!stopping) {
    try {
      const offset = Number(store.db.prepare("SELECT value FROM metadata WHERE key='telegram_offset'").get()?.value || 0);
      const updates = await telegram('getUpdates', { offset, timeout: 25, allowed_updates: ['message'] });
      for (const update of updates) {
        await handle(update);
        // Commit only after handling. Replayed redemption is idempotent, including a lost sendMessage response.
        store.db.prepare("INSERT INTO metadata VALUES('telegram_offset',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").run(String(update.update_id + 1));
      }
    } catch {
      console.error('Bot temporarily unavailable; retrying.');
      await new Promise(resolve => setTimeout(resolve, 5000));
    }
  }
} finally { store.close(); }
