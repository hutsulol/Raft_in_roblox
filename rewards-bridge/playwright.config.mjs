import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './browser-test',
  workers: 1,
  use: { baseURL: 'http://127.0.0.1:8798', viewport: { width: 390, height: 844 }, headless: true },
  webServer: {
    command: 'node server.mjs --demo',
    url: 'http://127.0.0.1:8798/health',
    env: { PORT: '8798', DEMO_DATA_DIR: './data/browser-test' },
    reuseExistingServer: false
  }
});
