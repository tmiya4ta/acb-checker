@echo off
rem ============================================================
rem  Check-TLS.cmd - TLS inspection (MITM) detection using curl.exe
rem
rem  Usage: Check-TLS.cmd [--vscode <PATH>] [https://example.com ...]
rem
rem  Without URL args, checks google.com plus the Maven/Exchange hosts
rem  used by Check-Maven.cmd for POM/JAR/ZIP downloads:
rem    repository.mulesoft.org, maven.anypoint.mulesoft.com, anypoint.mulesoft.com
rem
rem  Requirements:
rem    curl.exe  - Windows 10 1803+ (Schannel = Windows cert store)
rem    keytool   - Optional. JDK required for Java cacerts check
rem ============================================================

rem --- Logging wrapper: capture output to logs folder (in current directory) ---
if not defined _LOGGING (
    setlocal enabledelayedexpansion
    set "LOGDIR=%CD%\logs"
    if not exist "!LOGDIR!" mkdir "!LOGDIR!"
    for /f "tokens=1-3 delims=/ " %%a in ('date /t') do set "LOGDATE=%%c%%a%%b"
    for /f "tokens=1-2 delims=: " %%a in ('time /t') do set "LOGTIME=%%a%%b"
    set "LOGFILE=!LOGDIR!\Check-TLS_!LOGDATE!_!LOGTIME!.log"
    set "_LOGGING=1"
    cmd /c ""%~f0" %*" 2>&1 | powershell -NoProfile -Command "$input | Tee-Object -FilePath '!LOGFILE!'; Write-Host ''; Write-Host '[Log saved to !LOGFILE!]'"
    endlocal
    exit /b
)

setlocal enabledelayedexpansion

set "VSCODE_SETTINGS="
set "URLS="
set "PROXY="
set "PROXY_FORCE_WIN="
set "SHOWPROXY="

:parse
if "%~1"=="" goto :init
if /i "%~1"=="--vscode"     ( set "VSCODE_SETTINGS=%~2" & shift & shift & goto :parse )
if /i "%~1"=="--proxy"      ( set "PROXY=%~2"           & shift & shift & goto :parse )
if /i "%~1"=="--show-proxy" ( set "SHOWPROXY=1"         & shift & goto :parse )
set "URLS=!URLS! %~1"
shift
goto :parse

:init
set "PUBCA=/c:"DigiCert" /c:"GlobalSign" /c:"Let's Encrypt" /c:"Sectigo" /c:"Comodo" /c:"Entrust" /c:"VeriSign" /c:"USERTrust" /c:"ISRG" /c:"Amazon" /c:"Starfield" /c:"Baltimore" /c:"Cybertrust" /c:"Microsoft" /c:"Apple" /c:"Thawte" /c:"GeoTrust" /c:"QuoVadis" /c:"SwissSign" /c:"T-Systems" /c:"D-Trust" /c:"Certigna" /c:"SECOM" /c:"Symantec" /c:"Google Trust""

if defined SHOWPROXY (
    echo.
    echo ============================================================
    echo  Windows System Proxy Settings
    echo ============================================================
    powershell -NoProfile -Command "$k = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue; Write-Host ('  ProxyEnable   : ' + $(if($k.ProxyEnable -eq 1){'1 (enabled)'}else{'0 (disabled)'})); if ($k.ProxyServer) { Write-Host ('  ProxyServer   : ' + $k.ProxyServer); if ($k.ProxyServer -match '=') { $k.ProxyServer -split ';' | ForEach-Object { $p = $_ -split '=',2; if ($p.Count -eq 2) { Write-Host ('    ' + $p[0] + ' : ' + $p[1]) } } } } else { Write-Host '  ProxyServer   : (not set)' }; if ($k.AutoConfigURL) { Write-Host ('  AutoConfigURL : ' + $k.AutoConfigURL + '  (PAC script - not auto-resolved by this tool)') } else { Write-Host '  AutoConfigURL : (not set)' }"
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
)

rem ---- Proxy: --proxy > env vars > Windows system proxy > none (direct) ----
rem      --proxy system  forces use of the Windows system proxy
echo.
echo ============================================================
echo  Proxy configuration
echo ============================================================
set "PROXY_SRC="
if /i "!PROXY!"=="system" set "PROXY="&set "PROXY_FORCE_WIN=1"

if defined PROXY set "PROXY_SRC=--proxy"

if not defined PROXY if not defined PROXY_FORCE_WIN if defined HTTPS_PROXY set "PROXY=!HTTPS_PROXY!"&set "PROXY_SRC=HTTPS_PROXY env"
if not defined PROXY if not defined PROXY_FORCE_WIN if defined https_proxy set "PROXY=!https_proxy!"&set "PROXY_SRC=https_proxy env"
if not defined PROXY if not defined PROXY_FORCE_WIN if defined HTTP_PROXY set "PROXY=!HTTP_PROXY!"&set "PROXY_SRC=HTTP_PROXY env"
if not defined PROXY if not defined PROXY_FORCE_WIN if defined http_proxy set "PROXY=!http_proxy!"&set "PROXY_SRC=http_proxy env"

set "WINPROXY="
if not defined PROXY if defined PROXY_FORCE_WIN (
    for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command "$k = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue; if ($k.ProxyEnable -eq 1 -and $k.ProxyServer) { $raw = $k.ProxyServer; $m = @{}; $raw -split ';' | ForEach-Object { $p = $_ -split '=',2; if ($p.Count -eq 2) { $m[$p[0]] = $p[1] } }; if ($m.ContainsKey('https')) { $m['https'] } elseif ($m.ContainsKey('http')) { $m['http'] } elseif ($raw -notmatch '=') { $raw } }"`) do set "WINPROXY=%%P"
    if defined WINPROXY set "PROXY=!WINPROXY!"&set "PROXY_SRC=Windows system proxy"
)

set "WINPAC="
if not defined PROXY if defined PROXY_FORCE_WIN (
    for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command "$k = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue; $k.AutoConfigURL"`) do set "WINPAC=%%P"
)

