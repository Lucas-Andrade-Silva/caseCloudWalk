<#
.SYNOPSIS
  Cenário S4 do playbook (§9): respostas envenenadas do agente vão para a DLQ sem travar o resto.

.DESCRIPTION
  1. Sobe o agente simulado com uma fração de respostas em JSON quebrado (MOCK_CHAOS=malformed=...).
  2. Dispara uma rajada pelo webhook real; a plataforma recusa as quebradas (422) e o broker as manda direto
     para a DLQ (ADR 0009, W9).
  3. Prova: as quebradas chegaram à DLQ, as boas continuaram sendo respondidas (a partição não travou) e os
     quatro invariantes valem (o vigia escala quem ficou sem resposta).
  4. Volta o agente ao normal.
  Rode com a pilha de desenvolvimento no ar. Dados sintéticos apenas.

.EXAMPLE
  ./scripts/demo/veneno.ps1
  ./scripts/demo/veneno.ps1 -Fracao 0.4 -Mensagens 60
#>
param(
  [double] $Fracao = 0.25,
  [int] $Mensagens = 40,
  [double] $Taxa = 4,
  [int] $Semente = (Get-Random -Maximum 100000)
)

# O Docker escreve progresso na saída de erro; no PowerShell 5.1 isso não pode virar exceção.
$ErrorActionPreference = "Continue"
Set-Location (Resolve-Path (Join-Path $PSScriptRoot "../.."))

function Write-Step([string] $text) { Write-Host "`n== $text" -ForegroundColor Green }

function Get-DlqCount {
  $line = & docker compose exec -T broker bin/dlq list 2>&1 | ForEach-Object { "$_" } |
    Where-Object { $_ -match "^\d+ mensagem" } | Select-Object -First 1
  if (-not $line) { throw "não consegui ler a DLQ do broker" }
  [int]($line -replace "^(\d+).*", '$1')
}

function Set-AgentChaos([string] $chaos) {
  $env:MOCK_CHAOS = $chaos
  & docker compose up -d --force-recreate mock-agent 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "não consegui recriar o mock-agent" }
  Start-Sleep -Seconds 8
}

$before = Get-DlqCount
Write-Step "S4: $([math]::Round($Fracao * 100))% das respostas do agente em JSON quebrado ($Mensagens mensagens, semente $Semente)"
Write-Host "DLQ antes: $before"

try {
  Set-AgentChaos "malformed=$Fracao"

  Write-Step "1. Rajada pelo webhook real"
  $burst = & docker compose exec -T api bin/rails "load:burst[$Mensagens,$Taxa,0.2,$Semente]" 2>&1 | ForEach-Object { "$_" }
  $burst | Where-Object { $_ -match "^(status|ledger):" } | ForEach-Object { Write-Host $_ }
  $ledger = ($burst | Where-Object { $_ -match "^ledger: " } | Select-Object -First 1) -replace "^ledger: ", ""
  if (-not $ledger) { throw "a rajada não gravou o ledger" }

  Write-Step "2. Esperando as respostas quebradas chegarem à DLQ (vão direto, sem retentativa)"
  $start = Get-Date
  do {
    Start-Sleep -Seconds 10
    $now = Get-DlqCount
    $elapsed = ((Get-Date) - $start).TotalSeconds
    Write-Host ("[{0:HH:mm:ss}] DLQ: {1}" -f (Get-Date), $now)
  } until ((($now - $before) -gt 0 -and $elapsed -ge 30) -or $elapsed -ge 120)
  $poisoned = (Get-DlqCount) - $before

  Write-Step "3. Invariantes (nada perdido, nada duplicado, ordem, nenhum ticket esquecido)"
  $report = & docker compose exec -T api bin/rails "invariants:check[$ledger,240]" 2>&1 | ForEach-Object { "$_" }
  $code = $LASTEXITCODE
  $report | Where-Object { -not $_.StartsWith("I, ") -and $_ -notlike "application*" -and $_ -notlike "allowed_rack*" -and
    $_ -notlike "2000*" -and $_ -notlike "trace_launcher*" } | ForEach-Object { Write-Host $_ }
  $answered = [int](($report | Where-Object { $_ -match '"answered": (\d+)' } | Select-Object -First 1) -replace '.*"answered": (\d+).*', '$1')
} finally {
  Write-Step "4. Agente de volta ao normal"
  Set-AgentChaos ""
}

Write-Host "Respostas envenenadas na DLQ: $poisoned · mensagens respondidas normalmente: $answered"
$ok = ($code -eq 0) -and ($report -contains "INVARIANTES OK") -and ($poisoned -gt 0) -and ($answered -gt 0)
if (-not $ok) {
  Write-Host "S4 não comprovado (invariantes: código $code; DLQ +$poisoned; respondidas $answered)." -ForegroundColor Red
  exit 1
}
Write-Host "S4 comprovado: o veneno foi para a DLQ, o resto seguiu e nada se perdeu." -ForegroundColor Green
