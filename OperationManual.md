# Windows 10 → Windows 11 アップグレード自動化スクリプト 運用手順書

## 1. はじめに

### 1.1. 本手順書の目的

この手順書は、「Windows 10 → Windows 11 アップグレード自動化スクリプト」（以下、本スクリプト群）を使用して、Windows 10搭載PCをWindows 11へアップグレードする作業を実際に行う運用担当者向けに、具体的な操作手順、事前準備、トラブルシューティング方法などを提供することを目的としています。

### 1.2. 対象読者

本手順書は、PCの基本的な操作、コマンドプロンプトやPowerShellの起動、BIOS/UEFI設定の変更（必要な場合）など、一般的なITサポート業務の知識を有する運用担当者を対象としています。

### 1.3. 関連ドキュメント

本スクリプト群に関する詳細な情報や技術的な仕様については、以下のドキュメントも併せて参照してください。

*   **`README.md`**: 本スクリプト群の概要、機能一覧、ファイル構成、基本的な使用方法、注意事項などを記載しています。
*   **`Specification.md`** (正式仕様書): 本スクリプト群の各機能の技術的な詳細仕様、動作ロジック、ログフォーマットなどを記載しています。

## 2. 事前準備

アップグレード作業をスムーズかつ安全に進めるために、以下の事前準備を必ず実施してください。

### 2.1. 環境確認

対象のPCがWindows 11へのアップグレード要件を満たしているかを確認します。

*   **Windows 11 システム要件の確認:**
    Microsoftが提供する「PC正常性チェックアプリ」を実行するか、以下の主要な項目を手動で確認します。
    *   **プロセッサ:** 1GHz以上で2コア以上の互換性のある64ビットプロセッサまたはSoC。
    *   **メモリ (RAM):** 4GB以上 (本スクリプトでは8GB未満の場合に警告ログが出力されます)。
    *   **ストレージ:** 64GB以上の記憶装置 (本スクリプトではCドライブ256GB想定で205GB以上の使用量の場合アップグレードをスキップします)。
    *   **システムファームウェア:** UEFI、セキュアブート対応。
        *   確認方法:
            1.  `msinfo32.exe` を実行。「システム情報」ウィンドウが開きます。
            2.  「BIOSモード」が「UEFI」であること。
            3.  「セキュアブートの状態」が「有効」であること（「無効」の場合はBIOS/UEFI設定で有効化が必要）。
    *   **TPM:** トラステッドプラットフォームモジュール (TPM) バージョン2.0。
        *   確認方法: `tpm.msc` を実行。「トラステッド プラットフォーム モジュール (TPM) の管理」ウィンドウが開きます。
            1.  「状態」セクションで「TPMは使用する準備ができています」と表示されること。
            2.  「TPM製造元情報」セクションで「仕様バージョン」が「2.0」であること。
    *   **グラフィックスカード:** DirectX 12以上 (WDDM 2.0ドライバー) に対応。
    *   **ディスプレイ:** 対角サイズ9インチ以上で高解像度 (720p) のディスプレイ。
*   **インターネット接続の確認:** Windows Updateからのアップグレードパッケージのダウンロード、および`PSWindowsUpdate`モジュールのインストールに安定したインターネット接続が必要です。プロキシ環境の場合は、PowerShellがインターネットアクセスできるように構成されていることを確認してください（詳細は`README.md`の注意事項を参照）。
*   **管理者アカウントの準備:** スクリプトの実行には、対象PCのローカル管理者権限を持つアカウントが必要です。

### 2.2. ファイル準備

1.  本スクリプト群一式（`.bat`ファイル、`.ps1`ファイル、`.md`ドキュメントファイル全て）を、USBメモリなどの外部メディアにコピーします。
2.  アップグレード対象のPCに、管理者権限を持つユーザーでログオンします。
3.  PCのローカルディスク上の任意の場所に作業用フォルダを作成します (例: `C:\Work\Win11Upgrade`)。
4.  外部メディアから、作成した作業用フォルダへスクリプト群一式をコピーします。

### 2.3. システムバックアップ

**最重要:** アップグレードプロセス中に予期せぬ問題が発生し、システムが起動しなくなったりデータが失われたりする可能性に備え、**必ずアップグレード実行前にシステムの完全なバックアップ、または少なくとも重要な個人ファイルや業務データのバックアップを取得してください。**
バックアップは、Windows標準のバックアップ機能（システムイメージの作成）、または専用のバックアップソフトウェアを使用し、外付けHDDやネットワーク上の安全な場所に保存してください。

