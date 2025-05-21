#Requires -RunAsAdministrator

# --- Initial Setup and Global Variables ---
$ErrorActionPreference = "Stop" # Stop on terminating errors
$OutputEncoding = [System.Text.Encoding]::UTF8

$Global:LogDirectory = "C:\kitting\UpgradeLog"
$Global:CurrentTimestamp = Get-Date -Format "yyyyMMddHHmm"
$Global:StatusLogPath = Join-Path -Path $Global:LogDirectory -ChildPath "UpgradeStatus_$($Global:CurrentTimestamp).log"
$Global:ErrorLogPath = Join-Path -Path $Global:LogDirectory -ChildPath "UpgradeError_$($Global:CurrentTimestamp).log"

try {
    if (-not (Test-Path -Path $Global:LogDirectory)) {
        New-Item -ItemType Directory -Path $Global:LogDirectory -Force -ErrorAction Stop | Out-Null
    }
}
catch {
    Write-Error "致命的エラー: ログディレクトリ '$($Global:LogDirectory)' の作成に失敗しました。スクリプトを終了します。Error: $($_.Exception.Message)"
    exit 1
}

# --- Log Functions ---
function Write-StatusLog {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    $logEntry = "[$(Get-Date -Format 'yyyy/MM/dd HH:mm:ss')] $Message"
    Write-Host $logEntry
    try {
        Add-Content -Path $Global:StatusLogPath -Value $logEntry -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Warning "警告: ステータスログファイル '$($Global:StatusLogPath)' への書き込みに失敗しました。Error: $($_.Exception.Message)"
    }
}

function Write-ErrorLog {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ErrorMessage,
        [string]$Script = "Win11Upgrade.ps1", # Default to this script
        [string]$Action = "未定義"
    )
    $timestamp = Get-Date -Format 'yyyy/MM/dd HH:mm:ss'
    $hostname = $env:COMPUTERNAME
    $username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    $logEntry = @"
発生時刻　：$timestamp
ホスト名　：$hostname
ユーザー名：$username
スクリプト：$Script
エラー内容：$ErrorMessage
対応状況　：$Action
"@
    $formattedMessage = "エラーログ記録: スクリプト '$Script', エラー '$ErrorMessage', 対応 '$Action'"
    Write-Host $formattedMessage -ForegroundColor Red
    try {
        Add-Content -Path $Global:ErrorLogPath -Value ($logEntry + [System.Environment]::NewLine) -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Warning "警告: エラーログファイル '$($Global:ErrorLogPath)' への書き込みに失敗しました。Error: $($_.Exception.Message)"
    }
}

# --- Module Imports ---
Write-StatusLog "モジュールのインポートを開始します..."
try {
    Import-Module "$PSScriptRoot\CheckHDD.ps1" -Force -ErrorAction Stop
    Write-StatusLog "CheckHDD.ps1 モジュールをインポートしました。"
}
catch {
    Write-ErrorLog -ErrorMessage "CheckHDD.ps1 モジュールのインポートに失敗しました。Error: $($_.Exception.Message)" -Action "中断"
    Write-StatusLog "スクリプトを終了します。"
    exit 1
}

try {
    Import-Module "$PSScriptRoot\DoUpgrade.ps1" -Force -ErrorAction Stop
    Write-StatusLog "DoUpgrade.ps1 モジュールをインポートしました。"
}
catch {
    Write-ErrorLog -ErrorMessage "DoUpgrade.ps1 モジュールのインポートに失敗しました。Error: $($_.Exception.Message)" -Action "中断"
    Write-StatusLog "スクリプトを終了します。"
    exit 1
}

try {
    Import-Module "$PSScriptRoot\CleanupAndUpdate.ps1" -Force -ErrorAction Stop
    Write-StatusLog "CleanupAndUpdate.ps1 モジュールをインポートしました。"
}
catch {
    Write-ErrorLog -ErrorMessage "CleanupAndUpdate.ps1 モジュールのインポートに失敗しました。Error: $($_.Exception.Message)" -Action "中断"
    Write-StatusLog "スクリプトを終了します。"
    exit 1
}
Write-StatusLog "全てのモジュールのインポートが完了しました。"


# --- Main Processing Flow ---
Write-StatusLog "Windows 11 アップグレード処理を開始します。"

# アップグレード前 HDDログ取得
Write-StatusLog "アップグレード前のHDDログを取得します..."
try {
    Log-HDDStatus -LogFilePath $Global:StatusLogPath -Header "アップグレード前 HDD状態" -ErrorAction Stop
    Write-StatusLog "アップグレード前のHDDログを取得しました。"
}
catch {
    Write-ErrorLog -ErrorMessage "アップグレード前のHDDログ取得に失敗しました。Error: $($_.Exception.Message)" -Script "Log-HDDStatus (CheckHDD.ps1)" -Action "継続 (致命的ではない)"
    # Not exiting here as it's a logging step, but it is an error.
}

# 前提条件チェック
Write-StatusLog "前提条件チェックを開始します..."
$preCheckResult = $null
try {
    $preCheckResult = Test-UpgradePrerequisites -ErrorAction Stop
    if ($preCheckResult -and $preCheckResult.Messages) {
        $preCheckResult.Messages | ForEach-Object { Write-StatusLog "前提条件チェック結果: $_" }
    } else {
         Write-StatusLog "前提条件チェック Test-UpgradePrerequisites から予期せぬ応答がありました。"
         # This case might not be necessary if Test-UpgradePrerequisites always returns a valid object.
    }

    if (-not $preCheckResult.CanUpgrade) {
        Write-ErrorLog -ErrorMessage "前提条件チェックに失敗しました。アップグレードをスキップします。" -Script "Test-UpgradePrerequisites (DoUpgrade.ps1)" -Action "スキップして中断"
        Write-StatusLog "アップグレード処理を中断しました。"
        exit 1
    } else {
        Write-StatusLog "前提条件チェックをクリアしました。"
    }
}
catch {
    Write-ErrorLog -ErrorMessage "前提条件チェックの実行中に予期せぬエラーが発生しました。Error: $($_.Exception.Message)" -Script "Test-UpgradePrerequisites (DoUpgrade.ps1)" -Action "中断"
    Write-StatusLog "アップグレード処理を中断しました。"
    exit 1
}

