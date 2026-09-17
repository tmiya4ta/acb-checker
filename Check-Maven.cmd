@echo off
rem ============================================================
rem  Check-Maven.cmd
rem
rem  Diagnose Maven repository access from this machine.
rem
rem  Usage: Check-Maven.cmd [--token <TOKEN>] [--gav <G:A:V[:classifier]>] [--vscode <PATH>]
rem
rem  Tests:
rem    1. TLS connectivity   (real verification; -k only to show the chain on failure)
rem    2. Auth               (Bearer token from acb_settings.xml, Exchange only)
rem    3. POM HEAD           (mulesoft-releases is public and always tested)
rem    4. JAR download       (size / ZIP magic / entry list - catches empty or HTML bodies)
rem
rem  Token is auto-detected from a running Anypoint Code Builder
rem  (acb_settings.xml). Without it, only the Exchange tests are skipped.
rem ============================================================

rem --- Logging wrapper: capture output to logs folder (in current directory) ---
if not defined _LOGGING (
    setlocal enabledelayedexpansion
    set "LOGDIR=%CD%\logs"
    if not exist "!LOGDIR!" mkdir "!LOGDIR!"
    for /f "tokens=1-3 delims=/ " %%a in ('date /t') do set "LOGDATE=%%c%%a%%b"
    for /f "tokens=1-2 delims=: " %%a in ('time /t') do set "LOGTIME=%%a%%b"
    set "LOGFILE=!LOGDIR!\Check-Maven_!LOGDATE!_!LOGTIME!.log"
    set "_LOGGING=1"
    cmd /c ""%~f0" %*" 2>&1 | powershell -NoProfile -Command "$input | Tee-Object -FilePath '!LOGFILE!'; Write-Host ''; Write-Host '[Log saved to !LOGFILE!]'"
    endlocal
    exit /b
)

setlocal enabledelayedexpansion

set "TOKEN="
set "GAV="
set "SKIP_AUTH="
set "VSCODE_SETTINGS="
set "ASSET="
set "PROXY="
set "PROXY_FORCE_WIN="

:parse
if "%~1"=="" goto :find_proxy
if /i "%~1"=="--token"  ( set "TOKEN=%~2"           & shift & shift & goto :parse )
if /i "%~1"=="--gav"    ( set "GAV=%~2"             & shift & shift & goto :parse )
if /i "%~1"=="--vscode" ( set "VSCODE_SETTINGS=%~2" & shift & shift & goto :parse )
if /i "%~1"=="--asset"  ( set "ASSET=%~2"           & shift & shift & goto :parse )
if /i "%~1"=="--proxy"  ( set "PROXY=%~2"           & shift & shift & goto :parse )
shift & goto :parse

rem ============================================================
rem  Proxy: --proxy > env vars > Windows system proxy > none (direct)
rem  --proxy system  forces use of the Windows system proxy
rem ============================================================
:find_proxy
echo.
echo [*] Proxy configuration ...
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

if defined PROXY (
    echo     Using   : !PROXY!  ^(!PROXY_SRC!^)
) else (
    if defined WINPAC (
        echo     Using   : none  - Windows uses a PAC script ^(!WINPAC!^)
        echo               PAC scripts cannot be resolved automatically.
        echo               Find the actual proxy host:port and pass it via --proxy.
    ) else if defined PROXY_FORCE_WIN (
        echo     Using   : none  - no manual proxy configured in Windows
    ) else (
        echo     Using   : none  ^(direct connection - no proxy^)
    )
    echo     If your network requires a proxy, retry with:
    echo       Check-Maven.cmd --proxy http://proxy.example.com:8080
    echo       Check-Maven.cmd --proxy system    ^(look up and use the Windows system proxy^)
)

set "PROXY_OPT="
if defined PROXY set "PROXY_OPT=-x !PROXY!"

rem ============================================================
rem  Auto-detect token from acb_settings.xml
rem ============================================================
:find_token
if defined TOKEN goto :find_gav

echo.
echo [*] Looking for ACB token in AnypointCodeBuilder\.tmp\ ...

