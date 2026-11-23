<#
.SYNOPSIS
  Experimento oficial enxuto (playbook §9; ADR 0009, W6), na pilha em modo de produção (projeto helpdesk-pilot).

.DESCRIPTION
  Cenários:
    S1  rampa 1× → 10× → 50× → 1× com 30% de reentregas fora de ordem;
    S2  10× com o Kafka pausado (docker pause) por 60 s no meio;
    S3  10× com o agente em caos (latência de 200 a 2000 ms e 5% de silêncio).
  A LLM fica desligada (LLM_MODE=off): mede-se a plataforma sem dependência externa.

  Cada rodada grava em backend/tmp/experiment/<rodada>/: k6.json (saída bruta), ledger.jsonl, invariants.txt,
  report.json e report.txt. Rode com a pilha de desenvolvimento parada (-PararDev, padrão) para o gerador e a pilha
  não disputarem CPU com ela.

.EXAMPLE
  ./scripts/experiment/run.ps1 -Cenarios S1,S2,S3 -Rodadas 3
  ./scripts/experiment/run.ps1 -Cenarios S1 -Rodadas 1 -Curto   # ensaio rápido do encanamento
#>
param(
  [string[]] $Cenarios = @("S1", "S2", "S3"),
  [int] $Rodadas = 3,
  [int] $Semente = 42,
  [switch] $Curto,
  [bool] $PararDev = $true
)

# O Docker escreve progresso na saída de erro; no PowerShell 5.1 isso não pode virar exceção.
$ErrorActionPreference = "Continue"
$root = Resolve-Path (Join-Path $PSScriptRoot "../..")
Set-Location $root
$compose = @("compose", "-p", "helpdesk-pilot", "-f", "compose.yaml", "-f", "compose.pilot.yaml", "-f", "compose.experiment.yaml")
$services = @("postgres", "redis", "kafka", "api", "relay", "sidekiq", "broker", "broker-replies", "mock-agent")
$dbUser = if ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { "helpdesk" }

