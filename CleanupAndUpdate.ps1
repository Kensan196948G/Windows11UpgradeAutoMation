# This PowerShell script performs cleanup and updates after the upgrade.

function Invoke-PostUpgradeTasks {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory=$true)]
        [string]$LogFilePath,

        [Parameter(Mandatory=$true)]
        [string]$LogHeader
    )

    $cleanMgrStatus = "失敗: 初期化されていません"
    $dismStatus = "失敗: 初期化されていません"
    $finalUpdateStatus = "失敗: 初期化されていません"
    $postUpgradeLogStatus = "失敗: 初期化されていません"

    # 1. Disk Cleanup (cleanmgr.exe)
    Write-Host "ディスククリーンアップ (cleanmgr.exe) を開始します..."
    try {
        $process = Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:1 /verylowdisk" -Wait -PassThru -ErrorAction Stop
        if ($process.ExitCode -eq 0) {
            $cleanMgrStatus = "成功"
            Write-Host "cleanmgr.exe が正常に完了しました。"
        } else {
            $cleanMgrStatus = "失敗: cleanmgr.exe がエラーコード $($process.ExitCode) で終了しました。"
            Write-Warning $cleanMgrStatus
        }
    }
    catch {
        $cleanMgrStatus = "失敗: cleanmgr.exe の実行中にエラーが発生しました。Error: $($_.Exception.Message)"
        Write-Warning $cleanMgrStatus
    }

    # 2. System File Cleanup (Dism.exe)
    Write-Host "システムファイルのクリーンアップ (Dism.exe) を開始します..."
    try {
        $process = Start-Process -FilePath "Dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /ResetBase" -Wait -PassThru -ErrorAction Stop
        if ($process.ExitCode -eq 0) {
            $dismStatus = "成功"
            Write-Host "Dism.exe が正常に完了しました。"
        } 
        elseif ($process.ExitCode -eq 3010) { # ERROR_SUCCESS_REBOOT_REQUIRED
            $dismStatus = "成功 (再起動保留中)" # Or just "成功" if a pending reboot is fine
            Write-Host "Dism.exe が正常に完了しましたが、再起動が必要です。(ExitCode: 3010)"
        }
        else {
            $dismStatus = "失敗: Dism.exe がエラーコード $($process.ExitCode) で終了しました。"
            Write-Warning $dismStatus
        }
    }
    catch {
        $dismStatus = "失敗: Dism.exe の実行中にエラーが発生しました。Error: $($_.Exception.Message)"
        Write-Warning $dismStatus
    }

    # 3. Final Windows Update and Reboot
    Write-Host "最終的なWindows Updateの実行と再起動を開始します..."
    try {
        Import-Module PSWindowsUpdate -Force -ErrorAction Stop
        Write-Host "PSWindowsUpdate モジュールをインポートしました。"
        
        # Check if any updates are actually installed and if a reboot is pending
        # Get-WindowsUpdate itself doesn't tell us if a reboot will occur, Install-WindowsUpdate does.
        # We assume that if Install-WindowsUpdate -AutoReboot runs without error, it has succeeded in its task.
        Get-WindowsUpdate -Install -AcceptAll -AutoReboot -ErrorAction Stop
        # If -AutoReboot is triggered and the script is still running, it means the reboot is scheduled but not immediate for the script.
        # Or, no updates were found that required a reboot.
        # The nature of -AutoReboot is that the script might terminate here if a reboot is immediate.
        $finalUpdateStatus = "成功 (最終更新プロセスが実行され、必要に応じて再起動がスケジュールされました)"
        Write-Host $finalUpdateStatus
    }
    catch {
        if ($_.Exception.Message -match "No updates found") {
            $finalUpdateStatus = "成功 (利用可能な更新プログラムはありませんでした)"
            Write-Host $finalUpdateStatus
        } 
        elseif ($_.Exception.ToString() -match "PendingRebootException" -or ($_.Exception.InnerException -and $_.Exception.InnerException.ToString() -match "PendingRebootException") ) {
             # This specific exception type might be thrown by PSWindowsUpdate if a reboot is pending from its operations
            $finalUpdateStatus = "再起動がトリガーされました (PSWindowsUpdateにより検出)"
            Write-Host $finalUpdateStatus
        }
        else {
            $finalUpdateStatus = "失敗: Windows Updateの実行中にエラーが発生しました。Error: $($_.Exception.Message)"
            Write-Warning $finalUpdateStatus
        }
    }

    # 4. Post-Upgrade HDD Log
    Write-Host "アップグレード後のHDD使用状況ログ取得を開始します..."
    try {
        # Try to find CheckHDD.ps1 in the same directory as this script first.
        $checkHddPath = Join-Path -Path $PSScriptRoot -ChildPath "CheckHDD.ps1"
        if (-not (Test-Path $checkHddPath)) {
            # If not found, try to load it as if it's in a module path (though less likely for .ps1 files)
            # This assumes CheckHDD.ps1 acts like a module script.
            Write-Warning "CheckHDD.ps1 not found at $checkHddPath. Attempting to import by name."
            Import-Module CheckHDD -Force -ErrorAction Stop # Fallback, might not work if not in PSModulePath
        } else {
            Import-Module $checkHddPath -Force -ErrorAction Stop
        }
        
        Log-HDDStatus -LogFilePath $LogFilePath -Header $LogHeader -ErrorAction Stop
        $postUpgradeLogStatus = "成功"
        Write-Host "アップグレード後のHDD使用状況ログを記録しました。"
    }
    catch {
        $postUpgradeLogStatus = "失敗: アップグレード後のHDD使用状況ログ取得中にエラーが発生しました。Error: $($_.Exception.Message)"
        Write-Warning $postUpgradeLogStatus
    }

    return [PSCustomObject]@{
        CleanMgrStatus       = $cleanMgrStatus
        DismStatus           = $dismStatus
        FinalUpdateStatus    = $finalUpdateStatus
        PostUpgradeLogStatus = $postUpgradeLogStatus
    }
}

Export-ModuleMember -Function Invoke-PostUpgradeTasks

# Placeholder for old script content if any
# Write-Host "Performing cleanup and updates..."
# Remove-Item "C:\Windows\Temp\*" -Recurse -Force
# Install-Module PSWindowsUpdate -Force
# Get-WindowsUpdate -Install -AcceptAll
# Write-Host "Cleanup and updates completed."
# exit 0
