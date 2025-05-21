# This PowerShell script performs the Windows 11 upgrade.
# It includes functions to test upgrade prerequisites and start the upgrade.

function Test-UpgradePrerequisites {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $canUpgrade = $true
    $messages = [System.Collections.Generic.List[string]]::new()

    # --- 1. Disk Space Check ---
    try {
        $drive = Get-PSDrive C -ErrorAction Stop
        $assumedTotalCapacityGB = 256 # As per requirement
        $usedCapacityBytes = $drive.Used
        $usedCapacityGB = [Math]::Round($usedCapacityBytes / 1GB, 1)
        $thresholdGB = 205
        
        if ($usedCapacityGB -ge $thresholdGB) {
            $canUpgrade = $false
            $messages.Add("エラー: ディスク空き容量が不足しています。現在の使用量 $usedCapacityGB GB / $assumedTotalCapacityGB GB (しきい値 $thresholdGB GB)。アップグレードをスキップします。")
        } else {
            $messages.Add("OK: ディスク空き容量は十分です。(使用量 $usedCapacityGB GB / $assumedTotalCapacityGB GB)")
        }
    }
    catch {
        $canUpgrade = $false 
        $messages.Add("エラー: Cドライブのディスク空き容量の確認に失敗しました。Error: $($_.Exception.Message)。アップグレードをスキップします。")
    }

    # --- 2. TPM Check ---
    try {
        $tpm = Get-Tpm -ErrorAction Stop
        if ($tpm.TpmPresent -and $tpm.TpmReady -and $tpm.SpecificationVersion -eq "2.0") {
            $messages.Add("OK: TPMはバージョン2.0で準備ができています。")
        } else {
            $tpmVersion = if ($tpm.SpecificationVersion) { $tpm.SpecificationVersion } else { "N/A" }
            $tpmPresentStatus = if ($tpm.TpmPresent) { "True" } else { "False" }
            $tpmReadyStatus = if ($tpm.TpmReady) { "True" } else { "False" }
            $messages.Add("警告: TPMの準備ができていないか、バージョンが2.0ではありません。(存在: $tpmPresentStatus, 準備完了: $tpmReadyStatus, バージョン: $tpmVersion)")
        }
    }
    catch {
        if ($_.Exception.Message -like "*Get-Tpm*is not recognized*") {
             $messages.Add("警告: Get-Tpm コマンドレットが見つかりません。TPM状態を確認できません。")
        } elseif ($_.Exception.Message -like "*A compatible Trusted Platform Module (TPM) Security Device cannot be found on this computer.*" `
                -or $_.FullyQualifiedErrorId -eq "Microsoft.Tpm.Commands.GetTpmCommand.NoTpmFound") {
            $messages.Add("警告: TPMが存在しません、または準備ができていません。")
        }
        else {
            $messages.Add("警告: TPM状態の確認中にエラーが発生しました。Error: $($_.Exception.Message)")
        }
    }

    # --- 3. Memory Check ---
    try {
        $totalMemoryKB = Get-ComputerInfo -Property OsTotalVisibleMemorySize -ErrorAction Stop | Select-Object -ExpandProperty OsTotalVisibleMemorySize
        $totalMemoryGB = [Math]::Round($totalMemoryKB / 1MB, 1) 
        $requiredMemoryKB = 8 * 1024 * 1024 

        if ($totalMemoryKB -lt $requiredMemoryKB) {
            $messages.Add("警告: メモリ容量が8GB未満です。(現在の容量: $totalMemoryGB GB)")
        } else {
            $messages.Add("OK: メモリ容量は十分です。($totalMemoryGB GB)")
        }
    }
    catch {
        $messages.Add("警告: メモリ容量の確認中にエラーが発生しました。Error: $($_.Exception.Message)")
    }

    # --- 4. UEFI/SecureBoot Check ---
    try {
        if (Confirm-SecureBootUEFI -ErrorAction Stop) {
            $messages.Add("OK: UEFIセキュアブートは有効です。")
        } else {
            $canUpgrade = $false
            $messages.Add("エラー: UEFI環境ですが、セキュアブートが無効です。アップグレードをスキップします。")
        }
    }
    catch {
        $canUpgrade = $false
        if ($_.Exception.Message -like "*Confirm-SecureBootUEFI*is not recognized*") {
            $messages.Add("エラー: Confirm-SecureBootUEFI コマンドレットが見つかりません。UEFI/セキュアブート状態を確認できません。アップグレードをスキップします。")
        } elseif ($_.Exception.Message -like "*Cmdlet not supported on this platform*") { 
            $messages.Add("エラー: プラットフォームがUEFIをサポートしていないか、セキュアブートが無効です。アップグレードをスキップします。")
        } else {
            $messages.Add("エラー: UEFI/セキュアブート状態の確認中に予期せぬエラーが発生しました。Error: $($_.Exception.Message)。アップグレードをスキップします。")
        }
    }

    return [PSCustomObject]@{
        CanUpgrade = $canUpgrade
        Messages   = $messages.ToArray()
    }
}

function Start-WindowsUpgrade {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $upgradeStarted = $false
    $message = ""

    # 1. PSWindowsUpdate Module Management
    try {
        Write-Verbose "Checking for PSWindowsUpdate module..."
        $module = Get-Module -ListAvailable PSWindowsUpdate
        if (-not $module) {
            Write-Host "PSWindowsUpdate module not found. Attempting to install..."
            try {
                Install-Module PSWindowsUpdate -Force -Scope AllUsers -Confirm:$false -SkipPublisherCheck -ErrorAction Stop
                Write-Host "PSWindowsUpdate module installed successfully."
                $module = Get-Module -ListAvailable PSWindowsUpdate # Re-check after install
                if (-not $module) {
                    throw "PSWindowsUpdate module installed but still not found by Get-Module."
                }
            }
            catch {
                $message = "PSWindowsUpdateモジュールのインストールに失敗しました。Error: $($_.Exception.Message)"
                return [PSCustomObject]@{ UpgradeStarted = $false; Message = $message }
            }
        }
        
        try {
            Import-Module PSWindowsUpdate -Force -ErrorAction Stop
            Write-Verbose "PSWindowsUpdate module imported successfully."
        }
        catch {
            $message = "PSWindowsUpdateモジュールのインポートに失敗しました。Error: $($_.Exception.Message)"
            return [PSCustomObject]@{ UpgradeStarted = $false; Message = $message }
        }
    }
    catch { # Catch issues with Get-Module itself or other unexpected errors
        $message = "PSWindowsUpdateモジュールの管理中に予期せぬエラーが発生しました。Error: $($_.Exception.Message)"
        return [PSCustomObject]@{ UpgradeStarted = $false; Message = $message }
    }

    # 2. Upgrade Search and Execution
    try {
        Write-Host "利用可能な更新プログラムを確認しています..."
        # Ensure PSWindowsUpdate cmdlets are available after import
        if (-not (Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue)) {
            $message = "Get-WindowsUpdate コマンドレットが見つかりません。PSWindowsUpdateモジュールが正しくロードされませんでした。"
            return [PSCustomObject]@{ UpgradeStarted = $false; Message = $message }
        }

        $availableUpdates = Get-WindowsUpdate -WindowsUpdate -ErrorAction Stop
        
        # Filter for Windows 11 upgrade
        # Keywords can be localized, so this might need adjustment for non-English systems
        # Forcing English UI for commands is generally safer if possible, but PSWindowsUpdate might not fully support it.
        $win11Upgrade = $availableUpdates | Where-Object {
            ($_.Title -like "*Windows 11*") -and 
            ( ($_.Title -like "*upgrade*") -or ($_.Title -like "*feature update*") -or ($_.Description -like "*upgrade*") -or ($_.Description -like "*feature update*") )
        } | Select-Object -First 1

        if ($win11Upgrade) {
            Write-Host "Windows 11 アップグレードが見つかりました: $($win11Upgrade.Title)"
            try {
                # Prefer KBArticleID if available and not empty, otherwise use Title
                if ($win11Upgrade.KBArticleID -and $win11Upgrade.KBArticleID.Trim() -ne "") {
                    Write-Host "アップグレードをKBArticleIDで開始します: $($win11Upgrade.KBArticleID)"
                    Install-WindowsUpdate -KBArticleID $win11Upgrade.KBArticleID -AcceptAll -ErrorAction Stop
                } else {
                    Write-Host "アップグレードをTitleで開始します: $($win11Upgrade.Title)"
                    Install-WindowsUpdate -Title $win11Upgrade.Title -AcceptAll -ErrorAction Stop
                }
                $upgradeStarted = $true
                $message = "Windows 11アップグレードを開始しました: $($win11Upgrade.Title)"
            }
            catch {
                $message = "Windows 11アップグレードのインストールに失敗しました。Title: $($win11Upgrade.Title), Error: $($_.Exception.Message)"
            }
        } else {
            $message = "Windows 11アップグレードが見つかりませんでした。"
        }
    }
    catch {
        $message = "Windows Updateの確認または実行中にエラーが発生しました。Error: $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        UpgradeStarted = $upgradeStarted
        Message        = $message
    }
}

Export-ModuleMember -Function Test-UpgradePrerequisites, Start-WindowsUpgrade

# Placeholder for actual upgrade commands - this script now primarily provides Test-UpgradePrerequisites
# Write-Host "Performing Windows 11 upgrade..."
# Start-Process "C:\Path\To\Windows11\setup.exe" -ArgumentList "/auto upgrade" -Wait
# Write-Host "Upgrade completed."
# exit 0
