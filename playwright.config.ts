import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  timeout: 180000, // 3 minutes for agent compilation/deployment
  use: {
    baseURL: 'https://qis.hayashi-dev.me',
    headless: false,
    viewport: { width: 1280, height: 720 },
  },
});
