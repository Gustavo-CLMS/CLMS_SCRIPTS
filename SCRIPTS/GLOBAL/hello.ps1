$logFile = "C:\CLMS\Github\test_log.txt"
$date = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
"Script executado com sucesso em $date" | Out-File $logFile -Append
Write-Host "Hello World da CLMS!"