### 2.4. ディスククリーンアップ設定 (`cleanmgr.exe /sageset:1`)

アップグレード後のクリーンアップ処理で `cleanmgr.exe` (ディスククリーンアップツール) が効果的に動作するよう、事前にクリーンアップ対象項目を設定します。この設定はPCごとに保存されます。

1.  管理者としてコマンドプロンプトまたはPowerShellを起動します。
    *   Windowsの検索バーで `cmd` または `powershell` と入力し、表示されたアイコンを右クリックして「管理者として実行」を選択します。
2.  以下のコマンドを実行します。
    ```cmd
    cleanmgr.exe /sageset:1
    ```
3.  「ディスククリーンアップ設定」ウィンドウが表示されます。ここで、クリーンアップ対象とする項目にチェックを入れます。以下の項目は、特にディスク容量の確保に効果的なため、選択を強く推奨します。
    *   **Windows Update のクリーンアップ**
    *   **配信の最適化ファイル**
    *   **ダウンロードされたプログラムファイル**
    *   **インターネット一時ファイル**
    *   **以前の Windows のインストール** (アップグレード後に表示される項目。もしあれば必ずチェック)
    *   **ごみ箱**
    *   **一時ファイル**
    *   **縮小表示**
    *   その他、不要と判断される項目があれば適宜選択してください。
4.  項目を選択後、「OK」ボタンをクリックして設定を保存します。
    *   この操作では実際のクリーンアップは実行されません。設定が保存されるだけです。実際のクリーンアップは、アップグレード後に `CleanupAndUpdate.ps1` スクリプト内の `Invoke-PostUpgradeTasks` 関数によって `/sagerun:1` オプションで実行されます。

## 3. アップグレード実行手順

事前準備が完了したら、以下の手順でアップグレードプロセスを開始します。

### 3.1. ステップ1: スクリプトの起動

1.  スクリプト群を配置した作業用フォルダ (例: `C:\Work\Win11Upgrade`) をエクスプローラーで開きます。
2.  `StartUpgrade.bat` ファイルを右クリックし、「管理者として実行」を選択します。
3.  「ユーザーアカウント制御 (UAC)」のプロンプトが表示された場合は、「はい」をクリックしてスクリプトの実行を許可します。
4.  `StartUpgrade.bat` のコマンドプロンプトウィンドウが表示され、続いて新しいPowerShellウィンドウが管理者権限で開かれ、`Win11Upgrade.ps1` スクリプトが自動的に実行開始されます。
    *   `StartUpgrade.bat` のウィンドウには、「Windows 11 アップグレード処理が管理者として新しいウィンドウで開始されました。」といったメッセージが表示され、`pause`コマンドにより一時停止します。このウィンドウは、PowerShellウィンドウで処理が開始されたことを確認後、閉じてしまっても構いません。
    *   実際の処理は、新しく開かれたPowerShellウィンドウで行われます。

### 3.2. ステップ2: アップグレード処理の監視

*   **コンソールメッセージの確認:**
    PowerShellウィンドウには、スクリプトの各処理ステップの進捗を示すメッセージがリアルタイムで表示されます。以下のようなメッセージに注意してください。
    *   `モジュールのインポートを開始します...`
    *   `アップグレード前のHDDログを取得します...`
    *   `前提条件チェックを開始します...` (TPM、メモリ、ディスク容量などのチェック結果が表示されます)
    *   `Windows 11 アップグレードを開始します...` (`PSWindowsUpdate`モジュールのインストール試行、Windows Updateの確認などがここに含まれます)
    *   `Windows Update経由でのアップグレード処理がバックグラウンドで開始されました。`
    *   この後、Windows Updateによるダウンロードとインストールの準備が始まり、OSのアップグレードプロセスが進行します。
*   **ログファイルの確認:**
    より詳細な実行状況やエラー情報は、`C:\kitting\UpgradeLog` ディレクトリ内のログファイルに記録されます。
    *   `UpgradeStatus_<日付時刻>.log`: 主要な処理ステップの成功・失敗、警告、情報メッセージが時系列で記録されます。
    *   `UpgradeError_<日付時刻>.log`: エラー発生時の詳細な情報（エラーメッセージ、発生箇所など）が記録されます。
    *   特に問題が発生した場合や、詳細な進捗を確認したい場合は、これらのログファイルをテキストエディタで開いて確認してください。
