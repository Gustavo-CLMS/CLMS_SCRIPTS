$logFile = "C:\CLMS\Github\test_global.txt"
$date = Get-Date -Format "dd/MM/yyyy HH:mm:ss"

# Lê o DNA para saber quem está logando
$machine = Get-Content "C:\CLMS\Github\machine.json" | ConvertFrom-Json

$mensagem = "[$date] CLIENTE: $($machine.cliente) | SETOR: $($machine.setor) | Agente instalado e testado com sucesso!"

$mensagem | Out-File $logFile -Append -Encoding utf8
Write-Host $mensagem
