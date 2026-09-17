@echo off
rem ============================================================
rem  ACB-Trace.cmd  -  ACB デバッグトレース管理 & ログ収集
rem
rem  Usage:
rem    ACB-Trace.cmd --enable             trace設定を settings.json に追加
rem    ACB-Trace.cmd --disable            trace設定を settings.json から削除
rem    ACB-Trace.cmd --status             現在の trace 設定を表示
rem    ACB-Trace.cmd --collect            ログを logs\ フォルダに収集
rem    ACB-Trace.cmd --enable --collect   有効化 + 既存ログ収集（同時指定可）
rem    ACB-Trace.cmd --disable --collect  ログ収集してから無効化（同時指定可）
rem
rem  Options:
rem    --vscode <PATH>  settings.json の場所（省略時は自動検出）
rem    --acb <PATH>     ACB ホームの場所（省略時は mule.homeDirectory → デフォルト）
rem    --mask           収集時にトークンをマスク（--collect と組み合わせる）
rem ============================================================

if not defined _LOGGING (
    setlocal enabledelayedexpansion
    set "LOGDIR=%CD%\logs"
    if not exist "!LOGDIR!" mkdir "!LOGDIR!"
    for /f "tokens=1-3 delims=/ " %%a in ('date /t') do set "LOGDATE=%%c%%a%%b"
    for /f "tokens=1-2 delims=: " %%a in ('time /t') do set "LOGTIME=%%a%%b"
    set "LOGFILE=!LOGDIR!\ACB-Trace_!LOGDATE!_!LOGTIME!.log"
    set "_LOGGING=1"
    cmd /c ""%~f0" %*" 2>&1 | powershell -NoProfile -Command "$input | Tee-Object -FilePath '!LOGFILE!'; Write-Host ''; Write-Host '[Log saved to !LOGFILE!]'"
    endlocal
    exit /b
)

setlocal enabledelayedexpansion

set "COMMON=%~dp0_Common.cmd"
if not exist "!COMMON!" (
    echo [ERROR] _Common.cmd が見つかりません。
    echo         ACB-Trace.cmd と _Common.cmd は同じフォルダに置いてください。
    exit /b 2
)

set "OP="
set "DO_COLLECT="
set "DO_MASK="
set "VSCODE_SETTINGS="
set "ACB_HOME_OVERRIDE="

:parse
if "%~1"=="" goto :init
if /i "%~1"=="--enable"  ( set "OP=enable"    & shift & goto :parse )
if /i "%~1"=="--disable" ( set "OP=disable"   & shift & goto :parse )
if /i "%~1"=="--status"  ( set "OP=status"    & shift & goto :parse )
if /i "%~1"=="--collect" ( set "DO_COLLECT=1" & shift & goto :parse )
if /i "%~1"=="--mask"    ( set "DO_MASK=1"    & shift & goto :parse )
if /i "%~1"=="--vscode"  ( set "VSCODE_SETTINGS=%~2"      & shift & shift & goto :parse )
if /i "%~1"=="--acb"     ( set "ACB_HOME_OVERRIDE=%~2"   & shift & shift & goto :parse )
shift
goto :parse

:init
call "!COMMON!" :find_vscode
if not defined VSCODE_SETTINGS (
    echo [ERROR] VS Code settings.json が見つかりません。--vscode で指定してください。
    exit /b 1
)

if /i "!OP!"=="enable"  goto :do_enable
if /i "!OP!"=="disable" goto :do_disable
if /i "!OP!"=="status"  goto :do_status
if defined DO_COLLECT   goto :do_collect

echo.
echo  Usage: ACB-Trace.cmd [--enable ^| --disable ^| --status] [--collect] [--mask] [--vscode ^<PATH^>]
echo.
echo    --enable    trace設定を追加  ^(VS Code 再起動後に有効^)
echo    --disable   trace設定を削除  ^(VS Code 再起動後に無効^)
echo    --status    現在の trace 設定値を表示
echo    --collect   ログを logs\ に収集
echo    --mask      収集時にトークンをマスク  ^(--collect と組み合わせる^)
echo    --acb ^<PATH^>   ACB ホームを指定  ^(省略時は mule.homeDirectory を参照^)
echo.
echo  推奨手順:
echo    1. ACB-Trace.cmd --enable      ^(問題再現の前に有効化^)
echo    2. VS Code を再起動
echo    3. 問題を再現する
echo    4. ACB-Trace.cmd --collect --mask  ^(ログを収集^)
echo    5. ACB-Trace.cmd --disable     ^(収集後に無効化^)
exit /b 0

