###############################################################################
#    ____ _     __  __ ____  
#   / ___| |   |  \/  / ___| 
#  | |   | |   | |\/| \___ \ 
#  | |___| |___| |  | |___) |
#   \____|_____|_|  |_|____/ 
#
# PROPRIEDADE EXCLUSIVA DE: CLMS Tecnologia | clms.com.br
###############################################################################
#
# SCRIPT:      CLMS-Deploy-Winget.ps1
# FINALIDADE:  Implantar automacao Winget com Merge Inteligente de Blacklist
# CLIENTE:     [INSERIR NOME DO CLIENTE / AMBIENTE]
#
# ESTE SOFTWARE E SEU CODIGO-FONTE SAO CONFIDENCIAIS E PROPRIETARIOS.
# E TERMINANTEMENTE PROIBIDA A COPIA, DISTRIBUICAO OU USO SEM AUTORIZACAO
# EXPRESSA DA CLMS TECNOLOGIA. O USO INDEVIDO ESTA SUJEITO A SANCOES LEGAIS.
#
###############################################################################
# INFORMACOES TECNICAS:
# Criado por:  Mauro (Sysadmin) | mauro@clms.com.br
# Versao:      1.0.6
# Data:        23/03/2026
# Requisitos:  PowerShell 5.1+, Permissoes de Administrador
###############################################################################
# HISTORICO DE ALTERACOES:
# ...
# 22/03/26 | 1.0.4    | Mauro   | Adicionada descricao oficial nas tarefas.
# 23/03/26 | 1.0.5    | Mauro   | Adicionado controle de Hash (SHA-256) para GPO.
# 23/03/26 | 1.0.6    | Mauro   | Sincronizacao (Merge) inteligente da Blacklist.
###############################################################################

# ==============================================================================
# TRAVA DE SEGURANCA: VERIFICA SE ESTA RODANDO COMO ADMINISTRADOR
# ==============================================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "ATENCAO: Este script de implantacao requer privilegios elevados!"
    Write-Warning "Feche esta janela, clique com o botao direito no PowerShell e selecione 'Executar como Administrador'."
    Break
}

# ==============================================================================
# CONTROLE DE VERSAO POR HASH (EVITA EXECUCOES REDUNDANTES NA GPO)
# ==============================================================================
$BaseDir      = "C:\CLMS\SCRIPTz\Winget"
$HashFile     = "$BaseDir\DeployHash.txt"
$CurrentScript = $MyInvocation.MyCommand.Path

if ($CurrentScript -and (Test-Path -Path $CurrentScript)) {
    $CurrentHash = (Get-FileHash -Path $CurrentScript -Algorithm SHA256).Hash
    if (Test-Path -Path $HashFile) {
        $SavedHash = Get-Content -Path $HashFile
        if ($CurrentHash -eq $SavedHash) {
            Write-Output "Automacao Winget (CLMS) ja esta atualizada nesta maquina (Hash match). Pulando deploy."
            Exit
        }
    }
}

Write-Output "Iniciando o Deploy da Automacao Winget - CLMS Tecnologia..."

# 1. Nova Estrutura de Diretorios
$LogDir       = "$BaseDir\Logs"
$BlacklistDir = "$BaseDir\Blacklist"

foreach ($dir in @($BaseDir, $LogDir, $BlacklistDir)) {
    if (-not (Test-Path -Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

Write-Output "Ajustando permissoes NTFS para centralizacao de logs..."
$SID_Usuarios = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')
$NomeGrupo = $SID_Usuarios.Translate([System.Security.Principal.NTAccount]).Value
$Acl = Get-Acl $LogDir
$Ar = New-Object System.Security.AccessControl.FileSystemAccessRule($NomeGrupo, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
$Acl.SetAccessRule($Ar)
Set-Acl -Path $LogDir -AclObject $Acl

# ==============================================================================
# 1.1 BLACKLIST MASTER - Sincronizacao Inteligente (Merge)
# ==============================================================================
# Adicione os bloqueios GLOBAIS aqui. O script vai mesclar com os bloqueios locais.
$MasterBlacklist = @(
    "AETEurope.SafeSignICStandard",
    "Ubiquiti.UniFiNetworkServer",
    "Oracle.JavaRuntimeEnvironment"
)

$BlacklistFile = "$BlacklistDir\Blacklist.txt"

if (-not (Test-Path -Path $BlacklistFile)) {
    Write-Output "Criando arquivo padrao de Blacklist..."
    $Header = @(
        "# =============================================================================="
        "# CLMS Tecnologia - Blacklist de Aplicativos (Winget)"
        "# =============================================================================="
        "# Insira abaixo os IDs dos aplicativos que NAO devem ser atualizados."
    )
    Set-Content -Path $BlacklistFile -Value ($Header + $MasterBlacklist) -Encoding UTF8
} else {
    Write-Output "Verificando sincronia da Blacklist global..."
    $LocalBlacklist = Get-Content -Path $BlacklistFile | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }
    foreach ($app in $MasterBlacklist) {
        if ($LocalBlacklist -notcontains $app) {
            Add-Content -Path $BlacklistFile -Value $app -Encoding UTF8
            Write-Output " -> Adicionado novo bloqueio global: $app"
        }
    }
}

# ==============================================================================
# 2. Gerando o Script de MAQUINA (SYSTEM)
# ==============================================================================
$ScriptMachinePath = "$BaseDir\CLMS-Update-WingetApps.ps1"
$ScriptMachineContent = @'
###############################################################################
# SCRIPT:      CLMS-Update-WingetApps.ps1 (MAQUINA/SYSTEM)
# PROPRIEDADE: CLMS Tecnologia | clms.com.br
###############################################################################

$BaseDir      = "C:\CLMS\SCRIPTz\Winget"
$LogDir       = "$BaseDir\Logs"
$LogFile      = "$LogDir\Winget_SysUpdate_$(Get-Date -Format 'yyyy-MM').log"
$BlacklistTxt = "$BaseDir\Blacklist\Blacklist.txt"

Get-ChildItem -Path $LogDir -Filter "Winget_SysUpdate_*.log" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) } | Remove-Item -Force -ErrorAction SilentlyContinue

Start-Transcript -Path $LogFile -Append -Force
Write-Output "----------------------------------------------------------------"
Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Iniciando rotina de atualizacao Winget (SYSTEM)."

$wingetPath = $null
$userWinget = Join-Path -Path $env:LOCALAPPDATA -ChildPath "Microsoft\WindowsApps\winget.exe"

if (Test-Path -Path $userWinget) {
    $wingetPath = $userWinget
} else {
    $appInstallerPaths = Get-ChildItem -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller*" -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    foreach ($path in $appInstallerPaths) {
        $tempPath = Join-Path -Path $path.FullName -ChildPath "winget.exe"
        if (Test-Path -Path $tempPath) { $wingetPath = $tempPath; break }
    }
}