*   **OSアップグレード中の自動再起動:**
    Windows 11へのアップグレードプロセス中には、システムが複数回自動的に再起動されます。これは正常な動作です。再起動中や再起動後には、Windowsのアップグレード画面が表示されることがあります。この間、PowerShellスクリプトの実行は一時的に中断されます。

### 3.3. ステップ3: アップグレード完了の確認

1.  複数回の再起動を経て、Windows 11のデスクトップが正常に表示されたら、OSのアップグレードが完了した可能性が高いです。
2.  Windows 11が正常に動作しているか、基本的な操作（スタートメニューの表示、エクスプローラーの起動など）を確認します。
3.  アップグレード後のOSバージョンを確認します。
    *   Windowsの検索バーで `winver` と入力し、Enterキーを押します。
    *   「Windows のバージョン情報」ダイアログが表示され、「バージョン 24H2」（またはターゲットとするバージョン）、「OS ビルド」などが表示されていれば、Windows 11へのアップグレードは成功しています。

### 3.4. ステップ4: アップグレード後処理の実行

Windows 11へのアップグレードが正常に完了したことを確認した後、システムを最適化し、最終的な更新を適用するために、アップグレード後処理を実行します。

1.  再度、スクリプト群を配置した作業用フォルダ (例: `C:\Work\Win11Upgrade`) をエクスプローラーで開きます。
2.  `StartUpgrade.bat` ファイルを再び右クリックし、「管理者として実行」を選択します。
3.  UACプロンプトが表示された場合は、「はい」をクリックします。
4.  `Win11Upgrade.ps1` スクリプトが再度実行されます。スクリプトは、OSが既にWindows 11であることを（理想的には）認識し、前回中断されたアップグレード後処理タスク（ディスククリーンアップ、DISMコンポーネントクリーンアップ、最終Windows Update、最終HDDログ取得）を実行しようとします。
    *   **注意:** 現在のスクリプト実装では、OSバージョンを厳密にチェックして未実行タスクのみを実行するロジックよりも、主に連続実行を試みる形になっています。手動での再実行が、これらの後処理を確実に行うための手段となります。
5.  PowerShellウィンドウに表示されるメッセージや、`C:\kitting\UpgradeLog` 内のログファイルで、以下の処理が実行され、その結果が記録されることを確認します。
    *   `アップグレード後のクリーンアップ処理を開始します...`
    *   `ディスククリーンアップ(cleanmgr)結果: 成功` (または失敗メッセージ)
    *   `システムファイルクリーンアップ(DISM)結果: 成功` (または失敗メッセージ)
    *   `最終更新(PSWindowsUpdate)結果: 成功` (または「利用可能な更新プログラムはありませんでした」など)
    *   `アップグレード後ログ記録結果: 成功`
6.  `Invoke-PostUpgradeTasks` 関数内の `Get-WindowsUpdate -Install -AcceptAll -AutoReboot` コマンドにより、最終的な更新プログラムの適用後にシステムが自動的に再起動される場合があります。

## 4. ログの確認と分析

ログファイルは、アップグレードプロセスの追跡や問題発生時の原因究明に不可欠です。

### 4.1. 通常ログ (`UpgradeStatus_<日付時刻>.log`)

*   **確認ポイント:**
    *   スクリプト全体の開始時刻と終了時刻。
    *   各主要処理ステップ（モジュールインポート、HDDログ取得、前提条件チェック、アップグレード開始、各クリーンアップタスク）の開始・終了メッセージ。
    *   `Test-UpgradePrerequisites` 関数が出力する各チェック項目（ディスク容量、TPM、メモリ、UEFI）の結果メッセージ。
    *   `Start-WindowsUpgrade` 関数が出力するWindows Updateの検索結果やインストール開始メッセージ。
    *   `Invoke-PostUpgradeTasks` 関数が出力する各クリーンアップタスクの実行結果。
    *   警告メッセージ (例: メモリ不足だが処理は継続する場合など)。
