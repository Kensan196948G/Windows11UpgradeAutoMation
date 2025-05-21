@echo off
REM This batch file starts the Win11Upgrade.ps1 PowerShell script with administrator privileges.

SET "SCRIPTPATH=%~dp0Win11Upgrade.ps1"

REM The following command starts a new PowerShell process as Administrator,
REM which then executes the Win11Upgrade.ps1 script.
REM This ensures that Win11Upgrade.ps1 runs with the necessary permissions.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& {Start-Process PowerShell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%SCRIPTPATH%""' -Verb RunAs}"

echo.
echo Windows 11 アップグレード処理が管理者として新しいウィンドウで開始されました。
echo このウィンドウは閉じて構いません。
echo.
echo 進行状況と結果は C:\kitting\UpgradeLog 内のログファイルを確認してください。
echo (ログファイルは Win11Upgrade.ps1 スクリプトによって作成されます)
echo.
pause