if ($wingetPath) {
    $env:TEMP = "C:\Windows\Temp"
    $env:TMP = "C:\Windows\Temp"
    
    if (Test-Path -Path $BlacklistTxt) {
        Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Lendo Blacklist.txt..."
        $Blacklist = Get-Content -Path $BlacklistTxt | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }
        foreach ($app in $Blacklist) {
            $app = $app.Trim()
            Write-Output " -> Garantindo bloqueio para: $app"
            & $wingetPath pin add --id $app --accept-source-agreements --force | Out-Null
        }
    }
    
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Aplicando atualizacoes (ESCOPO MAQUINA)..."

# -----------------------------ALTERAÇÃO GUSTAVO---------------------------  

$wingetOutput = & $wingetPath upgrade --all --silent --accept-package-agreements --accept-source-agreements --scope machine --include-unknown 2>&1

# salva log bruto
$wingetOutput | Out-File "$LogDir\Winget_SysUpdate_raw.log" -Append

# gerar log bonitinho
$StatusFile = "$LogDir\status_machine.txt"
$Data = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$failures = $wingetOutput | Where-Object { $_ -match "Failed|Error" }

$realFailures = @()

foreach ($line in $failures) {
    $ignore = $false
    foreach ($app in $Blacklist) {
        if ($line -match $app) {
            $ignore = $true
            break
        }
    }
    if (-not $ignore) {
        $realFailures += $line
    }
}

if ($realFailures.Count -eq 0) {
    "OK | $Data | Atualizacao SYSTEM concluida" | Out-File $StatusFile -Force
} else {
    $msg = $realFailures -join " | "
    "ERRO | $Data | SYSTEM Falhas: $msg" | Out-File $StatusFile -Force
}
    

# -----------------------------FIM ALTERAÇÃO GUSTAVO----------------------- 

    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0 -or $exitCode -eq 2316632065) {
        Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] STATUS: SUCESSO."
    } else {
        Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] STATUS: Codigo $exitCode retornado."
    }
} else {
    Write-Error "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ERRO: Winget nao encontrado."
}
Write-Output "----------------------------------------------------------------"
Stop-Transcript
'@
Set-Content -Path $ScriptMachinePath -Value $ScriptMachineContent -Encoding UTF8

# ==============================================================================
# 3. Gerando o Script de USUARIO
# ==============================================================================
$ScriptUserPath = "$BaseDir\CLMS-Update-WingetUserApps.ps1"
$ScriptUserContent = @'
###############################################################################
# SCRIPT:      CLMS-Update-WingetUserApps.ps1 (USUARIO)
# PROPRIEDADE: CLMS Tecnologia | clms.com.br
###############################################################################

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$BaseDir      = "C:\CLMS\SCRIPTz\Winget"
$LogDir       = "$BaseDir\Logs"
$LogFile      = "$LogDir\Winget_UsrUpdate_$(Get-Date -Format 'yyyy-MM').log"
$BlacklistTxt = "$BaseDir\Blacklist\Blacklist.txt"

Get-ChildItem -Path $LogDir -Filter "Winget_UsrUpdate_*.log" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) } | Remove-Item -Force -ErrorAction SilentlyContinue

Start-Transcript -Path $LogFile -Append -Force
Write-Output "----------------------------------------------------------------"
Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Iniciando rotina (ESCOPO USUARIO)."

