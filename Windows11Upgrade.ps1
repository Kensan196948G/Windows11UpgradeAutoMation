#!/powershell

# Windows 11 アップグレード管理スクリプト

# モジュール化された関数を読み込む
Import-Module -Name .\Windows11Upgrade.psm1

# スクリプト開始
try {
    # 管理者権限で実行されているか確認
    if (-not (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "管理者権限で実行してください。"
    }

    # 前提条件チェック
    Write-Host "前提条件チェックを開始します。"
    $precheckResult = Start-Precheck
    if (-not $precheckResult.Success) {
        throw "前提条件が満たされていません。詳細: $($precheckResult.Message)"
    }

    # ネットワーク環境確認
    Write-Host "ネットワーク環境を確認します。"
    $networkResult = Check-Network
    if (-not $networkResult.Success) {
        throw "ネットワーク環境に問題があります。詳細: $($networkResult.Message)"
    }

    # ストレージ確認とOneDrive設定
    Write-Host "ストレージとOneDriveを確認します。"
    $storageResult = Check-Storage
    if (-not $storageResult.Success) {
        throw "ストレージに問題があります。詳細: $($storageResult.Message)"
    }

    # バックアップと保護機能
    Write-Host "バックアップと保護機能を実行します。"
    $backupResult = Start-Backup
    if (-not $backupResult.Success) {
        throw "バックアップに失敗しました。詳細: $($backupResult.Message)"
    }

    # アップグレードプロセス管理
    Write-Host "アップグレードを開始します。"
    $upgradeResult = Start-Upgrade
    if (-not $upgradeResult.Success) {
        throw "アップグレードに失敗しました。詳細: $($upgradeResult.Message)"
    }

    # アップグレード後の確認
    Write-Host "アップグレード後の確認を実行します。"
    $postcheckResult = Start-Postcheck
    if (-not $postcheckResult.Success) {
        throw "アップグレード後の確認でエラーが発生しました。詳細: $($postcheckResult.Message)"
    }

    Write-Host "Windows 11 アップグレードが正常に完了しました。"
} catch {
    Write-Host "エラーが発生しました: $($Error[0].Message)"
    Throw
}
