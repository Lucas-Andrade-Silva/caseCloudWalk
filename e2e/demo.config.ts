import { defineConfig, devices } from "@playwright/test";

// Gravação do vídeo de demonstração (não é teste de regressão): uma jornada só, devagar, com legendas, gravada
// em 1440 × 900. Rode com scripts/demo/video.ps1, que prepara o banco e copia o vídeo para e2e/videos/.
export default defineConfig({
  testDir: "./demo",
  workers: 1,
  timeout: 15 * 60_000,
  expect: { timeout: 60_000 },
  retries: 0,
  outputDir: "demo-results",
  reporter: [["list"]],
  use: {
    baseURL: process.env.BASE_URL ?? "http://localhost:5173",
    locale: "pt-BR",
    timezoneId: "America/Sao_Paulo",
    viewport: { width: 1440, height: 900 },
    video: { mode: "on", size: { width: 1440, height: 900 } },
    launchOptions: { slowMo: 120 },
  },
  projects: [{ name: "demo", use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } } }],
});
