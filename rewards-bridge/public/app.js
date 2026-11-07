const $ = id => document.getElementById(id);
const tg = window.Telegram?.WebApp;
tg?.ready(); tg?.expand();
const errors = {
  telegram_auth_required: 'Откройте приложение через Telegram-бота.',
  invalid_telegram_auth: 'Не удалось проверить вход. Откройте приложение заново через бота.',
  telegram_auth_expired: 'Вход устарел. Закройте и снова откройте Mini App.',
  invalid_code: 'Проверьте код: нужно 32 символа, без учёта пробелов и дефисов.',
  code_not_found: 'Такой код не найден. Проверьте символы на карточке.',
  code_used: 'Этот код уже активирован другим пользователем.',
  rate_limited: 'Слишком много запросов. Повторите через минуту.',
  temporarily_unavailable: 'Сервис временно недоступен. Повторите позже — код не потеряется.'
};
let demo = false, nextCursor = null, pendingDrop = null;
function message(text, error = false) { $('status').textContent = text; $('status').className = error ? 'error' : 'success'; }
async function api(path, body) {
  const headers = { 'X-Telegram-Init-Data': tg?.initData || '' };
  if (body) headers['Content-Type'] = 'application/json';
  let res;
  try { res = await fetch(path, { method: body ? 'POST' : 'GET', headers, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(12000) }); }
  catch { throw new Error('Нет ответа сервера. Повторите запрос: повторная активация не начислит награду дважды.'); }
  const data = await res.json();
  if (!res.ok) throw new Error(errors[data.error] || 'Запрос не выполнен. Попробуйте позже.');
  return data;
}
const number = value => new Intl.NumberFormat('ru-RU').format(value);
async function refresh() {
  const me = await api('/api/me');
  $('balance').textContent = number(me.balance);
  $('greeting').textContent = `${me.name} · ${demo ? 'тестовый кошелёк' : 'баланс в боте'}`;
  $('submit').disabled = false;
  $('history').replaceChildren();
  if (!me.history.length) { const p = document.createElement('p'); p.textContent = 'Пока нет начислений. Активируйте первую карточку.'; $('history').append(p); }
  for (const item of me.history) {
    const row = document.createElement('div'); row.className = 'entry';
    const date = document.createElement('small'); date.textContent = new Date(item.createdAt).toLocaleString('ru-RU');
    const amount = document.createElement('span'); amount.className = 'positive'; amount.textContent = `+${number(item.amount)} P`;
    row.append(date, amount); $('history').append(row);
  }
}
async function cards(reset = true) {
  const data = await api(`/api/demo/cards?after=${reset ? 0 : nextCursor}`);
  if (reset) $('cards').replaceChildren();
  for (const card of data.cards) {
    const box = document.createElement('div'); box.className = 'reward-card';
    const title = document.createElement('strong'); title.textContent = `${number(card.amount)} пиратов`;
    const status = document.createElement('small'); status.textContent = card.status === 'redeemed' ? 'Активирована' : 'Можно активировать';
    const code = document.createElement('code'); code.textContent = card.code;
    const button = document.createElement('button'); button.className = 'secondary'; button.textContent = 'Вставить код';
    button.onclick = () => { $('code').value = card.code; $('code').focus(); $('redeem').scrollIntoView({ behavior: 'smooth', block: 'center' }); };
    box.append(title, status, code, button); $('cards').append(box);
  }
  nextCursor = data.nextCursor; $('more').hidden = nextCursor === null;
}
$('redeem').onsubmit = async event => {
  event.preventDefault(); $('submit').disabled = true;
  try {
    const data = await api('/api/redeem', { code: $('code').value });
    $('balance').textContent = number(data.balance);
    message(data.alreadyRedeemed ? 'Вы уже получили награду за этот код. Повторного начисления нет.' : `Начислено ${number(data.amount)} пиратов!`);
    // A failed refresh must not obscure a successful credit.
    await refresh().catch(() => {});
    if (demo) await cards().catch(() => {});
  } catch (e) { message(e.message, true); }
  finally { $('submit').disabled = false; }
};
$('issue').onclick = async () => {
  $('issue').disabled = true;
  try {
    // Retain the same event after a timeout, including a page reload.
    pendingDrop ||= { dropId: crypto.randomUUID(), rewardId: $('nominal').value };
    localStorage.setItem('pirate-demo-pending', JSON.stringify(pendingDrop));
    const card = await api('/api/demo/issue', pendingDrop);
    pendingDrop = null; localStorage.removeItem('pirate-demo-pending');
    $('code').value = card.code; message('Карточка готова. Активируйте код, чтобы получить награду.');
    await cards();
  } catch (e) { message(e.message, true); }
  finally { $('issue').disabled = false; }
};
$('refresh').onclick = () => refresh().catch(e => message(e.message, true));
$('more').onclick = () => cards(false).catch(e => message(e.message, true));
async function start() {
  demo = (await api('/api/config')).demo;
  $('demo').hidden = !demo; $('mode').textContent = demo ? 'ДЕМО' : 'MINI APP';
  if (demo) { try { pendingDrop = JSON.parse(localStorage.getItem('pirate-demo-pending')); } catch {} }
  await refresh(); if (demo) await cards();
}
start().catch(e => message(e.message, true));
