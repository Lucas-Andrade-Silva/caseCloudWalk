<#
.SYNOPSIS
  Grava o vídeo de demonstração da plataforma, passo a passo e com legendas (Playwright).

.DESCRIPTION
  1. Limpa o banco de demo (demo:reset) e esvazia a DLQ das respostas do agente.
  2. Roda e2e/demo/video.spec.ts no container do Playwright, devagar, gravando a tela em 1440 × 900.
  3. Entrega o vídeo em e2e/videos/helpdesk-demo.webm (abre no navegador ou no VLC).
  Rode com a pilha de desenvolvimento no ar. Com LLM_MODE=live, título e rascunho do incidente vêm do Groq.

.EXAMPLE
  ./scripts/demo/video.ps1
#>
$ErrorActionPreference = "Continue"
Set-Location (Resolve-Path (Join-Path $PSScriptRoot "../.."))

Write-Host "== Banco de demo limpo e DLQ vazia" -ForegroundColor Green
& docker compose exec -T api bundle exec rails demo:reset 2>&1 | ForEach-Object { "$_" } |
  Where-Object { $_ -like "Banco de demo*" } | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) { Write-Host "demo:reset falhou: a pilha está no ar?" -ForegroundColor Red; exit 1 }
& docker compose exec -T broker bin/dlq purge 2>&1 | ForEach-Object { "$_" } | Select-Object -Last 1 | ForEach-Object { Write-Host $_ }

Write-Host "== Gravando (cerca de 3 minutos)" -ForegroundColor Green
& docker compose --profile e2e run --rm e2e sh -c "npm ci --no-audit --no-fund >/dev/null && npx playwright test --config demo.config.ts" 2>&1 |
  ForEach-Object { "$_" } | Where-Object { $_ -notmatch "Container|Volume" } | ForEach-Object { Write-Host $_ }
$code = $LASTEXITCODE

$video = "e2e/videos/helpdesk-demo.webm"
if ($code -eq 0 -and (Test-Path $video)) {
  Write-Host "Vídeo pronto: $(Resolve-Path $video)" -ForegroundColor Green
} else {
  Write-Host "A gravação falhou (código $code); veja e2e/demo-results." -ForegroundColor Red
  exit 1
}
