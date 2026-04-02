$pythonPath = "C:\Python312\python.exe"

if (!(Test-Path $pythonPath)) {

    $url = "https://www.python.org/ftp/python/3.12.2/python-3.12.2-amd64.exe"
    $installer = "$env:TEMP\python_installer.exe"

    Invoke-WebRequest $url -OutFile $installer

    Start-Process $installer -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 TargetDir=C:\Python312" -Wait

}