rem -- Check mule.homeDirectory in VS Code settings.json first --
set "ACB_HOME=%USERPROFILE%\AnypointCodeBuilder"
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
if defined VSCODE_SETTINGS echo     VS Code settings: !VSCODE_SETTINGS!
if exist "!VSCODE_SETTINGS!" (
    for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "try { $s=Get-Content '!VSCODE_SETTINGS!' -Raw | ConvertFrom-Json; if($s.'mule.homeDirectory'){$s.'mule.homeDirectory'} } catch {}"`) do (
        if not "%%H"=="" set "ACB_HOME=%%H"
    )
)

set "TMP_BASE=!ACB_HOME!\.tmp"
echo     ACB home: !ACB_HOME!
set "SETTINGS_FILE="

for /d %%d in ("!TMP_BASE!\*") do (
    if exist "%%d\acb_settings.xml" (
        set "SETTINGS_FILE=%%d\acb_settings.xml"
    )
)

if not defined SETTINGS_FILE (
    echo [WARN] acb_settings.xml not found.
    echo        Make sure Anypoint Code Builder is running, then retry.
    echo        Path checked: !TMP_BASE!\^<port^>\acb_settings.xml
    echo        Exchange tests will be skipped; public repo tests still run.
    echo.
    set "SKIP_AUTH=1"
    goto :find_gav
)

echo     Found: !SETTINGS_FILE!

rem Extract first <password>VALUE</password> from the file
for /f "tokens=1,* delims=<" %%a in ('findstr /i "password" "!SETTINGS_FILE!"') do (
    for /f "tokens=1 delims=>" %%c in ("%%b") do (
        if /i "%%c"=="password" (
            for /f "tokens=2 delims=>" %%v in ("%%b") do (
                for /f "tokens=1 delims=<" %%t in ("%%v") do (
                    if not defined TOKEN set "TOKEN=%%t"
                )
            )
        )
    )
)

if defined TOKEN (
    echo     Token : !TOKEN:~0,8!...
) else (
    echo [WARN] Could not parse token from acb_settings.xml.
    echo        Exchange tests will be skipped; public repo tests still run.
    set "SKIP_AUTH=1"
)

rem ============================================================
rem  Default GAV  (classifier is optional 4th field)
rem ============================================================
:find_gav
if not defined GAV (
    set "GAV=org.mule.modules:mule-apikit-module:1.12.6:mule-plugin"
    echo [*] Using default GAV: !GAV!
)

rem ============================================================
set "REPO_MULESOFT=https://repository.mulesoft.org/releases"
set "REPO_EXCHANGE=https://maven.anypoint.mulesoft.com/api/v3/maven"
set "BASIC_USER=~~~Token~~~"
set "WOUT=%TEMP%\mv_w.txt"
set "JARF=%TEMP%\mv_dl.jar"
set "JARLIST=%TEMP%\mv_jar_list.txt"

rem -- Tool for looking inside a jar: ACB JDK -> JAVA_HOME -> PATH -> tar.exe --
set "JARTOOL="
set "JARMODE="
rem Try ACB JDK first (from mule.homeDirectory)
for /d %%j in ("!ACB_HOME!\java\jdk-*") do (
    if not defined JARTOOL if exist "%%j\bin\jar.exe" ( set "JARTOOL=%%j\bin\jar.exe" & set "JARMODE=jar" )
)
if not defined JARTOOL if defined JAVA_HOME if exist "%JAVA_HOME%\bin\jar.exe" ( set "JARTOOL=%JAVA_HOME%\bin\jar.exe" & set "JARMODE=jar" )
if not defined JARTOOL for /f "delims=" %%j in ('where jar.exe 2^>nul')  do if not defined JARTOOL ( set "JARTOOL=%%j" & set "JARMODE=jar" )
if not defined JARTOOL for /f "delims=" %%j in ('where tar.exe 2^>nul')  do if not defined JARTOOL ( set "JARTOOL=%%j" & set "JARMODE=tar" )

echo.
echo ============================================================
echo  0. Local cache check  ^(%USERPROFILE%\.m2\repository^)
echo ============================================================
call :check_local_cache

echo.
echo ============================================================
echo  1. TLS Connectivity
echo ============================================================
call :check_tls "%REPO_MULESOFT%/"
call :check_tls "%REPO_EXCHANGE%/"

echo.
echo ============================================================
echo  2. Auth test  (Anypoint Exchange only - mulesoft-releases is public)
echo ============================================================
if defined SKIP_AUTH (
    echo   [SKIP] No token available.
) else (
    call :check_auth "%REPO_EXCHANGE%/"
)

echo.
echo ============================================================
echo  3. POM download and content check
echo ============================================================
call :check_pom_all

echo.
echo ============================================================
echo  4. JAR download and content check
echo ============================================================
call :check_jar_all

echo.
echo ============================================================
echo  5. Exchange API file download test
echo ============================================================
call :check_exchange_download

del /q "%WOUT%" "%JARF%" "%JARLIST%" 2>nul

echo.
echo ============================================================
echo  Legend
echo ============================================================
echo.
echo   curl 0  + HTTP 200 : OK
echo   curl 0  + HTTP 401 : Token missing or expired
echo   curl 0  + HTTP 403 : Org / permission denied
echo   curl 0  + HTTP 404 : Reached the repo, artifact not found
echo   curl 0  + HTTP 407 : Proxy auth required
echo   curl 60            : SSL cert error   -^> run Check-TLS.cmd
echo   curl 18            : Transfer truncated ^(proxy cut the body^)
echo   curl 7             : Network unreachable
echo   curl 28            : Timeout
echo.
echo   Test 4 NG with an HTML body: a proxy or portal returned an error
echo   page in place of the jar. Maven would cache that as a corrupt
echo   artifact - delete it from %%USERPROFILE%%\.m2\repository and retry.
echo.
endlocal
exit /b 0


rem ============================================================
rem  :run_curl <extra args...> -- sets CURL_RC / ST / SZ / CT
rem ============================================================
:run_curl
set "ST=" & set "SZ=" & set "CT="
curl.exe -sS -w "%%{http_code} %%{size_download} %%{content_type}\n" !PROXY_OPT! --connect-timeout 10 --max-time 30 %* > "%WOUT%" 2>&1
set CURL_RC=!errorlevel!
for /f "usebackq tokens=1,2,3" %%a in ("%WOUT%") do ( set "ST=%%a" & set "SZ=%%b" & set "CT=%%c" )
goto :eof

rem ============================================================
rem  :curl_msg <prefix> -- builds MSG from CURL_RC / ST
rem ============================================================
:curl_msg
set "MSG="
if !CURL_RC!==60 set "MSG=NG  (curl 60 - SSL cert error, run Check-TLS.cmd)"
if !CURL_RC!==18 set "MSG=NG  (curl 18 - transfer truncated)"
if !CURL_RC!==7  set "MSG=NG  (curl 7  - network unreachable)"
if !CURL_RC!==28 set "MSG=NG  (curl 28 - timeout)"
if !CURL_RC! neq 0 if not defined MSG set "MSG=NG  (curl !CURL_RC!)"
if !CURL_RC!==0 if "!ST!"=="200" set "MSG=OK  (HTTP 200)"
if !CURL_RC!==0 if "!ST!"=="301" set "MSG=OK  (HTTP 301 redirect)"
if !CURL_RC!==0 if "!ST!"=="302" set "MSG=OK  (HTTP 302 redirect)"
if !CURL_RC!==0 if "!ST!"=="401" set "MSG=NG  (HTTP 401 - token invalid or expired)"
if !CURL_RC!==0 if "!ST!"=="403" set "MSG=NG  (HTTP 403 - org/permission denied)"
if !CURL_RC!==0 if "!ST!"=="404" set "MSG=--  (HTTP 404 - reached repo, artifact not found)"
if !CURL_RC!==0 if "!ST!"=="407" set "MSG=NG  (HTTP 407 - proxy auth required)"
if not defined MSG set "MSG=?   (HTTP !ST!)"
goto :eof


rem ============================================================
rem  0. Local cache check - corrupt POM/JAR in .m2/repository
rem ============================================================
:check_local_cache
call :parse_gav || goto :eof
set "M2DIR=%USERPROFILE%\.m2\repository\!GPATH!\!AID!\!VER!"
set "LOCAL_POM=!M2DIR!\!AID!-!VER!.pom"
set "LOCAL_JAR=!M2DIR!\!AID!-!VER!!CLSSUF!.jar"
set "CACHE_NG=0"

echo.
echo   GAV: !GID!:!AID!:!VER!!CLSDISP!
echo   Dir: !M2DIR!
echo.

if not exist "!M2DIR!" (
    echo   Status: Not cached ^(directory does not exist^)
    echo           This is normal for first-time downloads.
    goto :eof
)

rem -- Check POM --
echo   POM: !AID!-!VER!.pom
if not exist "!LOCAL_POM!" (
    echo         Not found
) else (
    for %%F in ("!LOCAL_POM!") do set "POMSZ=%%~zF"
    if !POMSZ! lss 100 (
        echo         NG - File too small ^(!POMSZ! bytes^), likely corrupt
        echo         Delete: del "!LOCAL_POM!"
        set "CACHE_NG=1"
    ) else (
        rem Check if it's HTML instead of XML
        findstr /i /c:"<html" "!LOCAL_POM!" >nul 2>&1
        if !errorlevel!==0 (
            echo         NG - Contains HTML ^(proxy error page cached as POM^)
            echo         Delete: del "!LOCAL_POM!"
            set "CACHE_NG=1"
        ) else (
            findstr /i /c:"<project" "!LOCAL_POM!" >nul 2>&1
            if !errorlevel! neq 0 (
                echo         NG - Not a valid Maven POM ^(missing ^<project^> tag^)
                echo         Delete: del "!LOCAL_POM!"
                set "CACHE_NG=1"
            ) else (
                echo         OK  ^(!POMSZ! bytes, valid XML^)
            )
        )
    )
)
echo.

rem -- Check JAR --
echo   JAR: !AID!-!VER!!CLSSUF!.jar
if not exist "!LOCAL_JAR!" (
    echo         Not found
) else (
    for %%F in ("!LOCAL_JAR!") do set "JARSZ=%%~zF"
    if !JARSZ!==0 (
        echo         NG - 0 bytes ^(empty file^)
        echo         Delete: del "!LOCAL_JAR!"
        set "CACHE_NG=1"
    ) else if !JARSZ! lss 1000 (
        echo         NG - File too small ^(!JARSZ! bytes^), likely corrupt or HTML
        echo         Delete: del "!LOCAL_JAR!"
        set "CACHE_NG=1"
    ) else (
        rem Check ZIP magic (PK = 0x50 0x4B)
        set /p MAGIC=<"!LOCAL_JAR!"
        echo !MAGIC! | findstr /b "PK" >nul 2>&1
        if !errorlevel! neq 0 (
            rem Could be HTML error page
            findstr /i /c:"<html" "!LOCAL_JAR!" >nul 2>&1
            if !errorlevel!==0 (
                echo         NG - Contains HTML ^(proxy error page cached as JAR^)
                echo         Delete: del "!LOCAL_JAR!"
                set "CACHE_NG=1"
            ) else (
                echo         ?   ^(!JARSZ! bytes, ZIP magic not detected^)
                echo         Consider: del "!LOCAL_JAR!"
                set "CACHE_NG=1"
            )
        ) else (
            echo         OK  ^(!JARSZ! bytes, valid ZIP^)
        )
    )
)

if !CACHE_NG!==1 (
    echo.
    echo   [!] Corrupt files found in local cache.
    echo       Delete the directory and re-run Maven:
    echo         rmdir /s /q "!M2DIR!"
)
goto :eof


rem ============================================================
rem  1. TLS  - verify for real, then show the chain only if it failed
rem ============================================================
:check_tls
set "URL=%~1"
echo.
echo   %URL%
call :run_curl -o nul "!URL!"
if !CURL_RC!==0 (
    echo   Connectivity : OK  ^(HTTP !ST!^)
    goto :eof
)
if !CURL_RC!==60 (
    echo   Connectivity : NG  ^(curl 60 - certificate not trusted^)
    echo   Chain as presented by the server:
    curl.exe -sk -o nul -w "%%{certs}" !PROXY_OPT! --max-time 20 "!URL!" > "%WOUT%" 2>nul
    for /f "usebackq tokens=1,* delims=:" %%a in (`findstr /b /c:"Subject:" /c:"Issuer:" "%WOUT%"`) do (
        echo      %%a : %%b
    )
    echo   -^> run Check-TLS.cmd for the full MITM diagnosis
    goto :eof
)
call :curl_msg
echo   Connectivity : !MSG!
goto :eof


rem ============================================================
rem  2. Auth  - a 401 on the repo ROOT is not proof of a bad token
rem ============================================================
:check_auth
set "URL=%~1"
echo.
echo   %URL%
call :run_curl -I -o nul -u "!BASIC_USER!:!TOKEN!" "!URL!"
if !CURL_RC!==0 if "!ST!"=="401" (
    echo   Auth ^(Basic^) : ?   ^(HTTP 401 on the repository root^)
    echo                  The root is not an artifact path, so this alone does
    echo                  not mean the token is bad. Trust test 3/4 instead.
    goto :eof
)
call :curl_msg
echo   Auth (Basic) : !MSG!
goto :eof


rem ============================================================
rem  3. POM download - public repo always, Exchange only when a token exists
rem ============================================================
:check_pom_all
call :parse_gav || goto :eof
echo.
echo   GAV: !GID!:!AID!:!VER!!CLSDISP!
echo.
echo   [mulesoft-releases] !POM_MULE!
echo   Downloading POM...
call :check_pom "!POM_MULE!" ""

echo.
echo   [anypoint-exchange-v3] !POM_EXCH!
echo   Downloading POM...
if defined SKIP_AUTH (
    echo   Result : [SKIP] No token available.
    goto :eof
)
call :check_pom "!POM_EXCH!" "!BASIC_USER!" "!TOKEN!"
goto :eof

rem ============================================================
rem  :check_pom <URL> <auth_opts>  - download POM and check content
rem ============================================================
:check_pom
set "POMURL=%~1"
set "POMUSER=%~2"
set "POMPASS=%~3"
set "POMF=%TEMP%\mv_dl.pom"
del /q "!POMF!" 2>nul
if "!POMUSER!"=="" (
    call :run_curl -o "!POMF!" "!POMURL!"
) else (
    call :run_curl -o "!POMF!" -u "!POMUSER!:!POMPASS!" "!POMURL!"
)
if !CURL_RC! neq 0 (
    call :curl_msg
    echo   Result : !MSG!
    goto :eof
)
if not "!ST!"=="200" (
    call :curl_msg
    echo   Result : !MSG!
    goto :eof
)
rem Check file size
for %%f in ("!POMF!") do set "POMSZ=%%~zf"
if "!POMSZ!"=="0" (
    echo   Result : NG  - the file is EMPTY ^(0 bytes^)
    goto :eof
)
if not defined POMSZ (
    echo   Result : NG  - download failed ^(no file^)
    goto :eof
)
rem Check content - read first line to verify it's XML, not HTML
set "POMHEAD="
if not exist "!POMF!" (
    echo   Result : NG  - download file missing
    goto :eof
)
for /f "usebackq tokens=* delims=" %%L in ("!POMF!") do (
    if not defined POMHEAD set "POMHEAD=%%L"
)
echo "!POMHEAD!" | findstr /i /l /c:"<html" /c:"<!DOCTYPE" >nul 2>&1 && (
    echo   Result : NG  - the body is HTML, not XML ^(proxy error page?^)
    goto :eof
)
echo "!POMHEAD!" | findstr /i /l /c:"<project" /c:"<?xml" >nul 2>&1 || (
    echo   Result : NG  - content does not look like XML
    goto :eof
)
echo   Result : OK  ^(HTTP 200, !POMSZ! bytes, valid XML^)
goto :eof


rem ============================================================
rem  :parse_gav  -- G:A:V[:classifier] -> GID/AID/VER/CLS + URLs
rem ============================================================
:parse_gav
set "GID=" & set "AID=" & set "VER=" & set "CLS="
for /f "tokens=1,2,3,4 delims=:" %%a in ("!GAV!") do (
    set "GID=%%a" & set "AID=%%b" & set "VER=%%c" & set "CLS=%%d"
)
if not defined GID goto :gav_bad
if not defined AID goto :gav_bad
if not defined VER goto :gav_bad
set "CLSDISP="
set "CLSSUF="
if defined CLS ( set "CLSDISP=:!CLS!" & set "CLSSUF=-!CLS!" )
set "GPATH=!GID:.=/!"
set "BASE_MULE=%REPO_MULESOFT%/!GPATH!/!AID!/!VER!/!AID!-!VER!"
set "BASE_EXCH=%REPO_EXCHANGE%/!GPATH!/!AID!/!VER!/!AID!-!VER!"
set "POM_MULE=!BASE_MULE!.pom"
set "POM_EXCH=!BASE_EXCH!.pom"
set "JAR_MULE=!BASE_MULE!!CLSSUF!.jar"
set "JAR_EXCH=!BASE_EXCH!!CLSSUF!.jar"
exit /b 0
:gav_bad
echo   [ERROR] Cannot parse GAV: !GAV!  (expected G:A:V[:classifier])
exit /b 1


rem ============================================================
rem  4. JAR download + content check
rem ============================================================
:check_jar_all
call :parse_gav || goto :eof
echo.
if defined JARTOOL (echo   Inspecting with: !JARTOOL! ^(!JARMODE!^)) else (
    echo   [WARN] Neither jar.exe nor tar.exe found - the jar can only be
    echo          checked by size and ZIP magic, not by listing its entries.
)
echo.
echo   [mulesoft-releases] !JAR_MULE!
call :check_jar "!JAR_MULE!"
echo.
echo   [anypoint-exchange-v3] !JAR_EXCH!
if defined SKIP_AUTH (
    echo   Download : [SKIP] No token available.
    goto :eof
)
call :check_jar "!JAR_EXCH!" -u "!BASIC_USER!:!TOKEN!"
goto :eof

rem ------------------------------------------------------------
rem  :check_jar <url> [extra curl args]
rem ------------------------------------------------------------
:check_jar
set "JURL=%~1"
shift
set "XARGS="
:jar_args
if not "%~1"=="" ( set "XARGS=!XARGS! %1" & shift & goto :jar_args )

del /q "!JARF!" 2>nul
call :run_curl -o "!JARF!" !XARGS! "!JURL!"

if !CURL_RC! neq 0 (
    call :curl_msg
    echo   Download : !MSG!
    goto :eof
)
if not "!ST!"=="200" (
    call :curl_msg
    echo   Download : !MSG!
    goto :eof
)

set "FSZ=0"
if exist "!JARF!" for %%z in ("!JARF!") do set "FSZ=%%~zz"
echo   Download : OK  ^(HTTP 200, !FSZ! bytes, Content-Type: !CT!^)

if "!FSZ!"=="0" (
    echo   Content  : NG  - the file is EMPTY ^(0 bytes^)
    goto :eof
)
if not "!FSZ!"=="!SZ!" (
    echo   Content  : NG  - only !FSZ! of !SZ! bytes landed on disk ^(truncated^)
    goto :eof
)

echo !CT! | findstr /i /c:"html" /c:"text/" /c:"json" >nul
if not errorlevel 1 (
    echo   Content  : NG  - the body is !CT!, not a jar.
    echo              A proxy or login portal answered instead of the repo:
    call :show_head
    goto :eof
)

findstr /b /c:"PK" "!JARF!" >nul 2>&1
if errorlevel 1 (
    echo   Content  : NG  - not a ZIP archive ^(no PK header^). First bytes:
    call :show_head
    goto :eof
)

if not defined JARTOOL (
    echo   Content  : OK? - ZIP header present and size matches, but the entry
    echo              list was not checked ^(no jar.exe / tar.exe^).
    goto :eof
)

del /q "!JARLIST!" 2>nul
if /i "!JARMODE!"=="jar" ( "!JARTOOL!" tf "!JARF!" > "!JARLIST!" 2>nul ) else ( "!JARTOOL!" -tf "!JARF!" > "!JARLIST!" 2>nul )
if errorlevel 1 (
    echo   Content  : NG  - the archive is corrupt ^(!JARMODE! could not read it^)
    goto :eof
)

rem Count entries, real files (not directory markers) and classes.
rem A jar that lists only directories is effectively empty.
set /a ENTRIES=0
set /a FILES=0
set /a CLASSES=0
for /f "usebackq delims=" %%l in ("!JARLIST!") do (
    set /a ENTRIES+=1
    set "LN=%%l"
    if not "!LN:~-1!"=="/" set /a FILES+=1
    if /i "!LN:~-6!"==".class" set /a CLASSES+=1
)
if !ENTRIES! EQU 0 (
    echo   Content  : NG  - valid ZIP but it contains NO entries at all
    goto :eof
)
if !FILES! EQU 0 (
    echo   Content  : NG  - !ENTRIES! entries but every one is a directory:
    echo              the jar has no actual content
    goto :eof
)
echo   Content  : OK  ^(!ENTRIES! entries, !FILES! files, !CLASSES! .class^)
if !CLASSES! EQU 0 echo              note: no .class files - resource-only jar, or wrong artifact
goto :eof

rem ------------------------------------------------------------
:show_head
for /f "usebackq delims=" %%l in (`more +0 "!JARF!" 2^>nul`) do (
    echo              ^| %%l
    goto :eof
)
goto :eof

rem ============================================================
rem  5. Exchange API file download test
rem ============================================================
:check_exchange_download
if not defined ASSET (
    echo.
    echo   [SKIP] No --asset specified. Use: --asset assetId
    goto :eof
)
if defined SKIP_AUTH (
    echo.
    echo   [SKIP] No token available for Exchange test.
    goto :eof
)

rem Get root org ID from /accounts/api/me
set "EXCHG="
echo.
echo   Fetching organization ID from Anypoint Platform...
for /f "usebackq delims=" %%O in (`curl.exe -sS !PROXY_OPT! -H "Authorization: Bearer !TOKEN!" "https://anypoint.mulesoft.com/accounts/api/me" 2^>nul ^| powershell -NoProfile -Command "$j=[Console]::In.ReadToEnd() | ConvertFrom-Json; $j.user.organizationId"`) do set "EXCHG=%%O"
if not defined EXCHG (
    echo   [ERROR] Could not get organization ID. Token may be invalid.
    goto :eof
)
echo   Organization: !EXCHG!

rem ASSET is assetId only
set "EXCHA=!ASSET!"
echo.
echo   Testing Exchange API file download...
echo   Asset: !EXCHG!/!EXCHA!
echo.

rem Step 1: Get asset info (requires Bearer auth for private assets)
set "EXCHURL=https://anypoint.mulesoft.com/exchange/api/v2/assets/!EXCHG!/!EXCHA!"
set "EXCHF=%TEMP%\mv_exch.json"
echo   [1] GET asset info: !EXCHURL!
if defined SKIP_AUTH (
    curl.exe -sS !PROXY_OPT! --connect-timeout 10 --max-time 30 "!EXCHURL!" -o "!EXCHF!"
) else (
    curl.exe -sS !PROXY_OPT! --connect-timeout 10 --max-time 30 -H "Authorization: Bearer !TOKEN!" "!EXCHURL!" -o "!EXCHF!"
)
set CURL_RC=!errorlevel!
if "!CURL_RC!" neq "0" (
    echo   Result : NG  - curl !CURL_RC!
    goto :eof
)
if not exist "!EXCHF!" (
    echo   Result : NG  - response file not created
    goto :eof
)

rem Extract version from JSON using PowerShell
set "EXCHVER="
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "$j=Get-Content '!EXCHF!' -Raw | ConvertFrom-Json; $j.version"`) do set "EXCHVER=%%V"
if not defined EXCHVER (
    echo   Result : NG  - could not parse version from response
    goto :eof
)
echo   Version: !EXCHVER!