# アップグレード実行
Write-StatusLog "Windows 11 アップグレードを開始します..."
$upgradeResult = $null
try {
    $upgradeResult = Start-WindowsUpgrade -ErrorAction Stop
    Write-StatusLog "Start-WindowsUpgrade 結果: $($upgradeResult.Message)"

    if (-not $upgradeResult.UpgradeStarted) {
        Write-ErrorLog -ErrorMessage "アップグレードの開始に失敗しました: $($upgradeResult.Message)" -Script "Start-WindowsUpgrade (DoUpgrade.ps1)" -Action "中断"
        Write-StatusLog "アップグレード処理を中断しました。"
        exit 1
    } else {
        Write-StatusLog "Windows Update経由でのアップグレード処理がバックグラウンドで開始されました。"
        Write-StatusLog "完了までには複数回の再起動を含む長時間がかかる場合があります。"
        Write-StatusLog "アップグレードが完了し、OSが正常に起動した後、システムが自動的にアップグレード後のクリーンアップ処理を試みます (このスクリプトの連続実行を想定)。"
        Write-StatusLog "もしクリーンアップが自動実行されない場合は、再度このスクリプトを手動実行してください。"
        # As per requirements, this script will attempt to continue to post-upgrade tasks.
        # In a real-world scenario, a reboot would likely occur here, and the script would terminate.
        # The post-upgrade tasks would then need to be run upon next login, possibly via a scheduled task or run-once registry key.
        # For this exercise, we proceed directly.
    }
}
catch {
    Write-ErrorLog -ErrorMessage "Windows 11 アップグレードの開始処理中に予期せぬエラーが発生しました。Error: $($_.Exception.Message)" -Script "Start-WindowsUpgrade (DoUpgrade.ps1)" -Action "中断"
    Write-StatusLog "アップグレード処理を中断しました。"
    exit 1
}

# アップグレード後処理
Write-StatusLog "アップグレード後のクリーンアップ処理を開始します..."
$postUpgradeTasksResult = $null
try {
    $postUpgradeTasksResult = Invoke-PostUpgradeTasks -LogFilePath $Global:StatusLogPath -LogHeader "アップグレード後 HDD状態およびクリーンアップ" -ErrorAction Stop
    
    Write-StatusLog "ディスククリーンアップ(cleanmgr)結果: $($postUpgradeTasksResult.CleanMgrStatus)"
    if ($postUpgradeTasksResult.CleanMgrStatus -like "*失敗*") {
        Write-ErrorLog -ErrorMessage "ディスククリーンアップ(cleanmgr)に失敗しました。Status: $($postUpgradeTasksResult.CleanMgrStatus)" -Script "Invoke-PostUpgradeTasks (CleanupAndUpdate.ps1)" -Action "継続"
    }

    Write-StatusLog "システムファイルクリーンアップ(DISM)結果: $($postUpgradeTasksResult.DismStatus)"
    if ($postUpgradeTasksResult.DismStatus -like "*失敗*") {
        Write-ErrorLog -ErrorMessage "システムファイルクリーンアップ(DISM)に失敗しました。Status: $($postUpgradeTasksResult.DismStatus)" -Script "Invoke-PostUpgradeTasks (CleanupAndUpdate.ps1)" -Action "継続"
    }
    
    Write-StatusLog "最終更新(PSWindowsUpdate)結果: $($postUpgradeTasksResult.FinalUpdateStatus)"
    if ($postUpgradeTasksResult.FinalUpdateStatus -like "*失敗*") {
        Write-ErrorLog -ErrorMessage "最終更新(PSWindowsUpdate)に失敗しました。Status: $($postUpgradeTasksResult.FinalUpdateStatus)" -Script "Invoke-PostUpgradeTasks (CleanupAndUpdate.ps1)" -Action "継続"
    }

    Write-StatusLog "アップグレード後ログ記録結果: $($postUpgradeTasksResult.PostUpgradeLogStatus)"
    if ($postUpgradeTasksResult.PostUpgradeLogStatus -like "*失敗*") {
        Write-ErrorLog -ErrorMessage "アップグレード後ログ記録に失敗しました。Status: $($postUpgradeTasksResult.PostUpgradeLogStatus)" -Script "Invoke-PostUpgradeTasks (CleanupAndUpdate.ps1)" -Action "継続"
    }
    Write-StatusLog "アップグレード後のクリーンアップ処理が完了しました。"
}
catch {
    Write-ErrorLog -ErrorMessage "アップグレード後の処理中に予期せぬエラーが発生しました。Error: $($_.Exception.Message)" -Script "Invoke-PostUpgradeTasks (CleanupAndUpdate.ps1)" -Action "中断"
    Write-StatusLog "アップグレード後の処理を中断しました。"
    # Depending on where the error occurred, some tasks might have completed.
    # Not exiting with 1 here, as the main upgrade might have finished.
}

Write-StatusLog "Windows 11 アップグレード全処理が完了しました。"
exit 0
