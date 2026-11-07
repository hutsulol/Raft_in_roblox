// Explicit manual smoke of the running LOCAL DEMO, never a production account.
// node test/live-smoke.mjs
// Restart the demo server, then: node test/live-smoke.mjs --verify-restart
import assert from 'node:assert/strict';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { chromium } from '@playwright/test';

const base = 'http://127.0.0.1:8787';
const config = await (await fetch(`${base}/api/config`)).json();
assert.equal(config.demo, true, 'This smoke test is restricted to local demo mode');
const file = 'test-results/live-smoke.json';
if (process.argv.includes('--verify-restart')) {
  const saved = JSON.parse(readFileSync(file, 'utf8'));
  const me = await (await fetch(`${base}/api/me`)).json();
  assert.equal(me.balance, saved.balance);
  const response = await fetch(`${base}/api/redeem`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code: saved.code })
  });
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.alreadyRedeemed, true);
  assert.equal(result.balance, saved.balance);
  console.log('PASS: process restart preserves balance and prevents repeat credit:', result.balance);
} else {
  mkdirSync('test-results', { recursive: true });
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('https://telegram.org/**', route => route.abort());
    await page.goto(base);
    await page.waitForFunction(() => !document.querySelector('#submit').disabled);
    const initial = await (await fetch(`${base}/api/me`)).json();
    let issued;
    // The server commits issuance, but the browser receives a network failure.
    await page.route('**/api/demo/issue', async route => {
      const response = await route.fetch();
      assert.equal(response.status(), 200);
      issued = await response.json();
      await route.abort('failed');
    }, { times: 1 });
    await page.locator('#issue').click();
    await page.waitForFunction(() => document.querySelector('#status').classList.contains('error'));
    assert.ok(issued?.code);
    // The persisted event must survive a page reload and return the SAME code.
    await page.reload();
    await page.waitForFunction(() => !document.querySelector('#submit').disabled);
    await page.locator('#issue').click();
    await page.waitForFunction(() => document.querySelector('#code').value.length > 0);
    assert.equal(await page.locator('#code').inputValue(), issued.code);
    await page.locator('#submit').click();
    await page.waitForFunction(() => document.querySelector('#status').textContent.includes('Начислено'));
    await page.waitForFunction(() => !document.querySelector('#submit').disabled);
    await page.locator('#submit').click();
    await page.waitForFunction(() => document.querySelector('#status').textContent.includes('уже получили'));
    await page.waitForFunction(() => !document.querySelector('#submit').disabled);
    const current = await (await fetch(`${base}/api/me`)).json();
    assert.equal(current.balance, initial.balance + issued.amount);
    assert.deepEqual(errors, []);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
    writeFileSync(file, JSON.stringify({ balance: current.balance, code: issued.code }, null, 2));
    await page.screenshot({ path: 'test-results/live-mobile.png', fullPage: true });
    console.log('PASS: live mobile UI, lost-response retry after reload, same code, one credit:', current.balance);
  } finally { await browser.close(); }
}