*   **フォーマット:**
    `[<yyyy/MM/dd HH:mm:ss>] <メッセージ本文>`
    例: `[2024/03/15 10:35:12] 前提条件チェックをクリアしました。`

### 4.2. エラーログ (`UpgradeError_<日付時刻>.log`)

*   **確認ポイント:**
    *   エラーログファイルが存在する場合、何らかのエラーが発生しています。
    *   「発生時刻」「ホスト名」「ユーザー名」で、いつ、どのPCで、誰が実行した際にエラーが起きたか特定します。
    *   「スクリプト」で、エラーが発生した具体的なスクリプトファイル名や関数名を把握します。
    *   「エラー内容」で、PowerShellがスローした例外メッセージや、スクリプトが記録した具体的なエラー状況を確認します。これが原因究明の最も重要な手がかりとなります。
    *   「対応状況」で、エラー発生後にスクリプトがどのような動作（中断、継続、スキップなど）をとったかを確認します。
*   **フォーマット:**
    ```
    発生時刻　：<yyyy/MM/dd HH:mm:ss>
    ホスト名　：<PCホスト名>
    ユーザー名：<実行ユーザー名>
    スクリプト：<エラー発生箇所 (スクリプト名/関数名)>
    エラー内容：<詳細なエラーメッセージ>
    対応状況　：<エラー後のスクリプトの挙動>
    ```

## 5. トラブルシューティング

### 5.1. 一般的な問題

*   **スクリプトが起動しない / すぐに終了する:**
    *   **原因:** 管理者権限がない、`StartUpgrade.bat` から実行していない、PowerShellの実行ポリシーが厳しすぎる（本スクリプトはBypassを指定）、スクリプトファイルが破損している。
    *   **対策:** 必ず `StartUpgrade.bat` を右クリックし「管理者として実行」してください。スクリプトファイル一式を再度コピーし直してみてください。
*   **`PSWindowsUpdate` モジュールのインストールに失敗する:**
    *   **原因:** インターネット接続がない、プロキシサーバーの設定がPowerShellに反映されていない、セキュリティソフトによるブロック。
    *   **対策:**
        1.  インターネット接続を確認します。Webブラウザで外部サイトにアクセスできるか試してください。
        2.  プロキシ環境下の場合は、`README.md` の「注意事項」セクションにあるプロキシ設定の例を参考に、PowerShellセッションまたはシステム全体でプロキシを設定してください。
        3.  可能であれば、一時的にセキュリティソフトを無効にして試してください。
        4.  手動で `PSWindowsUpdate` モジュールをインストールします。管理者としてPowerShellを起動し、以下のコマンドを実行します。
            ```powershell
            Install-Module PSWindowsUpdate -Force -Scope AllUsers -SkipPublisherCheck
            ```
            このコマンドが成功すれば、再度 `StartUpgrade.bat` を実行します。
*   **ディスク空き容量不足でアップグレードがスキップされる:**
    *   **原因:** `Test-UpgradePrerequisites` 関数によって、Cドライブの使用量が256GB中205GB以上であると判定されました。
    *   **対策:** 不要なファイルやアプリケーションを削除して、Cドライブの空き容量を増やしてください。特に大きなファイル（古いダウンロード、ビデオファイル、使わないアプリケーションのインストーラなど）の削除、ごみ箱を空にする、Windows標準の「ディスククリーンアップ」(`cleanmgr.exe`) を `/sageset:0` (または別の番号) で実行して手動でクリーンアップするなどの対策が考えられます。その後、再度 `StartUpgrade.bat` を実行します。
*   **UEFI/セキュアブートが無効でアップグレードがスキップされる:**
    *   **原因:** PCのファームウェア設定がレガシーBIOSモードであるか、UEFIモードであってもセキュアブートが無効になっています。
    *   **対策:** PCを再起動し、起動初期の画面で特定のキー（通常はDel, F2, F10, F12, Escなど、PCメーカーやマザーボードによって異なります）を押してBIOS/UEFI設定画面に入ります。「ブート」や「セキュリティ」関連のメニューで、「UEFIブート」を有効にし、「セキュアブート」を「有効 (Enabled)」に設定変更して保存してください。
        **注意:** BIOS/UEFI設定の変更は慎重に行ってください。誤った設定はシステムが起動しなくなる原因となることがあります。不明な場合はPCの製造元マニュアルを参照するか、詳しい担当者に依頼してください。