$wingetPath = Join-Path -Path $env:LOCALAPPDATA -ChildPath "Microsoft\WindowsApps\winget.exe"

if (Test-Path -Path $wingetPath) {
    
    if (Test-Path -Path $BlacklistTxt) {
        Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Lendo Blacklist.txt..."
        $Blacklist = Get-Content -Path $BlacklistTxt | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }
        foreach ($app in $Blacklist) {
            $app = $app.Trim()
            Write-Output " -> Garantindo bloqueio para: $app"
            & $wingetPath pin add --id $app --accept-source-agreements --force | Out-Null
        }
    }

    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Aplicando atualizacoes (ESCOPO USUARIO)..."

# -----------------------------ALTERAÇÃO GUSTAVO--------------------------- 

$wingetOutput = & $wingetPath upgrade --all --silent --accept-package-agreements --accept-source-agreements --scope user --include-unknown 2>&1

# salva log bruto
$wingetOutput | Out-File "$LogDir\Winget_UserUpdate_raw.log" -Append

# gerar log bonitinho
$StatusFile = "$LogDir\status_user.txt"
$Data = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$failures = $wingetOutput | Where-Object { $_ -match "Failed|Error" }

$realFailures = @()

foreach ($line in $failures) {
    $ignore = $false
    foreach ($app in $Blacklist) {
        if ($line -match $app) {
            $ignore = $true
            break
        }
    }
    if (-not $ignore) {
        $realFailures += $line
    }
}

if ($realFailures.Count -eq 0) {
    "OK | $Data | Atualizacao USER concluida" | Out-File $StatusFile -Force
} else {
    $msg = $realFailures -join " | "
    "ERRO | $Data | USER Falhas: $msg" | Out-File $StatusFile -Force
}

# -----------------------------FIM ALTERAÇÃO GUSTAVO----------------------- 
    
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0 -or $exitCode -eq 2316632065) {
        Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] STATUS: SUCESSO."
    } else {
        Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] STATUS: Codigo $exitCode retornado."
    }
} else {
    Write-Error "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ERRO: Winget nao encontrado no perfil."
}
Write-Output "----------------------------------------------------------------"
Stop-Transcript
'@
Set-Content -Path $ScriptUserPath -Value $ScriptUserContent -Encoding UTF8

# ==============================================================================
# 4. Gerando o Lancador VBS (Modo Furtivo)
# ==============================================================================
$VbsPath = "$BaseDir\CLMS-RunHidden.vbs"
$VbsContent = @'
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
' SCRIPT:      CLMS-RunHidden.vbs
' PROPRIEDADE: CLMS Tecnologia | clms.com.br
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
CreateObject("WScript.Shell").Run "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\CLMS\SCRIPTz\Winget\CLMS-Update-WingetUserApps.ps1", 0, False
'@
Set-Content -Path $VbsPath -Value $VbsContent -Encoding Ascii

# ==============================================================================
# 5. Registro das Tarefas Agendadas
# ==============================================================================
Write-Output "Registrando Tarefas no Agendador do Windows..."

Unregister-ScheduledTask -TaskName "CLMS_Winget_Update" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "CLMS_Winget_UserApps" -Confirm:$false -ErrorAction SilentlyContinue

$DescSys = "========================================`r`nCLMS Tecnologia | clms.com.br`r`n========================================`r`nAtualizacao automatizada de aplicativos globais (Escopo de Maquina) via Winget.`r`nExecutado com privilegios de SYSTEM.`r`nLogs salvos em: C:\CLMS\SCRIPTz\Winget\Logs"
$DescUsr = "========================================`r`nCLMS Tecnologia | clms.com.br`r`n========================================`r`nAtualizacao automatizada de aplicativos do perfil (Store/Terminal) via Winget.`r`nExecutado de forma furtiva no escopo do usuario ativo.`r`nLogs salvos em: C:\CLMS\SCRIPTz\Winget\Logs"

$AcaoSys = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File C:\CLMS\SCRIPTz\Winget\CLMS-Update-WingetApps.ps1"
$GatilhoSys = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Wednesday -At 12:00PM
$ContaSys = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$ConfigsSys = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName "CLMS_Winget_Update" -Action $AcaoSys -Trigger $GatilhoSys -Principal $ContaSys -Settings $ConfigsSys -Description $DescSys -Force | Out-Null

$AcaoUsr = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$VbsPath`""
$GatilhoUsr = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Tuesday -At 12:00PM
$ContaUsr = New-ScheduledTaskPrincipal -GroupId $NomeGrupo -RunLevel Limited
$ConfigsUsr = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName "CLMS_Winget_UserApps" -Action $AcaoUsr -Trigger $GatilhoUsr -Principal $ContaUsr -Settings $ConfigsUsr -Description $DescUsr -Force | Out-Null

# ==============================================================================
# 6. Salvando o Hash apos Deploy bem-sucedido
# ==============================================================================
if ($CurrentScript -and (Test-Path -Path $CurrentScript)) {
    Set-Content -Path $HashFile -Value $CurrentHash -Force
}

Write-Output "[OK] Implantacao concluida com sucesso! Tarefas, descricoes e Hash aplicados."
