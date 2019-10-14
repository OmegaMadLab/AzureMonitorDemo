$LogFiles = Get-ChildItem -Path "C:\LogFiles"

foreach ($logFile in $logFiles) {
    Write-Output "Analyzing $($logFile.Name)..."
    if($logFile.LastWriteTime -lt (Get-Date).AddDays(-30)) {
        $logFile | Remove-Item -force -confirm:$false
        Write-Output "$($logFile.Name) removed."
    }
}