rem Get download URL for RAML file
set "EXCHDL="
for /f "usebackq delims=" %%U in (`powershell -NoProfile -Command "$j=Get-Content '!EXCHF!' -Raw | ConvertFrom-Json; ($j.files | Where-Object { $_.classifier -match 'raml' } | Select-Object -First 1).downloadURL"`) do set "EXCHDL=%%U"
del /q "!EXCHF!" 2>nul
if not defined EXCHDL (
    echo   Result : NG  - no RAML file found in asset
    goto :eof
)

rem Step 2: Try to download via Maven API (same auth as test 3/4)
set "EXCHMVN=https://maven.anypoint.mulesoft.com/api/v3/maven/!EXCHG!/!EXCHA!/!EXCHVER!/!EXCHA!-!EXCHVER!-raml.zip"
set "EXCHZIP=%TEMP%\mv_spec.zip"
echo.
echo   [2] Download via Maven API (Basic auth)
echo   URL: !EXCHMVN!
if defined SKIP_AUTH (
    echo   Result : [SKIP] No token available.
    goto :eof
)

del /q "!EXCHZIP!" 2>nul
call :run_curl -o "!EXCHZIP!" -u "!BASIC_USER!:!TOKEN!" "!EXCHMVN!"
if !CURL_RC! neq 0 (
    call :curl_msg
    echo   Download : !MSG!
    goto :eof
)
if not "!ST!"=="200" (
    call :curl_msg
    echo   Download : !MSG!
    goto :eof
)

