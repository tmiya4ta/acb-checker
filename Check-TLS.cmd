@echo off
rem ============================================================
rem  Check-TLS.cmd - TLS inspection (MITM) detection using curl.exe
rem
rem  Usage: Check-TLS.cmd [--vscode <PATH>] [--proxy <URL|system>]
rem                       [--show-proxy] [--help] [https://example.com ...]
rem
rem  Without URL args, checks all hosts listed in the ACB proxy settings doc
rem  (docs.mulesoft.com/anypoint-code-builder/ref-proxy-settings):
rem    repository.mulesoft.org, maven.anypoint.mulesoft.com, anypoint.mulesoft.com
rem    exchange2-asset-manager-kprod.s3.amazonaws.com
rem    exchange2-file-upload-service-kprod.s3.amazonaws.com
rem    repo.maven.apache.org, repo1.maven.org, download.eclipse.org
rem
rem  Requirements:
rem    _Common.cmd - shared routines, must sit next to this script
rem    curl.exe    - Windows 10 1803+ (Schannel = Windows cert store)
rem    keytool     - Optional. JDK required for Java cacerts check
rem
rem  Exit code: 0 = nothing wrong found
rem             1 = at least one NG (untrusted CA / failed connection)
rem             2 = usage error or missing _Common.cmd
rem ============================================================

if defined _LOGGING goto :main

rem --- Logging wrapper: capture output to logs folder (in current directory) ---
setlocal enabledelayedexpansion
set "LOGDIR=%CD%\logs"
if not exist "!LOGDIR!" mkdir "!LOGDIR!"
for /f "tokens=1-3 delims=/ " %%a in ('date /t') do set "LOGDATE=%%c%%a%%b"
for /f "tokens=1-2 delims=: " %%a in ('time /t') do set "LOGTIME=%%a%%b"
set "LOGFILE=!LOGDIR!\Check-TLS_!LOGDATE!_!LOGTIME!.log"
rem A pipeline reports the exit code of its LAST stage, so the real run's
rem code would be lost. The child writes it to RCFILE instead - environment
rem variables are inherited by the child, delayed expansion is not.
set "RCFILE=%TEMP%\acb_rc_%RANDOM%.tmp"
del /q "!RCFILE!" 2>nul
set "_LOGGING=1"
cmd /c ""%~f0" %*" 2>&1 | powershell -NoProfile -Command "$input | Tee-Object -FilePath '!LOGFILE!'; Write-Host ''; Write-Host '[Log saved to !LOGFILE!]'"
set "RC=1"
if exist "!RCFILE!" set /p RC=<"!RCFILE!"
del /q "!RCFILE!" 2>nul
for /f "delims=" %%r in ("!RC!") do endlocal & exit /b %%r

:main
setlocal enabledelayedexpansion

set "COMMON=%~dp0_Common.cmd"
if not exist "!COMMON!" (
    echo [ERROR] _Common.cmd not found next to this script.
    echo         Check-TLS.cmd, Check-Maven.cmd and _Common.cmd must be
    echo         copied together into the same folder.
    set "RC=2"
    goto :finish
)

set "VSCODE_SETTINGS="
set "PROXY="
set "SHOWPROXY="
set /a URLN=0
set /a NGCOUNT=0

:parse
if "%~1"=="" goto :init
if /i "%~1"=="--vscode"     ( set "VSCODE_SETTINGS=%~2" & shift & shift & goto :parse )
if /i "%~1"=="--proxy"      ( set "PROXY=%~2"           & shift & shift & goto :parse )
if /i "%~1"=="--show-proxy" ( set "SHOWPROXY=1"         & shift & goto :parse )
if /i "%~1"=="--help"       goto :usage
if /i "%~1"=="-h"           goto :usage
if /i "%~1"=="/?"           goto :usage
rem Anything else must be a URL; an unknown option is a typo, not a URL.
set "ARG=%~1"
echo(!ARG!| findstr /b /c:"-" >nul && (
    echo [ERROR] Unknown option: !ARG!
    goto :usage_err
)
call :add_url "!ARG!"
shift
goto :parse

:usage_err
set "RC=2"
echo.
goto :usage_body
:usage
set "RC=0"
:usage_body
echo Usage: Check-TLS.cmd [options] [https://example.com ...]
echo.
echo   --vscode ^<PATH^>     VS Code settings.json ^(or its parent folder^)
echo   --proxy ^<URL^>       use this proxy ^(e.g. http://proxy.example.com:8080^)
echo   --proxy system      look up and use the Windows system proxy
echo   --show-proxy        show the Windows proxy settings and exit
echo   --help              show this help
echo.
echo   Without URLs, google.com and the MuleSoft Maven/Exchange hosts
echo   are checked. Exit code: 0 = OK, 1 = something is NG, 2 = usage error.
goto :finish

:add_url
set /a URLN+=1
set "URL_!URLN!=%~1"
exit /b 0

:init
set "PUBCA=/c:"DigiCert" /c:"GlobalSign" /c:"Let's Encrypt" /c:"Sectigo" /c:"Comodo" /c:"Entrust" /c:"VeriSign" /c:"USERTrust" /c:"ISRG" /c:"Amazon" /c:"Starfield" /c:"Baltimore" /c:"Cybertrust" /c:"Microsoft" /c:"Apple" /c:"Thawte" /c:"GeoTrust" /c:"QuoVadis" /c:"SwissSign" /c:"T-Systems" /c:"D-Trust" /c:"Certigna" /c:"SECOM" /c:"Symantec" /c:"Google Trust""

if defined SHOWPROXY (
    call "!COMMON!" :show_proxy
    set "RC=0"
    goto :finish
)

call "!COMMON!" :resolve_proxy "Check-TLS.cmd"
call "!COMMON!" :find_vscode

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
    call "!COMMON!" :mask_userpath "!JKS!"
    echo   Java cacerts       : !PATH_DISP!
) else (
    echo   Java cacerts       : [not found - keytool not available]
)
echo ============================================================

if !URLN!==0 (
    rem general connectivity
    call :add_url "https://www.google.com"
    rem MuleSoft Maven / Exchange  (ref-proxy-settings allowlist)
    call :add_url "https://repository.mulesoft.org/releases/"
    call :add_url "https://maven.anypoint.mulesoft.com/api/v3/maven/"
    call :add_url "https://anypoint.mulesoft.com/"
    call :add_url "https://exchange2-asset-manager-kprod.s3.amazonaws.com/"
    call :add_url "https://exchange2-file-upload-service-kprod.s3.amazonaws.com/"
    rem Maven Central  (ref-proxy-settings allowlist)
    call :add_url "https://repo.maven.apache.org/maven2/"
    call :add_url "https://repo1.maven.org/maven2/"
    rem Eclipse updates  (ref-proxy-settings allowlist)
    call :add_url "https://download.eclipse.org/eclipse/updates/"
)

rem The CALL below expands %%URL_%%i%% twice, which is what turns
rem URL_1 into its value. A plain "for %%u in (!URLS!)" cannot be used:
rem FOR would glob a URL containing * or ?.
for /l %%i in (1,1,!URLN!) do call :check "%%URL_%%i%%"

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

set "RC=0"
if !NGCOUNT! gtr 0 set "RC=1"

rem ============================================================
rem  :finish  - single exit point; hands RC back through the log pipe
rem ============================================================
:finish
if not defined RC set "RC=1"
if defined RCFILE >"!RCFILE!" echo !RC!
for /f "delims=" %%r in ("!RC!") do endlocal & exit /b %%r

rem ============================================================
:check
set "URL=%~1"
echo.
echo ============================================================
echo   !URL!
echo ============================================================

rem ---- 1) Certificate chain (-k to bypass validation and get chain) ----
curl.exe -sS -k -o nul -w "%%{certs}" !PROXY_OPT! "!URL!" > "%TEMP%\tls_chain.txt" 2>"%TEMP%\tls_chain_err.txt"
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
if defined MITM (
    echo   Root CA        : Unknown ^(corporate proxy or test site^)
    set /a NGCOUNT+=1
) else (
    echo   Root CA        : Trusted
)
goto :winstore

:nochain
echo   [WARN] Could not retrieve certificate chain
set /a NGCOUNT+=1
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
curl.exe -sS -o nul !PROXY_OPT! "!URL!" 2>"%TEMP%\tls_e1.txt"
set RC_CURL=!errorlevel!
if !RC_CURL!==0 (
    echo   Windows cert store : OK
) else (
    set /a NGCOUNT+=1
    if !RC_CURL!==60 (
        echo   Windows cert store : NG - certificate not trusted
    ) else if !RC_CURL!==35 (
        echo   Windows cert store : NG - TLS handshake failed
    ) else (
        echo   Windows cert store : ? curl exit code !RC_CURL!
    )
)

rem ---- 3) JDK cacerts ----
if not defined CACERTS_PEM (
    echo   Java cacerts         : SKIP - keytool not found
    goto :eof
)
curl.exe -sS -o nul --cacert "!CACERTS_PEM!" !PROXY_OPT! "!URL!" 2>"%TEMP%\tls_e2.txt"
set RC_CURL=!errorlevel!
if !RC_CURL!==0 (
    echo   Java cacerts         : OK
) else (
    set /a NGCOUNT+=1
    if !RC_CURL!==60 (
        echo   Java cacerts         : NG - CA not in cacerts ^(PKIX path building failed^)
    ) else (
        echo   Java cacerts         : ? curl exit code !RC_CURL!
    )
)
goto :eof