call :mask_proxy "!PROXY!"
if defined PROXY (
    echo   Using : !PROXY_DISP!  ^(!PROXY_SRC!^)
) else (
    if defined WINPAC (
        echo   Using : none  - Windows uses a PAC script ^(!WINPAC!^)
        echo           PAC scripts cannot be resolved automatically.
        echo           Find the actual proxy host:port and pass it via --proxy.
    ) else if defined PROXY_FORCE_WIN (
        echo   Using : none  - no manual proxy configured in Windows
    ) else (
        echo   Using : none  ^(direct connection - no proxy^)
    )
    echo   If your network requires a proxy, retry with:
    echo     Check-TLS.cmd --proxy http://proxy.example.com:8080 https://...
    echo     Check-TLS.cmd --proxy system https://...    ^(look up and use the Windows system proxy^)
)

set "PROXY_OPT="
if defined PROXY set "PROXY_OPT=-x !PROXY!"

rem ---- Find VS Code settings.json ----
rem If --vscode points to a directory, append User\settings.json
if defined VSCODE_SETTINGS (
    if exist "!VSCODE_SETTINGS!\User\settings.json" set "VSCODE_SETTINGS=!VSCODE_SETTINGS!\User\settings.json"
)
if not defined VSCODE_SETTINGS (
    if exist "%APPDATA%\Code\User\settings.json" set "VSCODE_SETTINGS=%APPDATA%\Code\User\settings.json"
)
if not defined VSCODE_SETTINGS (
    if exist "%APPDATA%\Code - Insiders\User\settings.json" set "VSCODE_SETTINGS=%APPDATA%\Code - Insiders\User\settings.json"
)

