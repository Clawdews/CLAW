param([ValidateSet('Install', 'Status', 'Disable')][string]$Action = 'Status')
$ErrorActionPreference = 'Stop'
$taskName = 'CLAW Luarmor Notes Publisher'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$publisher = Join-Path $repoRoot 'tools\luarmor-publisher.mjs'
$stateDir = Join-Path $repoRoot '.tools\luarmor-publisher'
if ($Action -eq 'Status') {
    Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Select-Object TaskName, State
    & node $publisher --status
    exit
}
if ($Action -eq 'Disable') {
    Disable-ScheduledTask -TaskName $taskName | Out-Null
    Write-Output 'Automatic notes uploads are disabled. Existing Luarmor scripts and keys are unchanged.'
    exit
}
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    throw 'A publisher task already exists. Inspect it before replacing it.'
}
if (-not (Test-Path -LiteralPath (Join-Path $stateDir 'api-key.dpapi'))) { throw 'Configure the protected API key first.' }
$nodePath = (Get-Command node.exe).Source
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 2)
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
$command = "& '" + $nodePath.Replace("'", "''") + "' '" + $publisher.Replace("'", "''") + "' --once"
$taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -Command "' + $command + '"') -WorkingDirectory $repoRoot
Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings -Description 'Publish checked CLAW Notes releases from the private control-beta branch to its existing Luarmor script.' | Out-Null
[IO.File]::WriteAllText((Join-Path $stateDir 'enabled'), 'enabled')
Write-Output 'Installed: checks every two minutes while this Windows user is signed in. The PC is not woken from sleep.'
