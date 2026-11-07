/* @ds-bundle: {"format":4,"namespace":"RaftUI","components":[{"name":"ResourceChip"},{"name":"AdOfferButton"},{"name":"AdOfferCard"},{"name":"AdOfferPrompt"},{"name":"AdBillboard"}]} */
(function () {
  'use strict';

  var O = 'stroke:var(--outline);stroke-width:3;stroke-linejoin:round;stroke-linecap:round;';
  function f(tok) { return 'style="fill:var(--' + tok + ');' + O + '"'; }
  function svg(body, cls) {
    return '<svg class="rh-ico ' + (cls || '') + '" viewBox="0 0 48 48" aria-hidden="true">' + body + '</svg>';
  }

  /* ---------- Resource icons (48×48, 3px outline, flat cartoon) ---------- */
  var ICONS = {
    log: svg(
      '<rect x="4" y="12" width="36" height="24" rx="12" ' + f('wood') + '/>' +
      '<path d="M12 20h12M10 28h16" style="fill:none;stroke:#00000040;stroke-width:2.5;stroke-linecap:round"/>' +
      '<ellipse cx="37" cy="24" rx="7" ry="12" ' + f('wood-light') + '/>' +
      '<ellipse cx="37" cy="24" rx="3" ry="5.5" style="fill:none;stroke:var(--wood);stroke-width:2.5"/>'
    ),
    plank: svg(
      '<rect x="4" y="11" width="40" height="11" rx="3" ' + f('wood-light') + '/>' +
      '<rect x="4" y="26" width="40" height="11" rx="3" ' + f('wood') + '/>' +
      '<circle cx="10" cy="16.5" r="1.8" style="fill:var(--outline)"/><circle cx="38" cy="16.5" r="1.8" style="fill:var(--outline)"/>' +
      '<circle cx="10" cy="31.5" r="1.8" style="fill:var(--outline)"/><circle cx="38" cy="31.5" r="1.8" style="fill:var(--outline)"/>'
    ),
    ingot: svg(
      '<path d="M5 36 L11 20 H37 L43 36 Z" ' + f('metal') + '/>' +
      '<path d="M11 20 L15 12 H33 L37 20 Z" ' + f('metal-light') + '/>' +
      '<path d="M15 27 h8" style="fill:none;stroke:#ffffffb3;stroke-width:3;stroke-linecap:round"/>'
    ),
    fuel: svg(
      '<path d="M40 16 L44 9" style="fill:none;stroke:var(--outline);stroke-width:7;stroke-linecap:round"/>' +
      '<path d="M40 16 L44 9" style="fill:none;stroke:var(--metal);stroke-width:3;stroke-linecap:round"/>' +
      '<path d="M13 8 H29 L39 16 V41 a3 3 0 0 1 -3 3 H13 a3 3 0 0 1 -3 -3 V11 a3 3 0 0 1 3 -3 Z" ' + f('fuel') + '/>' +
      '<rect x="15" y="12" width="10" height="5" rx="2.5" style="fill:var(--outline)"/>' +
      '<path d="M16 24 L32 38 M32 24 L16 38" style="fill:none;stroke:#00000047;stroke-width:3;stroke-linecap:round"/>'
    ),
    rope: svg(
      '<path d="M36 32 q8 4 5 11" style="fill:none;stroke:var(--outline);stroke-width:8;stroke-linecap:round"/>' +
      '<path d="M36 32 q8 4 5 11" style="fill:none;stroke:var(--rope);stroke-width:4;stroke-linecap:round"/>' +
      '<circle cx="23" cy="23" r="17" ' + f('rope') + '/>' +
      '<circle cx="23" cy="23" r="10.5" style="fill:none;stroke:#8a6428;stroke-width:3"/>' +
      '<circle cx="23" cy="23" r="4" style="fill:#8a6428"/>'
    ),
    food: svg(
      '<path d="M33 24 L44 15 L44 33 Z" ' + f('hunger') + '/>' +
      '<path d="M5 24 C11 11 29 11 35 24 C29 37 11 37 5 24 Z" ' + f('hunger') + '/>' +
      '<circle cx="13" cy="22" r="2.4" style="fill:var(--outline)"/>' +
      '<path d="M22 17 q4 7 0 14" style="fill:none;stroke:#00000040;stroke-width:2.5;stroke-linecap:round"/>'
    ),
    water: svg(
      '<path d="M24 5 C24 5 38 21 38 30 A14 14 0 0 1 10 30 C10 21 24 5 24 5 Z" ' + f('water') + '/>' +
      '<path d="M16.5 29 a8 8 0 0 0 5 7.5" style="fill:none;stroke:#ffffffb3;stroke-width:3;stroke-linecap:round"/>'
    )
  };

  var PICTO = {
    tv: svg(
      '<path d="M18 11 L13 4 M30 11 L35 4" style="fill:none;' + O + '"/>' +
      '<rect x="3" y="11" width="42" height="30" rx="7" ' + f('panel-raised') + '/>' +
      '<rect x="8" y="16" width="32" height="20" rx="4" ' + f('watch') + '/>' +
      '<path d="M20 20.5 L30 26 L20 31.5 Z" style="fill:var(--ink);' + O + 'stroke-width:2"/>'
    ),
    chest: svg(
      '<rect x="5" y="21" width="38" height="21" rx="3" ' + f('wood') + '/>' +
      '<path d="M5 23 V17 a9 9 0 0 1 9 -9 h20 a9 9 0 0 1 9 9 v6 Z" ' + f('wood-light') + '/>' +
      '<path d="M5 23 H43" style="fill:none;' + O + '"/>' +
      '<rect x="19.5" y="18" width="9" height="12" rx="2" ' + f('reward') + '/>' +
      '<circle cx="24" cy="24" r="1.8" style="fill:var(--outline)"/>'
    ),
    play: '<svg class="rh-ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5.5 L19 12 L8 18.5 Z" style="fill:var(--ink);stroke:var(--outline);stroke-width:2;stroke-linejoin:round"/></svg>'
  };

  var NAMES = { log: 'Брёвна', plank: 'Доски', ingot: 'Слитки', fuel: 'Топливо', rope: 'Верёвка', food: 'Еда', water: 'Вода' };

  function registerResource(id, def) {
    ICONS[id] = def.svg;
    NAMES[id] = def.name || id;
  }

  /* ---------- helpers ---------- */
  function el(tag, cls, html) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (html != null) n.innerHTML = html;
    return n;
  }
  function icon(id) { return ICONS[id] || ICONS.log; }
  function fmt(n) { return n >= 1000 ? (Math.round(n / 100) / 10) + 'K' : String(n); }
  function total(list) { var s = 0; (list || []).forEach(function (r) { s += r.amount || 0; }); return s; }

  /* ---------- ResourceChip ---------- */
  function ResourceChip(p) {
    p = p || {};
    var c = el('div', 'rh-chip' + (p.size === 'sm' ? ' rh-chip--sm' : '') + (p.more ? ' rh-chip--more' : ''));
    c.setAttribute('role', 'img');
    if (p.more) {
      c.innerHTML = '<span class="rh-chip-more">+' + p.more + '</span>';
      c.setAttribute('aria-label', 'Ещё ' + p.more + ' ресурса');
      return c;
    }
    c.innerHTML = icon(p.id) + '<span class="rh-chip-amt">+' + fmt(p.amount || 0) + '</span>';
    c.setAttribute('aria-label', (NAMES[p.id] || p.id) + ': +' + (p.amount || 0));
    return c;
  }

  function chipRow(resources, maxVisible, size) {
    var row = el('div', 'rh-chips');
    var list = resources || [];
    var max = maxVisible || 4;
    var shown = list.length > max ? list.slice(0, max - 1) : list;
    shown.forEach(function (r) { row.appendChild(ResourceChip({ id: r.id, amount: r.amount, size: size })); });
    if (list.length > max) row.appendChild(ResourceChip({ more: list.length - shown.length, size: size }));
    return row;
  }

  /* ---------- AdOfferButton (HUD entry point, left column) ---------- */
  function AdOfferButton(p) {
    p = p || {};
    var variant = p.variant || 'tv';
    var res = p.resources || [];
    var state = p.state || 'ready';
    var b = el('button', 'rh-hudbtn rh-hudbtn--' + variant + ' is-' + state);
    b.type = 'button';
    var art = el('span', 'rh-hudbtn-art');

    if (variant === 'ring') {
      var main = res[0] || { id: 'log', amount: 0 };
      var pct = p.progress == null ? 1 : p.progress;
      art.style.setProperty('--p', Math.round(pct * 360) + 'deg');
      art.innerHTML = '<span class="rh-ring"></span><span class="rh-ring-core">' + icon(main.id) + '</span>' +
        '<span class="rh-playbadge">' + PICTO.play + '</span>';
    } else {
      art.innerHTML = variant === 'chest' ? PICTO.chest : PICTO.tv;
      if (variant === 'chest') art.innerHTML += '<span class="rh-playbadge">' + PICTO.play + '</span>';
      if (res.length) {
        var bub = el('span', 'rh-bubble');
        var first = res.slice(0, 2);
        first.forEach(function (r) { bub.innerHTML += icon(r.id); });
        if (res.length === 1) bub.innerHTML += '<span class="rh-bubble-amt">+' + fmt(res[0].amount) + '</span>';
        else if (res.length > 2) bub.innerHTML += '<span class="rh-bubble-amt rh-bubble-amt--more">+' + (res.length - 2) + '</span>';
        art.appendChild(bub);
      }
    }
    b.appendChild(art);

    var label = state === 'cooldown' ? (p.cooldownText || '2:41') : (p.label || (variant === 'chest' ? 'Бонус' : 'Награда'));
    b.appendChild(el('span', 'rh-hudbtn-label', label));
    var names = res.map(function (r) { return (NAMES[r.id] || r.id) + ' ' + r.amount; }).join(', ');
    b.setAttribute('aria-label', 'Посмотреть рекламу и получить: ' + (names || 'награду'));
    if (state === 'cooldown') b.disabled = true;
    if (p.onClick) b.addEventListener('click', p.onClick);
    return b;
  }

  /* ---------- AdOfferCard (bottom-right, non-blocking, 12 s) ---------- */
  function AdOfferCard(p) {
    p = p || {};
    var bonus = p.variant === 'bonus';
    var card = el('section', 'rh-card' + (bonus ? ' rh-card--bonus' : ''));
    card.setAttribute('role', 'dialog');
    card.setAttribute('aria-live', 'polite');
    var dur = p.duration || 12;

    var head = el('div', 'rh-card-head');
    head.innerHTML = '<span class="rh-card-pict">' + (bonus ? PICTO.chest : PICTO.tv) + '</span>' +
      '<span class="rh-card-titles"><span class="rh-card-title">' +
      (p.title || (bonus ? 'Бонус течения' : 'Не хватает ресурсов')) + '</span>' +
      '<span class="rh-card-sub">' + (p.subtitle || (bonus ? 'Сундук с ресурсами за рекламу' : 'Посмотри рекламу — получишь недостающее')) + '</span></span>';
    card.appendChild(head);

    card.appendChild(chipRow(p.resources, p.maxVisible || 4));

    var actions = el('div', 'rh-card-actions');
    var watch = el('button', 'rh-btn rh-btn--watch', '<span>Смотреть</span>' + PICTO.play);
    var later = el('button', 'rh-btn rh-btn--ghost', '<span class="rh-later-full">Не сейчас</span><span class="rh-later-x" aria-hidden="true">✕</span>');
    later.setAttribute('aria-label', 'Не сейчас');
    watch.type = later.type = 'button';
    actions.appendChild(watch); actions.appendChild(later);
    card.appendChild(actions);

    var bar = el('div', 'rh-timer', '<span class="rh-timer-fill"></span>');
    bar.style.setProperty('--dur', dur + 's');
    if (p.timer === 'static') bar.style.setProperty('--static', String(p.timerValue == null ? 0.6 : p.timerValue));
    else bar.classList.add('is-running');
    card.appendChild(bar);

    var closed = false;
    function close(reason) {
      if (closed) return; closed = true;
      card.classList.add('is-leaving');
      if (p.onDismiss && reason !== 'watch') p.onDismiss(reason);
    }
    watch.addEventListener('click', function () { if (p.onWatch) p.onWatch(p.resources); close('watch'); });
    later.addEventListener('click', function () { close('later'); });
    if (p.timer !== 'static') {
      bar.firstChild.addEventListener('animationend', function () { close('timeout'); });
    }
    return card;
  }

  /* ---------- AdOfferPrompt (contextual, next to the build/interact prompt) ---------- */
  function AdOfferPrompt(p) {
    p = p || {};
    var b = el('button', 'rh-prompt');
    b.type = 'button';
    var need = (p.resources || []).map(function (r) {
      return '<span class="rh-prompt-need">' + icon(r.id) + '<b>' + fmt(r.amount) + '</b></span>';
    }).join('');
    b.innerHTML = '<span class="rh-prompt-key">' + PICTO.play + '</span>' +
      '<span class="rh-prompt-text"><span class="rh-prompt-top">' + (p.target || 'Не хватает') + '</span>' +
      '<span class="rh-prompt-row">' + need + '<span class="rh-prompt-cta">' + (p.cta || 'За рекламу') + '</span></span></span>';
    if (p.onClick) b.addEventListener('click', p.onClick);
    return b;
  }

  /* ---------- AdBillboard (world-space, над NPC: «Награда с рейдов») ---------- */
  function closeBtn(small) {
    var x = el('button', 'rh-close' + (small ? ' rh-close--sm' : ''),
      '<svg class="rh-ico" viewBox="0 0 24 24" aria-hidden="true">' +
      '<path d="M7 7 L17 17 M17 7 L7 17" style="fill:none;stroke:var(--outline);stroke-width:6;stroke-linecap:round"/>' +
      '<path d="M7 7 L17 17 M17 7 L7 17" style="fill:none;stroke:var(--ink);stroke-width:2.6;stroke-linecap:round"/></svg>');
    x.type = 'button';
    x.setAttribute('aria-label', 'Закрыть');
    return x;
  }

  var CROWN = '<svg class="rh-ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 18 L3 8 L8.5 12 L12 5 L15.5 12 L21 8 L20 18 Z" style="fill:var(--reward);stroke:var(--outline);stroke-width:2;stroke-linejoin:round"/></svg>';
  var CHECK = '<svg class="rh-ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5 L10 17 L19 7" style="fill:none;stroke:var(--outline);stroke-width:6;stroke-linecap:round;stroke-linejoin:round"/><path d="M5 12.5 L10 17 L19 7" style="fill:none;stroke:var(--watch-light);stroke-width:3;stroke-linecap:round;stroke-linejoin:round"/></svg>';

  function rewardSlot(r, claimed) {
    var c = el('div', 'rh-chip rh-slot' + (r.premium ? ' rh-slot--premium' : '') + (claimed ? ' is-claimed' : ''));
    c.setAttribute('role', 'img');
    c.innerHTML = icon(r.id) + '<span class="rh-chip-amt">+' + fmt(r.amount) + '</span>' +
      (r.premium ? '<span class="rh-slot-crown">' + CROWN + '</span>' : '') +
      (claimed ? '<span class="rh-slot-check">' + CHECK + '</span>' : '');
    c.setAttribute('aria-label', (r.premium ? 'Премиум: ' : '') + (NAMES[r.id] || r.id) + ' +' + r.amount + (claimed ? ', получено' : ''));
    return c;
  }

  function AdBillboard(p) {
    p = p || {};
    var state = p.state || 'full';              // full | claimed | cooldown | compact
    var res = p.resources || [];
    var free = res.filter(function (r) { return !r.premium; }).slice(0, 2);
    var prem = res.filter(function (r) { return r.premium; }).slice(0, 2);
    var price = p.price == null ? 49 : p.price;
    var root = el('div', 'rh-bb rh-bb--' + state);
    var closed = false;
    function close() {
      if (closed) return; closed = true;
      root.classList.add('is-leaving');
      if (p.onClose) p.onClose();
    }
    var x = p.closable === false ? null : closeBtn(state === 'compact');
    if (x) x.addEventListener('click', function (e) { e.stopPropagation(); close(); });

    if (state === 'compact') {
      var pill = el('button', 'rh-bb-pill');
      pill.type = 'button';
      pill.innerHTML = '<span class="rh-bb-key">' + PICTO.chest + '</span>' +
        '<span class="rh-bb-icons">' + free.map(function (r) { return icon(r.id); }).join('') + '</span>' +
        (prem.length ? '<span class="rh-bb-icons rh-bb-icons--premium">' + prem.map(function (r) { return icon(r.id); }).join('') + '</span>' : '');
      pill.setAttribute('aria-label', (p.title || 'Награда с рейда') + ': ' + res.length + ' наград');
      if (p.onOpen) pill.addEventListener('click', p.onOpen);
      var wrap = el('div', 'rh-bb-pillwrap');
      wrap.appendChild(pill);
      if (x) wrap.appendChild(x);
      root.appendChild(wrap);
      root.appendChild(el('span', 'rh-bb-tail'));
      return root;
    }

    var panel = el('div', 'rh-bb-panel');
    panel.innerHTML = '<div class="rh-bb-head"><span class="rh-bb-pict">' + PICTO.chest + '</span>' +
      '<span class="rh-card-titles"><span class="rh-bb-title">' + (p.title || 'Награда с рейда') + '</span>' +
      '<span class="rh-card-sub">' + (p.subtitle || 'Лодочник привезёт ещё раз') + '</span></span></div>';
    if (x) panel.appendChild(x);

    var freeClaimed = state === 'claimed' || state === 'cooldown';
    var row = el('div', 'rh-bb-slots');
    free.forEach(function (r) { row.appendChild(rewardSlot(r, freeClaimed)); });
    if (prem.length) {
      row.appendChild(el('span', 'rh-bb-divider'));
      prem.forEach(function (r) { row.appendChild(rewardSlot(r, false)); });
    }
    panel.appendChild(row);

    var actions = el('div', 'rh-bb-actions');
    var bFree = el('button', 'rh-paybtn rh-paybtn--free');
    bFree.type = 'button';
    if (freeClaimed) {
      bFree.disabled = true;
      bFree.classList.add('is-off');
      bFree.innerHTML = '<span class="rh-paybtn-main">Снова через</span><span class="rh-paybtn-sub rh-tabnum">' + (p.cooldownText || '4:12') + '</span>';
    } else {
      bFree.innerHTML = '<span class="rh-paybtn-main">' + (p.freeLabel || 'Бесплатно') + '</span>' +
        '<span class="rh-paybtn-sub">' + (p.freeSub || ('Обычные · ' + free.length)) + '</span>';
      if (p.onFree) bFree.addEventListener('click', function () { p.onFree(free); });
    }
    var bPay = el('button', 'rh-paybtn rh-paybtn--robux');
    bPay.type = 'button';
    var payMain = '<span class="rh-robux" aria-hidden="true">R$</span>' + price;
    var paySub = freeClaimed ? 'Премиум · ' + prem.length : 'Всё · ' + (free.length + prem.length);
    bPay.innerHTML = '<span class="rh-paybtn-main">' + payMain + '</span><span class="rh-paybtn-sub">' + paySub + '</span>';
    bPay.setAttribute('aria-label', 'Купить за ' + price + ' робуксов: ' + paySub);
    if (p.onBuy) bPay.addEventListener('click', function () { p.onBuy(freeClaimed ? prem : free.concat(prem)); });
    actions.appendChild(bFree);
    if (prem.length) actions.appendChild(bPay);
    panel.appendChild(actions);

    root.appendChild(panel);
    root.appendChild(el('span', 'rh-bb-tail'));
    return root;
  }

  function mount(target, node) {
    var t = typeof target === 'string' ? document.querySelector(target) : target;
    t.appendChild(node);
    return node;
  }

  window.RaftUI = {
    ResourceChip: ResourceChip,
    AdOfferButton: AdOfferButton,
    AdOfferCard: AdOfferCard,
    AdOfferPrompt: AdOfferPrompt,
    AdBillboard: AdBillboard,
    registerResource: registerResource,
    icon: icon,
    icons: ICONS,
    names: NAMES,
    total: total,
    mount: mount
  };
})();