rem ============================================================
:do_enable
echo.
echo ============================================================
echo  [trace 有効化]  settings.json に trace 設定を追加します
echo  対象: !VSCODE_SETTINGS!
echo ============================================================
powershell -NoProfile -Command "$f='!VSCODE_SETTINGS!'; $s=Get-Content $f -Raw | ConvertFrom-Json; $s | Add-Member -NotePropertyName 'mule.logging.level' -NotePropertyValue 'trace' -Force; $s | Add-Member -NotePropertyName 'mule.lsp.trace.server' -NotePropertyValue 'verbose' -Force; $s | Add-Member -NotePropertyName 'mule.application.logging.level' -NotePropertyValue 'trace' -Force; $s | ConvertTo-Json -Depth 10 | Set-Content $f -Encoding UTF8; Write-Host '  追加: mule.logging.level             = trace'; Write-Host '  追加: mule.lsp.trace.server          = verbose'; Write-Host '  追加: mule.application.logging.level = trace'"
echo.
echo  VS Code を再起動後、問題を再現してから --collect を実行してください。
if not defined DO_COLLECT exit /b 0
echo.
echo  [注意] trace ログは VS Code 再起動後に出力されます。
echo          再起動前の既存ログを収集します。
goto :do_collect

rem ============================================================
:do_disable
if defined DO_COLLECT goto :do_collect_then_disable
echo.
echo ============================================================
echo  [trace 無効化]  settings.json から trace 設定を削除します
echo  対象: !VSCODE_SETTINGS!
echo ============================================================
powershell -NoProfile -Command "$f='!VSCODE_SETTINGS!'; $s=Get-Content $f -Raw | ConvertFrom-Json; @('mule.logging.level','mule.lsp.trace.server','mule.application.logging.level') | ForEach-Object { $s.PSObject.Properties.Remove($_) }; $s | ConvertTo-Json -Depth 10 | Set-Content $f -Encoding UTF8; Write-Host '  削除: mule.logging.level'; Write-Host '  削除: mule.lsp.trace.server'; Write-Host '  削除: mule.application.logging.level'"
echo.
echo  VS Code を再起動してください。
exit /b 0

:do_collect_then_disable
rem --disable --collect の場合: 先にログ収集してから設定を削除する
call :do_collect
echo.
echo ============================================================
echo  [trace 無効化]  settings.json から trace 設定を削除します
echo  対象: !VSCODE_SETTINGS!
echo ============================================================
powershell -NoProfile -Command "$f='!VSCODE_SETTINGS!'; $s=Get-Content $f -Raw | ConvertFrom-Json; @('mule.logging.level','mule.lsp.trace.server','mule.application.logging.level') | ForEach-Object { $s.PSObject.Properties.Remove($_) }; $s | ConvertTo-Json -Depth 10 | Set-Content $f -Encoding UTF8; Write-Host '  削除: mule.logging.level'; Write-Host '  削除: mule.lsp.trace.server'; Write-Host '  削除: mule.application.logging.level'"
echo.
echo  VS Code を再起動してください。
exit /b 0

rem ============================================================
:do_status
echo.
echo ============================================================
echo  [trace 設定状況]
echo  対象: !VSCODE_SETTINGS!
echo ============================================================
powershell -NoProfile -Command "$f='!VSCODE_SETTINGS!'; try{$s=Get-Content $f -Raw|ConvertFrom-Json}catch{Write-Host '[ERROR] JSON 解析失敗';exit 1}; foreach($k in @('mule.logging.level','mule.lsp.trace.server','mule.application.logging.level')){$v=$s.$k; if($null -ne $v){Write-Host('  '+$k+' = '+$v)}else{Write-Host('  '+$k+' = (未設定)')}}"
if not defined DO_COLLECT exit /b 0
goto :do_collect

rem ============================================================
:do_collect
echo.
echo ============================================================
echo  [ログ収集]
echo ============================================================

for /f "tokens=1-3 delims=/ " %%a in ('date /t') do set "CDATE=%%c%%a%%b"
for /f "tokens=1-2 delims=: " %%a in ('time /t') do set "CTIME=%%a%%b"
if not defined LOGDIR set "LOGDIR=%CD%\logs"
if not exist "!LOGDIR!" mkdir "!LOGDIR!"
set "DEST=!LOGDIR!\ACB-logs-!CDATE!_!CTIME!"
mkdir "!DEST!" 2>nul
echo   収集先: !DEST!
if defined DO_MASK (echo   モード  : トークンをマスク ^(--mask^)) else (echo   モード  : そのままコピー)
echo.