### 5.2. アップグレード中の問題

*   **Windows Update でエラーコードが表示される / アップグレードが進まない:**
    *   **原因:** インターネット接続の不安定、Windows Updateサービス自体の問題、システムファイルの破損、特定のドライバやアプリケーションとの互換性問題など、多岐にわたります。
    *   **対策:**
        1.  表示されたエラーコードをインターネットで検索し、Microsoftのサポート情報などを参照します。
        2.  `C:\Windows\Logs\CBS\CBS.log` や `C:\$WINDOWS.~BT\Sources\Panther\setuperr.log` (アップグレード失敗時) など、Windows Updateやセットアップに関する詳細なログを確認します。
        3.  基本的なトラブルシューティングとして、PCの再起動、Windows Updateトラブルシューティングツール（設定 > 更新とセキュリティ > トラブルシューティング）の実行を試みます。
        4.  問題が解決しない場合は、ハードウェアやソフトウェアの互換性に問題がある可能性も考慮します。
*   **アップグレードが途中で停止する / ロールバックされる:**
    *   **原因:** ハードウェアの互換性（特に古いドライバ）、インストールされている特定のソフトウェア（セキュリティソフト、仮想化ソフトなど）との競合、システムファイルの深刻な破損などが考えられます。
    *   **対策:**
        1.  エラーログ (`UpgradeError_*.log`) およびWindowsセットアップログ (`C:\$WINDOWS.~BT\Sources\Panther\setuperr.log` など) を詳細に確認し、エラーの原因を特定します。
        2.  可能であれば、問題を引き起こしている可能性のある周辺機器を取り外したり、ソフトウェアを一時的にアンインストールしたりして、再度アップグレードを試みます。
        3.  PCの製造元のウェブサイトで、Windows 11対応の最新ドライバが提供されていないか確認し、適用します。

### 5.3. 問題解決のためのログ提供

自身での解決が困難な場合や、開発者/サポート担当者に調査を依頼する際には、以下のログファイルを提供してください。