function Invoke-Pilot {
  $output = & docker @compose @args 2>&1 | ForEach-Object { "$_" }
  if ($LASTEXITCODE -ne 0) { throw "docker compose $($args -join " ") falhou:`n$($output -join "`n")" }
  $output
}

function Write-Step([string] $text) { Write-Host "`n== $text" -ForegroundColor Green }

function Get-OutboxPending {
  $sql = "select count(*) from outbox_events where published_at is null and dead_at is null and discarded_at is null"
  [int]((Invoke-Pilot exec -T postgres psql -U $dbUser -d helpdesk_production -Atc $sql) | Select-Object -Last 1)
}

$stagesFor = @{
  S1 = if ($Curto) { "1x:1:20;10x:10:40;50x:50:30;1x-volta:1:20" } else { "1x:1:60;10x:10:180;50x:50:120;1x-volta:1:60" }
  S2 = if ($Curto) { "1x:1:20;10x-kafka:10:80;1x-volta:1:20" } else { "1x:1:60;10x-kafka:10:240;1x-volta:1:60" }
  S3 = if ($Curto) { "1x:1:20;10x-caos:10:60;1x-volta:1:20" } else { "1x:1:60;10x-caos:10:240;1x-volta:1:60" }
}
$chaos = "latency_ms=200..2000,silence=0.05"

if ($PararDev) {
  Write-Step "Parando a pilha de desenvolvimento (volta no fim)"
  & docker compose stop 2>&1 | Out-Null
}

try {
Write-Step "Subindo a pilha em modo de produção (LLM desligada)"
$env:LLM_MODE = "off"
$env:MOCK_CHAOS = ""
Invoke-Pilot up -d --build @services | Out-Null

$summary = @()
foreach ($cenario in $Cenarios) {
  # Caos só no S3: o mock sobe de novo com ou sem a configuração.
  $env:MOCK_CHAOS = if ($cenario -eq "S3") { $chaos } else { "" }
  Invoke-Pilot up -d --force-recreate mock-agent | Out-Null
  Start-Sleep -Seconds 10

  for ($rodada = 1; $rodada -le $Rodadas; $rodada++) {
    $run = "{0}-r{1}-{2:yyyyMMddHHmmss}" -f $cenario.ToLower(), $rodada, (Get-Date)
    $dir = "backend/tmp/experiment/$run"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $stages = $stagesFor[$cenario]
    Write-Step "$cenario, rodada $rodada de $Rodadas ($run): fases $stages"

    $k6Args = @($compose + @("--profile", "experiment", "run", "--rm", "-T",
      "-e", "RUN=$run", "-e", "SEED=$($Semente + $rodada)", "-e", "REDELIVER=0.3", "-e", "BASE_RATE=5", "-e", "STAGES=$stages", "-e", "PRE_VUS=1000",
      "k6", "run", "--quiet", "--out", "json=/results/$run/k6.json", "/scripts/webhooks.js"))
    $k6 = Start-Process -FilePath "docker" -ArgumentList $k6Args -NoNewWindow -PassThru `
      -RedirectStandardOutput "$dir/k6-summary.txt" -RedirectStandardError "$dir/k6-stderr.txt"

    $drain = $null
    if ($cenario -eq "S2") {
      # Pausa o Kafka 30 s depois do início do 10× (que começa depois da fase de 1×) e solta 60 s depois.
      $firstStage = [int]($stages.Split(";")[0].Split(":")[2])
      Start-Sleep -Seconds ($firstStage + 30)
      Write-Host "Kafka pausado"
      Invoke-Pilot pause kafka | Out-Null
      for ($s = 0; $s -lt 60; $s += 10) { Start-Sleep -Seconds 10; Write-Host "  outbox pendente: $(Get-OutboxPending)" }
      Invoke-Pilot unpause kafka | Out-Null
      $released = Get-Date
      Write-Host "Kafka de volta"
      do { Start-Sleep -Seconds 2; $pending = Get-OutboxPending } until ($pending -eq 0 -or ((Get-Date) - $released).TotalSeconds -gt 600)
      $drain = [math]::Round(((Get-Date) - $released).TotalSeconds)
      Write-Host "  outbox drenado em $drain s depois de soltar o Kafka (o gerador seguia enviando)"
    }

    $k6.WaitForExit()
    if (-not (Test-Path "$dir/k6.json")) { throw "o k6 não gerou a saída (veja $dir/k6-stderr.txt)" }
    Get-Content "$dir/k6-summary.txt" -Encoding UTF8 | Select-Object -Last 12 | ForEach-Object { Write-Host $_ }

    Invoke-Pilot exec -T api bin/rails "experiment:ledger[tmp/experiment/$run/k6.json,$stages,tmp/experiment/$run/ledger.jsonl]" |
      Where-Object { -not $_.StartsWith("I, ") } | Select-Object -Last 1 | ForEach-Object { Write-Host $_ }
    $invariants = & docker @compose exec -T api bin/rails "invariants:check[tmp/experiment/$run/ledger.jsonl,600]" 2>&1 | ForEach-Object { "$_" }
    $invariantsOk = ($LASTEXITCODE -eq 0) -and ($invariants -contains "INVARIANTES OK")
    $invariants | Where-Object { -not $_.StartsWith("I, ") -and $_ -notmatch "^(application|allowed_rack|2000|trace_launcher)" } |
      Set-Content -Encoding UTF8 "$dir/invariants.txt"
    $report = Invoke-Pilot exec -T api bin/rails "experiment:report[tmp/experiment/$run/ledger.jsonl,tmp/experiment/$run/report.json]" |
      Where-Object { -not $_.StartsWith("I, ") -and $_ -notmatch "^(application|allowed_rack|2000|trace_launcher)" }
    $report | Set-Content -Encoding UTF8 "$dir/report.txt"
    $report | ForEach-Object { Write-Host $_ }
    Write-Host ("Invariantes: {0}" -f $(if ($invariantsOk) { "OK" } else { "VIOLADOS (ver $dir/invariants.txt)" })) -ForegroundColor $(if ($invariantsOk) { "Green" } else { "Red" })
    $summary += [pscustomobject]@{ Rodada = $run; Invariantes = $(if ($invariantsOk) { "OK" } else { "VIOLADOS" }); DrenagemKafka_s = $drain }
  }
}

$summary | Format-Table -AutoSize | Out-String | Write-Host
$summary | ConvertTo-Json | Set-Content -Encoding UTF8 "backend/tmp/experiment/summary-$(Get-Date -Format yyyyMMddHHmmss).json"

} finally {
  # Mesmo com erro no meio, a pilha de desenvolvimento volta.
  if ($PararDev) {
    Write-Host "`n== Parando a pilha do experimento e religando a de desenvolvimento" -ForegroundColor Green
    & docker @compose stop 2>&1 | Out-Null
    & docker compose start 2>&1 | Out-Null
  }
}