rem Check downloaded file size
set "ZIPSZ=0"
if exist "!EXCHZIP!" for %%z in ("!EXCHZIP!") do set "ZIPSZ=%%~zz"
echo   Download : OK  ^(HTTP 200, !ZIPSZ! bytes^)

if "!ZIPSZ!"=="0" (
    echo   Content  : NG  - the file is EMPTY
    del /q "!EXCHZIP!" 2>nul
    goto :eof
)

rem Check ZIP content using jar command (tvf shows sizes)
set "ZIPLIST=%TEMP%\mv_spec_list.txt"
if not defined JARTOOL (
    echo   Content  : [SKIP] jar command not found
    del /q "!EXCHZIP!" 2>nul
    goto :eof
)
"!JARTOOL!" tvf "!EXCHZIP!" > "!ZIPLIST!" 2>&1
set JAR_RC=!errorlevel!
if !JAR_RC! neq 0 (
    echo   Content  : NG  - not a valid ZIP ^(jar rc=!JAR_RC!^)
    del /q "!EXCHZIP!" "!ZIPLIST!" 2>nul
    goto :eof
)

rem Count files and check for zero-byte files
rem jar tvf output: "  SIZE DATE TIME FILENAME"
set /a ZCNT=0
set /a ZRAML=0
set /a ZEMPTY=0
set /a ZTOTAL=0
for /f "usebackq tokens=1,*" %%a in ("!ZIPLIST!") do (
    set /a ZCNT+=1
    set /a ZTOTAL+=%%a
    if "%%a"=="0" set /a ZEMPTY+=1
    echo %%b | findstr /i /c:".raml" /c:".yaml" /c:".json" >nul && set /a ZRAML+=1
)
if !ZEMPTY! gtr 0 (
    echo   Content  : NG  - !ZEMPTY! empty files found ^(0 bytes^)
    del /q "!EXCHZIP!" "!ZIPLIST!" 2>nul
    goto :eof
)
echo   Content  : OK  ^(!ZCNT! files, !ZRAML! specs, !ZTOTAL! bytes total^)
del /q "!EXCHZIP!" "!ZIPLIST!" 2>nul
goto :eof