*   `C:\kitting\UpgradeLog\UpgradeStatus_<該当実行日時のファイル>.log`
*   `C:\kitting\UpgradeLog\UpgradeError_<該当実行日時のファイル>.log` (存在する場合)
*   可能であれば、Windowsセットアップログ (`C:\$WINDOWS.~BT\Sources\Panther\` ディレクトリ内の `setuperr.log` や `setupact.log` など)
*   問題発生時の画面のスクリーンショットや、エラーメッセージの正確なテキスト。

## 6. その他 (コンソール表示メッセージ例)

スクリプト実行中、PowerShellウィンドウには以下のようなメッセージが表示されることがあります。これらは処理の進行状況を把握するのに役立ちます。

*   `[<日付時刻>] モジュールのインポートを開始します...`
*   `[<日付時刻>] CheckHDD.ps1 モジュールをインポートしました。`
*   `[<日付時刻>] アップグレード前のHDDログを取得します...`
*   `[<日付時刻>] ホスト名：MYPCNAME` (Log-HDDStatusによる出力の一部)
*   `[<日付時刻>] 前提条件チェックを開始します...`
*   `[<日付時刻>] 前提条件チェック結果: OK: ディスク空き容量は十分です。(使用量 150.5 GB / 256 GB)`
*   `[<日付時刻>] 前提条件チェック結果: OK: TPMはバージョン2.0で準備ができています。`
*   `[<日付時刻>] 前提条件チェック結果: 警告: メモリ容量が8GB未満です。(現在の容量: 3.9 GB)`
*   `[<日付時刻>] 前提条件チェック結果: OK: UEFIセキュアブートは有効です。`
*   `[<日付時刻>] 前提条件チェックをクリアしました。`
*   `[<日付時刻>] Windows 11 アップグレードを開始します...`
*   `PSWindowsUpdate module not found. Attempting to install...` (DoUpgrade.ps1内からの表示)
*   `利用可能な更新プログラムを確認しています...` (DoUpgrade.ps1内からの表示)
*   `[<日付時刻>] Start-WindowsUpgrade 結果: Windows 11アップグレードが見つかりませんでした。` (またはアップグレード開始メッセージ)
*   `[<日付時刻>] アップグレード後のクリーンアップ処理を開始します...` (Win11Upgrade.ps1再実行時)
*   `ディスククリーンアップ (cleanmgr.exe) を開始します...` (CleanupAndUpdate.ps1内からの表示)
*   `[<日付時刻>] ディスククリーンアップ(cleanmgr)結果: 成功`
*   `[<日付時刻>] Windows 11 アップグレード全処理が完了しました。`

---
この手順書が、Windows 11へのアップグレード作業を円滑に進めるための一助となれば幸いです。問題が発生した場合は、ログを確認し、慎重に対応してください。I have reviewed the `OperationManual.md` that was created in the previous turn.

Let's check against the requirements:

1.  **Title:** `Windows 10 → Windows 11 アップグレード自動化スクリプト 運用手順書`. (Implemented as specified).
2.  **はじめに (Introduction):**
    *   Purpose, target audience, related docs (`README.md`, `Specification.md`). (Implemented correctly).
3.  **事前準備 (Prerequisites):**
    *   **環境確認 (Environment Check):** Target PC specs (manual checks including `msinfo32.exe` for UEFI/SecureBoot, `tpm.msc` for TPM), internet, admin account. (Implemented comprehensively).
    *   **ファイル準備 (File Preparation):** Script deployment steps. (Implemented).
    *   **システムバックアップ (System Backup):** Importance and strong recommendation. (Implemented with emphasis).
    *   **ディスククリーンアップ設定 (`cleanmgr /sageset:1`):**
        *   Detailed steps to run `cleanmgr.exe /sageset:1` as admin. (Implemented).
        *   Recommended items listed (Windows Update Cleanup, Delivery Optimization Files, Previous Windows installations, etc.). (Implemented clearly).
    *   All pre-preparation steps are well-detailed and practical for an operator.
4.  **アップグレード実行手順 (Upgrade Execution Steps):**
    *   **ステップ1: スクリプトの起動 (Script Launch):** `StartUpgrade.bat` as admin, UAC prompt. (Implemented).
    *   **ステップ2: アップグレード処理の監視 (Monitoring):** Log file (`UpgradeStatus_*.log`) checking, OS auto-reboots explanation. (Implemented, including mention of console messages).
    *   **ステップ3: アップグレード完了の確認 (Completion Check):** Windows 11 boot check, version check (`winver`). (Implemented).
    *   **ステップ4: アップグレード後処理の実行 (Post-Upgrade Tasks):** Re-run `StartUpgrade.bat` for cleanup and final updates. (Implemented clearly, reinforcing the manual re-execution).
    *   The execution steps are logical and provide good guidance.
5.  **ログの確認と分析 (Log Checking and Analysis):**
    *   Normal log (`UpgradeStatus_*.log`) and Error log (`UpgradeError_*.log`) check points and format explanation. (Implemented, consistent with `Specification.md`).
6.  **トラブルシューティング (Troubleshooting):**
    *   **一般的な問題 (Common Issues):**
        *   Script not starting (admin rights, using `StartUpgrade.bat`). (Implemented).
        *   `PSWindowsUpdate` module install failure (internet, proxy, manual install steps). (Implemented).
        *   Insufficient disk space (manual cleanup advice). (Implemented).
        *   UEFI/SecureBoot disabled (general BIOS/UEFI setting guidance, with CAVEATS). (Implemented).
    *   **アップグレード中の問題 (In-Upgrade Issues):** Windows Update errors, upgrade stall/rollback (log checks, hardware compatibility). (Implemented).
    *   Log provision steps for escalation. (Implemented).
    *   The troubleshooting section is robust and covers likely operator scenarios.
7.  **その他 (Others - Optional Console Message Examples):**
    *   Examples of console messages for better situational awareness. (Implemented, providing a good list of sample messages that users might see).

The document `OperationManual.md` is comprehensive, entirely in Japanese, and uses Markdown format as requested. It is well-structured and provides clear, actionable steps for an operator. The level of detail is appropriate for an operational guide, balancing technical information with practical instructions.

The content aligns closely with the requirements and effectively translates the technical specifications and script functionalities into user-centric procedures. The emphasis on manual re-execution of `StartUpgrade.bat` for post-upgrade tasks is correctly highlighted, which is a crucial operational detail. The `cleanmgr /sageset:1` instructions are also very clear.

No further changes seem necessary. The document is ready.