rem ---- [1/3] settings.json ----
echo   [1/3] settings.json
if defined DO_MASK (
    powershell -NoProfile -Command "$src='!VSCODE_SETTINGS!'; $dst='!DEST!\settings.json'; $c=Get-Content $src -Raw; $c=$c -replace '(\"(?:token|refreshToken|access_token)\"\s*:\s*\")[^\"]*\"','${1}***MASKED***\"'; $c|Set-Content $dst -Encoding UTF8; Write-Host '         OK (トークンをマスクしました)'"
) else (
    copy "!VSCODE_SETTINGS!" "!DEST!\settings.json" >nul
    echo          OK
    echo          [注意] --mask オプションでトークンをマスクできます
)

rem ---- [2/3] ACB home ログ ----
echo   [2/3] ACB home ログ
set "ACB_HOME=%USERPROFILE%\AnypointCodeBuilder"
if defined VSCODE_SETTINGS if exist "!VSCODE_SETTINGS!" (
    for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "try { $s=Get-Content '!VSCODE_SETTINGS!' -Raw | ConvertFrom-Json; if($s.'mule.homeDirectory'){$s.'mule.homeDirectory'} } catch {}"`) do (
        if not "%%H"=="" set "ACB_HOME=%%H"
    )
)
if defined ACB_HOME_OVERRIDE set "ACB_HOME=!ACB_HOME_OVERRIDE!"
echo          Home: !ACB_HOME!

if exist "!ACB_HOME!\logs\" (
    xcopy /E /I /Q "!ACB_HOME!\logs" "!DEST!\acb-home-logs\" >nul
    echo          OK: !ACB_HOME!\logs
) else (
    echo          SKIP: logs フォルダが見つかりません
)

rem ---- [3/3] VS Code exthost ログ ----
echo   [3/3] VS Code exthost ログ
set "VSCODE_LOGS=%APPDATA%\Code\logs"
if not exist "!VSCODE_LOGS!\" (
    echo          SKIP: %APPDATA%\Code\logs が見つかりません
    goto :collect_done
)

set "LATEST_SESSION="
for /f "usebackq delims=" %%S in (`powershell -NoProfile -Command "Get-ChildItem '!VSCODE_LOGS!' -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName"`) do set "LATEST_SESSION=%%S"

if not defined LATEST_SESSION (
    echo          SKIP: セッションフォルダが見つかりません
    goto :collect_done
)
echo          Session: !LATEST_SESSION!

if defined DO_MASK (
    powershell -NoProfile -Command "$src='!LATEST_SESSION!'; $dst='!DEST!\vscode-exthost'; Get-ChildItem $src -Recurse -File -Filter '*.log' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match 'exthost' } | ForEach-Object { $rel=$_.FullName.Substring($src.Length+1); $t=Join-Path $dst $rel; $d=[System.IO.Path]::GetDirectoryName($t); if(-not(Test-Path $d)){New-Item -ItemType Directory -Force -Path $d|Out-Null}; $c=Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue; if($c){$c=$c -replace '\"token\":\"[^\"]+\"','\"token\":\"***MASKED***\"'; $c=$c -replace '\"refreshToken\":\"[^\"]+\"','\"refreshToken\":\"***MASKED***\"'; $c|Set-Content $t -Encoding UTF8} }"
) else (
    powershell -NoProfile -Command "$src='!LATEST_SESSION!'; $dst='!DEST!\vscode-exthost'; Get-ChildItem $src -Recurse -File -Filter '*.log' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match 'exthost' } | ForEach-Object { $rel=$_.FullName.Substring($src.Length+1); $t=Join-Path $dst $rel; $d=[System.IO.Path]::GetDirectoryName($t); if(-not(Test-Path $d)){New-Item -ItemType Directory -Force -Path $d|Out-Null}; Copy-Item $_.FullName $t -ErrorAction SilentlyContinue }"
)

if exist "!DEST!\vscode-exthost\" (
    echo          OK
) else (
    echo          WARN: exthost ログが見つかりませんでした
)

:collect_done
echo.
echo ============================================================
echo   収集完了
echo   フォルダ: !DEST!
echo ============================================================
if not defined DO_MASK (
    echo.
    echo   [警告] ログには Anypoint Platform トークンが含まれる場合があります。
    echo           共有前に内容を確認するか --mask オプションを使用してください。
)
exit /b 0