rem ---- Find ACB JDK from mule.homeDirectory ----
set "ACB_JDK="
if defined VSCODE_SETTINGS if exist "!VSCODE_SETTINGS!" (
    for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "try { $s=Get-Content '!VSCODE_SETTINGS!' -Raw | ConvertFrom-Json; if($s.'mule.homeDirectory'){$s.'mule.homeDirectory'} } catch {}"`) do (
        if not "%%H"=="" (
            for /d %%j in ("%%H\java\jdk-*") do set "ACB_JDK=%%j"
        )
    )
)

rem ---- Find keytool: ACB JDK -> JAVA_HOME -> PATH ----
set "CACERTS_PEM="
set "KEYTOOL="
if defined ACB_JDK if exist "!ACB_JDK!\bin\keytool.exe" set "KEYTOOL=!ACB_JDK!\bin\keytool.exe"
if not defined KEYTOOL if defined JAVA_HOME if exist "%JAVA_HOME%\bin\keytool.exe" set "KEYTOOL=%JAVA_HOME%\bin\keytool.exe"
if not defined KEYTOOL for /f "delims=" %%k in ('where keytool.exe 2^>nul') do set "KEYTOOL=%%k"

if defined KEYTOOL (
    for %%d in ("!KEYTOOL!") do set "JBIN=%%~dpd"
    set "JKS=!JBIN!..\lib\security\cacerts"
    "!KEYTOOL!" -list -rfc -keystore "!JKS!" -storepass changeit > "%TEMP%\tls_cacerts.pem" 2>nul
    findstr /c:"BEGIN CERTIFICATE" "%TEMP%\tls_cacerts.pem" >nul 2>&1 && set "CACERTS_PEM=%TEMP%\tls_cacerts.pem"
)

echo.
echo ============================================================
echo  Certificate stores being checked
echo ============================================================
echo   Windows cert store : Schannel ^(system trust store^)
echo                        certlm.msc ^> Trusted Root Certification Authorities
if defined JKS (
    echo   Java cacerts       : !JKS!
) else (
    echo   Java cacerts       : [not found - keytool not available]
)
echo ============================================================

if "!URLS!"=="" set "URLS=https://www.google.com https://repository.mulesoft.org/releases/ https://maven.anypoint.mulesoft.com/api/v3/maven/ https://anypoint.mulesoft.com/"
for %%u in (!URLS!) do call :check %%u

echo.
echo ------------------------------------------------------------
echo  Legend
echo ------------------------------------------------------------
echo   Root CA: Trusted      - Certificate is from a known public CA
echo   Root CA: Unknown      - Certificate is from unknown CA
echo                           ^(corporate proxy MITM, or badssl test site^)
echo.
echo   Windows OK / Java NG  - CA missing from JDK cacerts
echo                           Fix: -Djavax.net.ssl.trustStoreType=WINDOWS-ROOT
echo ------------------------------------------------------------

del /q "%TEMP%\tls_chain.txt" "%TEMP%\tls_chain_err.txt" "%TEMP%\tls_e1.txt" "%TEMP%\tls_e2.txt" "%TEMP%\tls_cacerts.pem" 2>nul
endlocal
exit /b 0

rem ============================================================
:check
set "URL=%~1"
echo.
echo ============================================================
echo   %URL%
echo ============================================================

rem ---- 1) Certificate chain (-k to bypass validation and get chain) ----
curl.exe -sS -k -o nul -w "%%{certs}" !PROXY_OPT! "%URL%" > "%TEMP%\tls_chain.txt" 2>"%TEMP%\tls_chain_err.txt"
set "CHAIN_RC=!errorlevel!"
if not exist "%TEMP%\tls_chain.txt" goto :nochain
for %%s in ("%TEMP%\tls_chain.txt") do if %%~zs==0 goto :nochain

set /a IDX=0
set "MITM="
echo   Certificate chain:
for /f "usebackq tokens=1,* delims=:" %%a in (`findstr /b /c:"Subject:" /c:"Issuer:" "%TEMP%\tls_chain.txt"`) do (
    if /i "%%a"=="Subject" (
        set "SUBJ=%%b"
        echo     [!IDX!] Subject : %%b
        set /a IDX+=1
    ) else (
        echo          Issuer  : %%b
        if /i "!SUBJ!"=="%%b" (
            echo !SUBJ! | findstr /i %PUBCA% >nul
            if errorlevel 1 (
                echo          *** Unknown CA ^(not in public CA list^) ***
                set "MITM=1"
            ) else (
                echo          [Public root CA]
            )
        )
    )
)
if defined MITM (echo   Root CA        : Unknown ^(corporate proxy or test site^)) else (echo   Root CA        : Trusted)
goto :winstore

:nochain
echo   [WARN] Could not retrieve certificate chain
if defined CHAIN_RC if !CHAIN_RC! neq 0 (
    echo          curl exit code: !CHAIN_RC!
    if !CHAIN_RC!==6  echo          ^(Could not resolve host^)
    if !CHAIN_RC!==7  echo          ^(Failed to connect - network/firewall/proxy^)
    if !CHAIN_RC!==28 echo          ^(Connection timeout^)
    if !CHAIN_RC!==35 echo          ^(SSL connect error^)
    if !CHAIN_RC!==56 echo          ^(Recv failure - connection reset^)
)
if exist "%TEMP%\tls_chain_err.txt" for %%s in ("%TEMP%\tls_chain_err.txt") do if %%~zs gtr 0 (
    echo          Error details:
    type "%TEMP%\tls_chain_err.txt"
)

rem ---- 2) Windows certificate store ----
:winstore
curl.exe -sS -o nul !PROXY_OPT! "%URL%" 2>"%TEMP%\tls_e1.txt"
set RC=!errorlevel!
if !RC!==0    (echo   Windows cert store : OK) else (
if !RC!==60   (echo   Windows cert store : NG - certificate not trusted) else (
if !RC!==35   (echo   Windows cert store : NG - TLS handshake failed) else (
              echo   Windows cert store : ? curl exit code !RC!)))

rem ---- 3) JDK cacerts ----
if not defined CACERTS_PEM (
    echo   Java cacerts         : SKIP - keytool not found
    goto :eof
)
curl.exe -sS -o nul --cacert "!CACERTS_PEM!" !PROXY_OPT! "%URL%" 2>"%TEMP%\tls_e2.txt"
set RC=!errorlevel!
if !RC!==0  (echo   Java cacerts         : OK) else (
if !RC!==60 (echo   Java cacerts         : NG - CA not in cacerts ^(PKIX path building failed^)) else (
            echo   Java cacerts         : ? curl exit code !RC!))
goto :eof

rem ============================================================
rem  :mask_proxy <value> -- sets PROXY_DISP with any embedded
rem  credentials replaced by *** (the value is echoed to the
rem  console and to logs\, so user:pass@host must never appear)
rem ============================================================
:mask_proxy
set "PROXY_DISP=%~1"
rem !PROXY_DISP! (not %~1) from here on: delayed expansion is not
rem re-parsed, so a value containing & or | stays literal.
echo(!PROXY_DISP!| findstr /c:"@" >nul || goto :eof
for /f "tokens=1,* delims=@" %%x in ("!PROXY_DISP!") do (
    set "MP_CRED=%%x"
    set "MP_HOST=%%y"
)
set "PROXY_DISP=***@!MP_HOST!"
for /f "tokens=1,* delims=/" %%s in ("!MP_CRED!") do (
    if not "%%t"=="" set "PROXY_DISP=%%s//***@!MP_HOST!"
)
goto :eof
