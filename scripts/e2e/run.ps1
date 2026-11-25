<#
.SYNOPSIS
  Testes ponta a ponta no navegador (Playwright) contra a pilha de desenvolvimento no ar.

.DESCRIPTION
  1. Deixa o banco de demo limpo (demo:reset: apaga as conversas e cria a cliente com histórico).
  2. Roda as jornadas de e2e/tests no container do Playwright, na rede do serviço web.
  O relatório fica em e2e/playwright-report (abra o index.html). Sai com o código do Playwright.

.EXAMPLE
  ./scripts/e2e/run.ps1
#>
$ErrorActionPreference = "Continue"
Set-Location (Resolve-Path (Join-Path $PSScriptRoot "../.."))

Write-Host "== Banco de demo limpo" -ForegroundColor Green
& docker compose exec -T api bundle exec rails demo:reset 2>&1 | ForEach-Object { "$_" } |
  Where-Object { $_ -like "Banco de demo*" } | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) { Write-Host "demo:reset falhou: a pilha está no ar?" -ForegroundColor Red; exit 1 }

Write-Host "== Jornadas no navegador" -ForegroundColor Green
& docker compose --profile e2e run --rm e2e 2>&1 | ForEach-Object { "$_" } | ForEach-Object { Write-Host $_ }
exit $LASTEXITCODE
