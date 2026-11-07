import { test, expect } from '@playwright/test';
test('mobile: issue, activate, retry and reload preserve one credit', async ({ page }) => {
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  // Local demo must work even when Telegram SDK/network is unavailable.
  await page.route('https://telegram.org/**', route => route.abort());
  await page.goto('/');
  await expect(page.locator('#submit')).toBeEnabled();
  const number = text => Number(text.replace(/\D/g, ''));
  const before = number(await page.locator('#balance').textContent());
  await page.locator('#issue').click();
  await expect(page.locator('#code')).toHaveValue(/^[A-F0-9-]{39}$/);
  await page.locator('#submit').click();
  await expect(page.locator('#status')).toContainText('Начислено 1');
  expect(number(await page.locator('#balance').textContent())).toBe(before + 1000);
  await page.locator('#submit').click();
  await expect(page.locator('#status')).toContainText('уже получили');
  expect(number(await page.locator('#balance').textContent())).toBe(before + 1000);
  await page.reload();
  await expect(page.locator('#submit')).toBeEnabled();
  expect(number(await page.locator('#balance').textContent())).toBe(before + 1000);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.screenshot({ path: 'test-results/miniapp-mobile.png', fullPage: true });
  expect(errors).toEqual([]);
});
