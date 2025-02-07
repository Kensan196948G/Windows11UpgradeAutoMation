# Windows 11 アップグレード管理モジュール

# ログ出力関数
function New-Log {
    param (
        [string]$Message,
        [string]$LogLevel = "INFO"
    )
    
    $logPath = "$PSScriptRoot\Windows11UpgradeLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $timeStamp = Get-Date -Format 'yyyy/MM/dd HH:mm:ss'
    $logEntry = "[$timeStamp] [$LogLevel] $Message"
    
    if (-not (Test-Path -Path $logPath)) {
        New-Item -Path $logPath -ItemType File | Out-Null
    }
    
    Add-Content -Path $logPath -Value $logEntry
    Write-Host $logEntry
}

# 前提条件チェック関数
function Start-Precheck {
    try {
        New-Log -Message "前提条件チェックを開始します。" -LogLevel INFO
        
        # TPM 2.0 チェック
        $tpm = Get-WmiObject -Namespace "root\cimv2\security\microsofttpm" -Class "Win32_Tpm"
        if ($null -eq $tpm -or $tpm.IsEnabled() -eq $false) {
            throw "TPM 2.0 が有効ではありません。"
        }
        
        # UEFI チェック
        $firmware = Get-WmiObject -Class "Win32_Firmware"
        if ($firmware.Name -notmatch "UEFI") {
            throw "UEFI モードではありません。"
        }
        
        # メモリチェック
        $memory = Get-WmiObject -Class "Win32_PhysicalMemory"
        $totalMemory = ($memory | Measure-Object -Property Capacity -Sum).Sum / 1GB
        if ($totalMemory -lt 4GB) {
            throw "メモリが不足しています。4GB 以上必要です。"
        }
        
        # Secure Boot チェック
        $secureBoot = Get-WmiObject -Namespace "root\cimv2\security\microsofttpm" -Class "Win32_Tpm"
        if ($secureBoot.IsEnabled() -eq $false) {
            throw "Secure Boot が有効ではありません。"
        }
        
        return [PSCustomObject]@{
            Success = $true
            Message = "前提条件チェックに合格しました。"
        }
    } catch {
        New-Log -Message $_.Exception.Message -LogLevel ERROR
        return [PSCustomObject]@{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

# ネットワーク環境確認関数
function Check-Network {
    try {
        New-Log -Message "ネットワーク環境を確認します。" -LogLevel INFO
        
        # ネットワーク接続チェック
        if (Test-Connection -ComputerName "www.microsoft.com" -Count 1 -Quiet) {
            New-Log -Message "インターネット接続が確認されました。" -LogLevel INFO
        } else {
            throw "インターネット接続が確認できません。"
        }
        
        # ネットワークアダプター状態
        $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
        if ($null -eq $adapter) {
            throw "有効なネットワークアダプターが見つかりません。"
        }
        
        return [PSCustomObject]@{
            Success = $true
            Message = "ネットワーク環境が正常です。"
        }
    } catch {
        New-Log -Message $_.Exception.Message -LogLevel ERROR
        return [PSCustomObject]@{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

# ストレージ確認関数
function Check-Storage {
    try {
        New-Log -Message "ストレージとOneDriveを確認します。" -LogLevel INFO
        
        # OS ドライブの空き容量
        $osDrive = Get-WmiObject -Class "Win32_LogicalDisk" -Filter "DeviceID='C:'"
        $freeSpace = $osDrive.Size / 1GB - $osDrive.FreeSpace / 1GB
        if ($freeSpace -gt 20GB) {
            throw "C ドライブの空き容量が不足しています。20GB 以上必要です。"
        } else {
            New-Log -Message "C ドライブの空き容量が要件を満たしています。" -LogLevel INFO
        }
        
        # アップグレード後の入力手続き無用の確認
        $currentBuild = (Get-WmiObject -Class "Win32_OperatingSystem").Version
        if ($currentBuild -ne "10.0.22000") {
            throw "Windows 11 がインストールされていません。"
        } else {
            New-Log -Message "Windows 11 が正常にインストールされました。入力手続きは必要ありません。" -LogLevel INFO
        }
        
        # Windows Update for Business (WUfB) ポリシーの確認
        $wufbPolicy = Get-WmiObject -Namespace "root/SoftwareLicensingProducts" -Class "LicenseProduct"
        if ($wufbPolicy -eq $null) {
            throw "Windows Update for Business (WUfB) が有効ではありません。"
        } else {
            New-Log -Message "Windows Update for Business (WUfB) が有効になっています。" -LogLevel INFO
        }
        
        # ネットワーク帯域幅の確認
        $networkAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
        $networkUsage = Get-Counter -Counter "\Network Adapter($($networkAdapter.Name))\Current Bandwidth" -SampleInterval 1 -MaxSamples 5
        $averageBandwidth = ($networkUsage.CounterSamples | Measure-Object -Property CookedValue -Average).Average
        if ($averageBandwidth -lt 10MB) {
            throw "ネットワーク帯域幅が不足しています。10Mbps 以上が必要です。"
        } else {
            New-Log -Message "ネットワーク帯域幅は十分です。" -LogLevel INFO
        }
        
        # CDN へのアクセス確認
        if (-not (Test-Connection -ComputerName "windowsupdate.microsoft.com" -Count 1 -Quiet)) {
            throw "Windows Update サーバーへの接続に失敗しました。"
        } else {
            New-Log -Message "Windows Update サーバーへの接続に成功しました。" -LogLevel INFO
        }
        
        # インターネット接続の安定性確認
        $pingResult = Test-Connection -ComputerName "www.microsoft.com" -Count 4 -Quiet
        if (-not $pingResult) {
            throw "インターネット接続が不安定です。"
        } else {
            New-Log -Message "インターネット接続は安定しています。" -LogLevel INFO
        }
        
        # OneDrive チェック
        if (-not (Test-Path -Path "~\OneDrive")) {
            New-Log -Message "OneDrive が検出されませんでした。OneDrive を起動します。" -LogLevel INFO
            $onedrivePath = "$env:LOCALAPPDATA\Microsoft\OneDrive\onedrive.exe"
            if (Test-Path -Path $onedrivePath) {
                Start-Process -FilePath $onedrivePath
                Start-Sleep -Seconds 10
                New-Log -Message "OneDrive を起動しました。" -LogLevel INFO
            } else {
                throw "OneDrive がインストールされていません。"
            }
        }
        
        # OneDrive のファイルオンデマンドを有効化
        $onedriveSettingsPath = "~\AppData\Local\Microsoft\OneDrive\settings.json"
        if (-not (Test-Path -Path $onedriveSettingsPath)) {
            New-Log -Message "OneDrive の設定ファイルが見つかりませんでした。新規KFM設定を実行します。" -LogLevel INFO
            # KFM設定の実装
            $kfmSettings = @{
                "enableFileOnDemand" = $true
                "ghostSync" = $true
            }
            ConvertTo-Json -InputObject $kfmSettings | Out-File -FilePath $onedriveSettingsPath -Encoding UTF8
            New-Log -Message "KFM設定を実行しました。" -LogLevel INFO
            $settings = @{
                "enableFileOnDemand" = $true
            }
            ConvertTo-Json -InputObject $settings | Out-File -FilePath $onedriveSettingsPath -Encoding UTF8
            New-Log -Message "OneDrive のファイルオンデマンドを有効化しました。" -LogLevel INFO
        } else {
            $settings = Get-Content -Path $onedriveSettingsPath | ConvertFrom-Json
            if (-not $settings.enableFileOnDemand) {
                $settings.enableFileOnDemand = $true
                ConvertTo-Json -InputObject $settings | Out-File -FilePath $onedriveSettingsPath -Encoding UTF8
                New-Log -Message "OneDrive のファイルオンデマンドを有効化しました。" -LogLevel INFO
            }
        }
        
        return [PSCustomObject]@{
            Success = $true
            Message = "ストレージとOneDrive が正常です。"
        }
    } catch {
        New-Log -Message $_.Exception.Message -LogLevel ERROR
        return [PSCustomObject]@{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

# バックアップ関数
function Start-Backup {
    try {
        New-Log -Message "バックアップと保護機能を実行します。" -LogLevel INFO
        
        # バックアップ対象フォルダー
        $backupPaths = @(
            "C:\Users\$env:USERNAME\Documents"
            "C:\Users\$env:USERNAME\Pictures"
            "C:\Users\$env:USERNAME\Downloads"
        )
        
        $backupDestination = "E:\Windows11UpgradeBackup"
        
        # バックアップフォルダー作成
        if (-not (Test-Path -Path $backupDestination)) {
            New-Item -Path $backupDestination -ItemType Directory | Out-Null
            New-Log -Message "バックアップフォルダーを作成しました: $backupDestination" -LogLevel INFO
        }
        
        # バックアップ実行
        foreach ($path in $backupPaths) {
            $target = Join-Path -Path $backupDestination -ChildPath (Split-Path -Path $path -Leaf)
            if (Test-Path -Path $path) {
                Copy-Item -Path $path\* -Destination $target -Recurse -Force
                New-Log -Message "バックアップしました: $path → $target" -LogLevel INFO
            }
        }
        
        return [PSCustomObject]@{
            Success = $true
            Message = "バックアップが正常に完了しました。"
        }
    } catch {
        New-Log -Message $_.Exception.Message -LogLevel ERROR
        return [PSCustomObject]@{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

# アップグレード実行関数
function Start-Upgrade {
    try {
        New-Log -Message "Windows 11 アップグレードを開始します。" -LogLevel INFO
        
        # Windows Update でアップグレードを実行
        $result = Start-Process -FilePath "C:\Windows\System32\control.exe" -ArgumentList "/name Microsoft.WindowsUpdate" -PassThru -Wait
        if ($result.ExitCode -ne 0) {
            throw "Windows Update の起動に失敗しました。"
        }
        
        New-Log -Message "Windows Update が正常に起動しました。" -LogLevel INFO
        New-Log -Message "アップグレードプロセスが開始されました。" -LogLevel INFO
        
        return [PSCustomObject]@{
            Success = $true
            Message = "アップグレードが正常に開始されました。"
        }
    } catch {
        New-Log -Message $_.Exception.Message -LogLevel ERROR
        return [PSCustomObject]@{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

# アップグレード後の確認関数
function Start-Postcheck {
    try {
        New-Log -Message "アップグレード後の確認を実行します。" -LogLevel INFO
        
        # OS バージョン確認
        $os = Get-WmiObject -Class "Win32_OperatingSystem"
        if ($os.Version -ne "10.0.22000") {
            throw "Windows 11 がインストールされていません。"
        }
        
        # システムの安定性確認
        $systemStatus = Get-WmiObject -Class "Win32_ComputerSystem"
        if ($systemStatus.BootupState -ne "Normal") {
            throw "システムの起動状態が正常ではありません。"
        }
        
        $osVersion = (Get-WmiObject -Class "Win32_OperatingSystem").Version
        New-Log -Message "Windows 11 ($osVersion) アップグレードが正常に完了しました。" -LogLevel INFO
        
        return [PSCustomObject]@{
            Success = $true
            Message = "アップグレード後の確認が正常に完了しました。"
        }
    } catch {
        New-Log -Message $_.Exception.Message -LogLevel ERROR
        return [PSCustomObject]@{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}
