@echo off
rem ============================================================
rem  _Common.cmd - routines shared by Check-Maven.cmd / Check-TLS.cmd
rem
rem  Usage:  call "%~dp0_Common.cmd" :<routine> [args...]
rem
rem  There is deliberately no setlocal in this file: the variables
rem  these routines set (PROXY, PROXY_OPT, PROXY_DISP, VSCODE_SETTINGS,
rem  MAGIC, ...) have to stay visible to the caller.
rem  The caller must run with delayed expansion enabled.
rem ============================================================

rem -- Probe for delayed expansion; without it nothing below works --
set "_DE_A=probe"
set "_DE_B=!_DE_A!"
if not "%_DE_B%"=="probe" (
    echo [ERROR] _Common.cmd requires the caller to run with
    echo         setlocal enabledelayedexpansion.
    exit /b 2
)
set "_DE_A=" & set "_DE_B="

if "%~1"=="" (
    echo [ERROR] _Common.cmd is a library - call it with a routine name.
    exit /b 2
)
set "_ROUTINE=%~1"
shift
goto %_ROUTINE%


rem ============================================================
rem  :mask_proxy <value>   ->  PROXY_DISP
rem
rem  Replaces credentials embedded in a proxy URL with ***.
rem  The value is echoed to the console and into logs\, so a
rem  user:pass@host must never appear there verbatim.
rem ============================================================
:mask_proxy
set "PROXY_DISP=%~1"
rem Everything below reads !PROXY_DISP! rather than %~1: delayed
rem expansion is not re-parsed, so & or | in the value stay literal.
echo(!PROXY_DISP!| findstr /c:"@" >nul || exit /b 0
for /f "tokens=1,* delims=@" %%x in ("!PROXY_DISP!") do (
    set "MP_CRED=%%x"
    set "MP_HOST=%%y"
)
set "PROXY_DISP=***@!MP_HOST!"
for /f "tokens=1,* delims=/" %%s in ("!MP_CRED!") do (
    if not "%%t"=="" set "PROXY_DISP=%%s//***@!MP_HOST!"
)
exit /b 0


rem ============================================================
rem  :show_proxy   - dump every place Windows keeps a proxy setting
rem ============================================================
:show_proxy
echo.
echo ============================================================
echo  Windows proxy settings
echo ============================================================
powershell -NoProfile -Command "$t=@(@('HKCU       ','HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'),@('HKLM       ','HKLM:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'),@('HKLM policy','HKLM:\Software\Policies\Microsoft\Windows\CurrentVersion\Internet Settings')); foreach ($e in $t) { $k = Get-ItemProperty $e[1] -ErrorAction SilentlyContinue; if (-not $k) { Write-Host ('  ' + $e[0] + ' : (key does not exist)'); continue }; Write-Host ('  ' + $e[0] + ' : ProxyEnable   : ' + $(if($k.ProxyEnable -eq 1){'1 (enabled)'}else{'0 (disabled)'})); Write-Host ('                ProxyServer   : ' + $(if($k.ProxyServer){$k.ProxyServer}else{'(not set)'})); Write-Host ('                ProxyOverride : ' + $(if($k.ProxyOverride){$k.ProxyOverride}else{'(not set)'})); Write-Host ('                AutoConfigURL : ' + $(if($k.AutoConfigURL){$k.AutoConfigURL + '  (PAC - not resolved by this tool)'}else{'(not set)'})) }"
echo.
echo   WinHTTP ^(used by services and some JVMs; independent of the above^):
netsh winhttp show proxy
echo.
echo   Environment variables:
if defined HTTPS_PROXY (
    call :mask_proxy "!HTTPS_PROXY!"
    echo     HTTPS_PROXY : !PROXY_DISP!
) else (echo     HTTPS_PROXY : ^(not set^))
if defined https_proxy (
    call :mask_proxy "!https_proxy!"
    echo     https_proxy : !PROXY_DISP!
) else (echo     https_proxy : ^(not set^))
if defined HTTP_PROXY (
    call :mask_proxy "!HTTP_PROXY!"
    echo     HTTP_PROXY  : !PROXY_DISP!
) else (echo     HTTP_PROXY  : ^(not set^))
if defined http_proxy (
    call :mask_proxy "!http_proxy!"
    echo     http_proxy  : !PROXY_DISP!
) else (echo     http_proxy  : ^(not set^))
echo ============================================================
exit /b 0


rem ============================================================
rem  :resolve_proxy <script-name>
rem
rem  Priority: --proxy > env vars > (only with --proxy system) the
rem  Windows system proxy > none.  Reads PROXY (may hold "system")
rem  and sets PROXY / PROXY_SRC / PROXY_OPT / PROXY_BYPASS / WINPAC.
rem ============================================================
:resolve_proxy
set "SCRIPTNAME=%~1"
set "PROXY_SRC="
set "PROXY_BYPASS="
set "PROXY_FORCE_WIN="
set "WINPROXY="
set "WINPAC="
set "WINFROM="

if /i "!PROXY!"=="system" set "PROXY=" & set "PROXY_FORCE_WIN=1"
if defined PROXY set "PROXY_SRC=--proxy"

if not defined PROXY if not defined PROXY_FORCE_WIN if defined HTTPS_PROXY set "PROXY=!HTTPS_PROXY!"&set "PROXY_SRC=HTTPS_PROXY env"
if not defined PROXY if not defined PROXY_FORCE_WIN if defined https_proxy set "PROXY=!https_proxy!"&set "PROXY_SRC=https_proxy env"
if not defined PROXY if not defined PROXY_FORCE_WIN if defined HTTP_PROXY set "PROXY=!HTTP_PROXY!"&set "PROXY_SRC=HTTP_PROXY env"
if not defined PROXY if not defined PROXY_FORCE_WIN if defined http_proxy set "PROXY=!http_proxy!"&set "PROXY_SRC=http_proxy env"

rem -- Windows system proxy: HKCU, then HKLM, then the HKLM policy key --
if not defined PROXY if defined PROXY_FORCE_WIN (
    for /f "usebackq tokens=1,* delims==" %%a in (`powershell -NoProfile -Command "$t=@(@('HKCU','HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'),@('HKLM','HKLM:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'),@('HKLM policy','HKLM:\Software\Policies\Microsoft\Windows\CurrentVersion\Internet Settings')); $proxy=$null; $from=$null; $bypass=$null; $pac=$null; foreach ($e in $t) { $k = Get-ItemProperty $e[1] -ErrorAction SilentlyContinue; if (-not $k) { continue }; if (-not $pac -and $k.AutoConfigURL) { $pac = $k.AutoConfigURL }; if ($proxy) { continue }; if ($k.ProxyEnable -eq 1 -and $k.ProxyServer) { $raw = $k.ProxyServer; $m = @{}; $raw -split ';' | ForEach-Object { $q = $_ -split '=',2; if ($q.Count -eq 2) { $m[$q[0]] = $q[1] } }; $p = $null; if ($m.ContainsKey('https')) { $p = $m['https'] } elseif ($m.ContainsKey('http')) { $p = $m['http'] } elseif ($raw -notmatch '=') { $p = $raw }; if ($p) { $proxy = $p; $from = $e[0]; $bypass = $k.ProxyOverride } } }; if ($proxy) { Write-Output ('proxy=' + $proxy); Write-Output ('from=' + $from); if ($bypass) { Write-Output ('bypass=' + $bypass) } }; if ($pac) { Write-Output ('pac=' + $pac) }"`) do (
        if /i "%%a"=="proxy"  set "WINPROXY=%%b"
        if /i "%%a"=="from"   set "WINFROM=%%b"
        if /i "%%a"=="bypass" set "PROXY_BYPASS=%%b"
        if /i "%%a"=="pac"    set "WINPAC=%%b"
    )
    if defined WINPROXY set "PROXY=!WINPROXY!"&set "PROXY_SRC=Windows system proxy - !WINFROM!"
)

echo.
echo ============================================================
echo  Proxy configuration
echo ============================================================
call :mask_proxy "!PROXY!"
if defined PROXY (
    echo   Using  : !PROXY_DISP!  ^(!PROXY_SRC!^)
    if defined PROXY_BYPASS (
        echo   Bypass : !PROXY_BYPASS!
        echo            Windows bypass list - NOT applied here: curl sends
        echo            every URL through the proxy.
    )
    goto :resolve_proxy_done
)
if defined WINPAC (
    echo   Using  : none  - Windows uses a PAC script ^(!WINPAC!^)
    echo            PAC scripts cannot be resolved automatically.
    echo            Find the actual proxy host:port and pass it via --proxy.
) else if defined PROXY_FORCE_WIN (
    echo   Using  : none  - no manual proxy configured in Windows
) else (
    echo   Using  : none  ^(direct connection - no proxy^)
)
echo   If your network requires a proxy, retry with:
echo     !SCRIPTNAME! --proxy http://proxy.example.com:8080
echo     !SCRIPTNAME! --proxy system    ^(look up and use the Windows system proxy^)

:resolve_proxy_done
set "PROXY_OPT="
if defined PROXY set "PROXY_OPT=-x !PROXY!"
exit /b 0


rem ============================================================
rem  :find_vscode   ->  VSCODE_SETTINGS
rem
rem  Honours a VSCODE_SETTINGS already set from --vscode (a
rem  directory is completed with User\settings.json), otherwise
rem  looks in the usual VS Code locations.
rem ============================================================
:find_vscode
if defined VSCODE_SETTINGS (
    if exist "!VSCODE_SETTINGS!\User\settings.json" set "VSCODE_SETTINGS=!VSCODE_SETTINGS!\User\settings.json"
)
if not defined VSCODE_SETTINGS (
    if exist "%APPDATA%\Code\User\settings.json" set "VSCODE_SETTINGS=%APPDATA%\Code\User\settings.json"
)
if not defined VSCODE_SETTINGS (
    if exist "%APPDATA%\Code - Insiders\User\settings.json" set "VSCODE_SETTINGS=%APPDATA%\Code - Insiders\User\settings.json"
)
exit /b 0


rem ============================================================
rem  :zip_magic <file>   ->  MAGIC
rem
rem  First two bytes of the file as text ("PK" for a jar/zip).
rem  set /p cannot be used: it stops at NUL/EOF bytes, and
rem  findstr /b matches any line start, not just the first byte.
rem ============================================================
:zip_magic
set "MAGIC="
for /f "usebackq delims=" %%M in (`powershell -NoProfile -Command "$f=[System.IO.File]::OpenRead('%~1'); $b=New-Object byte[] 2; $n=$f.Read($b,0,2); $f.Close(); if($n -eq 2){[char]$b[0]+[char]$b[1]}"`) do set "MAGIC=%%M"
exit /b 0
