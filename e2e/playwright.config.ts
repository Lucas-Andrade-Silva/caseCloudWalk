import { defineConfig, devices } from "@playwright/test";

// Ponta a ponta contra a pilha real (docker compose up). Roda dentro da rede do serviço `web`: o navegador
// acessa http://localhost:5173 como um usuário, e o Vite repassa /api para o Rails.
export default defineConfig({
  testDir: "./tests",
  // As jornadas mexem no mesmo banco de desenvolvimento: uma de cada vez, na ordem dos arquivos.
  workers: 1,
  fullyParallel: false,
  timeout: 120_000,
  expect: { timeout: 30_000 },
  retries: 0,
  reporter: [["list"], ["html", { open: "never", outputFolder: "playwright-report" }]],
  use: {
    baseURL: process.env.BASE_URL ?? "http://localhost:5173",
    locale: "pt-BR",
    timezoneId: "America/Sao_Paulo",
    viewport: { width: 1440, height: 900 },
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } } }],
});
