<#
.SYNOPSIS
  Roteiro de resiliência ao vivo (ADR 0009, W1): derruba o Kafka ou o agente no meio de uma rajada e prova
  que nenhuma mensagem se perdeu nem se duplicou.

.DESCRIPTION
  1. Dispara uma rajada de mensagens sintéticas pelo webhook real (com reentregas), gravando o ledger.
  2. Alguns segundos depois, para o serviço escolhido e mostra, a cada 10 s, o outbox e a fila humana.
  3. Religa o serviço e espera ele ficar saudável.
  4. Espera o fluxo esvaziar e roda invariants:check sobre o ledger (sai com código 1 se algo violar).

  Rode com a pilha de desenvolvimento no ar (docker compose up -d). Dados sintéticos apenas.

.EXAMPLE
  ./scripts/demo/resiliencia.ps1 -Cenario kafka
  ./scripts/demo/resiliencia.ps1 -Cenario agente -Mensagens 60 -QuedaSegundos 45
#>
param(
  [ValidateSet("kafka", "agente")] [string] $Cenario = "kafka",
  [int] $Mensagens = 80,
  [double] $Taxa = 4,
  [int] $QuedaSegundos = 60,
  [int] $EsperaInvariantes = 240,
  [int] $Semente = (Get-Random -Maximum 100000)
)

# O Docker escreve progresso na saída de erro; no PowerShell 5.1 isso não pode virar exceção. Cada passo confere
# o código de saída do comando.
$ErrorActionPreference = "Continue"

function Invoke-Docker {
  $output = & docker @args 2>&1
  if ($LASTEXITCODE -ne 0) { throw "docker $($args -join " ") falhou: $output" }
  $output | Where-Object { $_ -is [string] }
}
$servico = if ($Cenario -eq "kafka") { "kafka" } else { "mock-agent" }
$dbUser = if ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { "helpdesk" }

function Write-Step([string] $text) { Write-Host "`n== $text" -ForegroundColor Green }

function Get-Snapshot {
  $sql = "select (select count(*) from outbox_events where published_at is null and dead_at is null and discarded_at is null)," +
         " (select count(*) from outbox_events where dead_at is not null and discarded_at is null)," +
         " (select count(*) from tickets where mode = 'pending_human')," +
         " (select count(*) from tickets where mode = 'ai' and awaiting_agent_since is not null)"
  $row = (Invoke-Docker compose exec -T postgres psql -U $dbUser -d helpdesk_development -Atc $sql) | Select-Object -Last 1
  $parts = $row.Trim().Split("|")
  "outbox pendente: $($parts[0]) · outbox morto: $($parts[1]) · esperando humano: $($parts[2]) · esperando o agente: $($parts[3])"
}

Write-Step "Cenário: $servico fora do ar por $QuedaSegundos s, durante uma rajada de $Mensagens mensagens ($Taxa/s, semente $Semente)"
Write-Host (Get-Snapshot)

Write-Step "1. Rajada pelo webhook real (com 20% de reentregas)"
$burstLog = Join-Path ([IO.Path]::GetTempPath()) "helpdesk-burst-$Semente.log"
$burst = Start-Process -FilePath "docker" -NoNewWindow -PassThru -RedirectStandardOutput $burstLog `
  -ArgumentList @("compose", "exec", "-T", "api", "bin/rails", "load:burst[$Mensagens,$Taxa,0.2,$Semente]")
Start-Sleep -Seconds 5

Write-Step "2. Derrubando $servico"
Invoke-Docker compose stop $servico | Out-Null
$fim = (Get-Date).AddSeconds($QuedaSegundos)
while ((Get-Date) -lt $fim) {
  Write-Host ("[{0:HH:mm:ss}] {1} fora · {2}" -f (Get-Date), $servico, (Get-Snapshot))
  Start-Sleep -Seconds 10
}

Write-Step "3. Religando $servico"
Invoke-Docker compose start $servico | Out-Null
$deadline = (Get-Date).AddSeconds(120)
do {
  Start-Sleep -Seconds 3
  $id = Invoke-Docker compose ps -q $servico
  $health = Invoke-Docker inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" $id
} until ($health -in @("healthy", "running") -or (Get-Date) -gt $deadline)
Write-Host "$servico`: $health · $(Get-Snapshot)"

$burst.WaitForExit()
$ledger = (Select-String -Path $burstLog -Encoding UTF8 -Pattern "^ledger: (.+)$").Matches.Groups[1].Value
Get-Content $burstLog -Encoding UTF8 | Select-Object -Last 3 | ForEach-Object { Write-Host $_ }
if (-not $ledger) { throw "a rajada não gravou o ledger (veja $burstLog)" }

Write-Step "4. Esperando esvaziar e conferindo os invariantes (nada perdido, nada duplicado, ordem, um ticket aberto por cliente)"
$report = & docker compose exec -T api bin/rails "invariants:check[$ledger,$EsperaInvariantes]" 2>&1 | ForEach-Object { "$_" }
$code = $LASTEXITCODE
# Mostra só o relatório: o log de inicialização do OpenTelemetry começa com "I, [" e continua em linhas soltas.
$report | Where-Object { -not $_.StartsWith("I, ") -and $_ -notlike "application*" -and $_ -notlike "allowed_rack*" -and
  $_ -notlike "2000*" -and $_ -notlike "trace_launcher*" } | ForEach-Object { Write-Host $_ }
Write-Host (Get-Snapshot)
# Sucesso exige as duas provas: código de saída 0 e o relatório dizendo que os invariantes passaram.
if ($code -ne 0 -or -not ($report -contains "INVARIANTES OK")) {
  Write-Host "Invariantes violados ou não conferidos (código $code)." -ForegroundColor Red
  exit 1
}
Write-Host "Resiliência comprovada: $servico ficou $QuedaSegundos s fora e nenhuma mensagem se perdeu." -ForegroundColor Green
