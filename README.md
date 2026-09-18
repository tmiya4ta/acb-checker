# acb-checker

Anypoint Code Builder (ACB) の Maven リポジトリ接続問題と、社内プロキシ（MITM）による TLS 証明書問題を診断するツール。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `Check-Maven.cmd` | Maven リポジトリ診断 |
| `Check-TLS.cmd` | TLS / MITM 診断 |
| `_Common.cmd` | 上記 2 つが共有するルーチン（プロキシ解決・設定探索など） |
| `Verify-Check-TLS.cmd` | `Check-TLS.cmd` の動作確認 |

**4 ファイルは同じフォルダにまとめてコピーすること。**
`_Common.cmd` が隣にないと、`Check-Maven.cmd` / `Check-TLS.cmd` はエラー終了する（終了コード 2）。

## 終了コード

| コード | 意味 |
|---|---|
| `0` | NG なし |
| `1` | NG が 1 件以上（証明書未信頼、ダウンロード失敗、キャッシュ破損など） |
| `2` | 引数エラー、または `_Common.cmd` が見つからない |

バッチや CI から呼ぶ場合はこの値で判定できる。
実行ログは常にカレントディレクトリの `logs\` に保存される。

## ヘルプ

```cmd
Check-Maven.cmd --help
Check-TLS.cmd --help
```

未知のオプションを渡した場合は黙って無視せず、エラーにして使い方を表示する。

---

## Check-Maven.cmd

**Maven リポジトリへの接続・認証・アーティファクト取得を診断する。**

ACB を起動した状態でコマンドプロンプトから実行するだけ。

```cmd
Check-Maven.cmd
Check-Maven.cmd --vscode C:\vscode
```

### トークン自動検出

1. VS Code の `settings.json` から `mule.homeDirectory` を読む
2. 見つからなければ `%USERPROFILE%\AnypointCodeBuilder` をデフォルトとする
3. `<ACB_HOME>\.tmp\<port>\acb_settings.xml` からトークンを抽出

ACB が起動していない場合は Exchange 側のテストをスキップし、公開リポジトリのテストのみ実行する。

### テスト項目

| テスト | 内容 | 認証 |
|--------|------|------|
| 0. Local cache check | `~/.m2/repository` のキャッシュ破損チェック | なし |
| 1. TLS Connectivity | MuleSoft リポジトリへの疎通確認 | なし |
| 2. Auth test | Anypoint Exchange への認証確認 | Basic |
| 3. POM download | POM ファイルのダウンロードと XML 検証 | Basic |
| 4. JAR download | JAR ファイルのダウンロードと内容検証 | Basic |
| 5. API spec download | Exchange の API spec ダウンロード（`--asset` 指定時のみ） | Basic |

### 出力例（正常時）

```
[*] Looking for ACB token in AnypointCodeBuilder\.tmp\ ...
    ACB home: C:\Users\<user>\AnypointCodeBuilder
    Found: C:\Users\<user>\AnypointCodeBuilder\.tmp\12345\acb_settings.xml
    Token : xxxxxxxx...
[*] Using default GAV: org.mule.modules:mule-apikit-module:1.12.6

============================================================
 0. Local cache check  (%USERPROFILE%\.m2\repository)
============================================================
  GAV: org.mule.modules:mule-apikit-module:1.12.6:mule-plugin
  Dir: C:\Users\<user>\.m2\repository\org\mule\modules\mule-apikit-module\1.12.6

  POM: mule-apikit-module-1.12.6.pom
        OK  (39085 bytes, valid XML)

  JAR: mule-apikit-module-1.12.6-mule-plugin.jar
        OK  (5750110 bytes, valid ZIP)

============================================================
 1. TLS Connectivity
============================================================
  https://repository.mulesoft.org/releases/
  Connectivity : OK  (HTTP 200)

  https://maven.anypoint.mulesoft.com/api/v3/maven/
  Connectivity : OK  (HTTP 200)

============================================================
 2. Auth test  (Anypoint Exchange only - mulesoft-releases is public)
============================================================
  https://maven.anypoint.mulesoft.com/api/v3/maven/
  Auth (Basic) : OK  (HTTP 200)

============================================================
 3. POM download and content check
============================================================
  GAV: org.mule.modules:mule-apikit-module:1.12.6

  [mulesoft-releases] https://...
  Result : OK  (HTTP 200, 40540 bytes, valid XML)

  [anypoint-exchange-v3] https://...
  Result : OK  (HTTP 200, 39085 bytes, valid XML)

============================================================
 4. JAR download and content check
============================================================
  [mulesoft-releases] https://...
  Download : OK  (HTTP 200, 5750480 bytes)
  Content  : OK  (248 entries, 196 files, 156 .class)

  [anypoint-exchange-v3] https://...
  Download : OK  (HTTP 200, 5750110 bytes)
  Content  : OK  (248 entries, 196 files, 156 .class)

============================================================
 5. Exchange API file download test
============================================================
  Fetching organization ID from Anypoint Platform...
  Organization: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

  Testing Exchange API file download...
  Asset: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/my-api-spec

  [1] GET asset info: https://anypoint.mulesoft.com/exchange/api/v2/assets/...
  Version: 1.0.1

  [2] Download via Maven API (Basic auth)
  URL: https://maven.anypoint.mulesoft.com/api/v3/maven/.../my-api-spec-1.0.1-raml.zip
  Download : OK  (HTTP 200, 1240 bytes)
  Content  : OK  (2 entries, 2 spec files)
```

### 結果の読み方

| 表示 | 意味 | 対処 |
|---|---|---|
| `POM: OK` / `JAR: OK` | ローカルキャッシュ正常 | — |
| `POM: NG` / `JAR: NG` | **キャッシュ破損** | 表示されたコマンドでファイル/フォルダを削除 |
| `Connectivity : OK` | ネットワーク疎通 OK | — |
| `Auth (Basic) : OK` | トークン有効、認証 OK | — |
| `Result : OK` | アーティファクト取得可能 | — |
| `curl 60` | **SSL 証明書エラー** | `Check-TLS.cmd` で詳細確認 → 下記「解決策」 |
| `HTTP 401` | トークン期限切れ | ACB 再起動してリトライ |
| `HTTP 407` | プロキシ認証が必要 | プロキシ設定を確認 |
| `curl 7` | ネットワーク到達不可 | ファイアウォール / VPN を確認 |

### オプション

```cmd
Check-Maven.cmd                           基本テスト（1〜4）のみ
Check-Maven.cmd --asset <assetId>         API spec ダウンロードもテスト（テスト 5）
Check-Maven.cmd --gav <G:A:V>             別の Maven アーティファクトを確認
Check-Maven.cmd --token <TOKEN>           トークンを手動指定（下記の注意を参照）
Check-Maven.cmd --vscode <PATH>           VS Code settings.json のパスを指定
Check-Maven.cmd --proxy <URL>             プロキシを手動指定
Check-Maven.cmd --show-proxy              Windows のシステムプロキシ設定を表示して終了
Check-Maven.cmd --help                    使い方を表示して終了
```

> **`--token` の注意**
> コマンドラインに渡したトークンはプロセス一覧（タスクマネージャー等）と
> コマンド履歴（`doskey /history`）に残る。
> ACB を起動して自動検出させるほうが安全。

> **プロキシ資格情報の表示について**
> `http://user:pass@proxy:8080` のような形式を渡しても、画面と `logs\` には
> `http://***@proxy:8080` とマスクして出力される。

#### --proxy オプション（プロキシ経由での接続）

社内プロキシ経由でないと外部に接続できない環境で使用。

```cmd
Check-Maven.cmd --proxy http://proxy.example.com:8080
```

プロキシは以下の順で決定される:
1. `--proxy` で指定された URL
2. `HTTPS_PROXY` / `https_proxy` 環境変数
3. `HTTP_PROXY` / `http_proxy` 環境変数
4. 指定がなければ直接接続（プロキシなし）

Windows の system proxy 設定（インターネット オプションのプロキシ設定）は自動的には使われない。
`--proxy system` を明示的に指定したときだけ、以下の順にレジストリを検索してその値を使う:

1. `HKCU\...\Internet Settings`（ユーザー設定）
2. `HKLM\...\Internet Settings`（マシン設定）
3. `HKLM\Software\Policies\...\Internet Settings`（グループポリシー配布）

```cmd
Check-Maven.cmd --proxy system
```

Windows がプロキシではなく PAC スクリプト（自動構成スクリプト）を使っている場合、
PAC は自動解決できないため、実際のプロキシ host:port を調べて `--proxy` で指定する必要がある。

#### --show-proxy オプション（Windows のシステムプロキシ設定を表示）

実際に接続を試す前に、Windows に何が設定されているかだけを確認したい場合に使用。
HKCU / HKLM / グループポリシーの `ProxyEnable` / `ProxyServer` / `ProxyOverride` /
`AutoConfigURL`、`netsh winhttp show proxy`（サービスや一部 JVM が使う別系統の設定）、
`HTTPS_PROXY` 系の環境変数を表示して終了する（接続は行わない）。

```cmd
Check-Maven.cmd --show-proxy
```

出力例:
```
============================================================
 Windows proxy settings
============================================================
  HKCU        : ProxyEnable   : 1 (enabled)
                ProxyServer   : http=proxy.example.com:8080;https=proxy.example.com:8443
                ProxyOverride : <local>;*.example.com
                AutoConfigURL : (not set)
  HKLM        : (key does not exist)
  HKLM policy : (key does not exist)

  WinHTTP (used by services and some JVMs; independent of the above):
Current WinHTTP proxy settings:

    Direct access (no proxy server).

  Environment variables:
    HTTPS_PROXY : (not set)
    https_proxy : (not set)
    HTTP_PROXY  : (not set)
    http_proxy  : (not set)
============================================================
```

実行時には必ず使用中のプロキシ（または「direct connection」）を表示する。
`curl 7`（network unreachable）が出る場合、プロキシが必要な環境の可能性が高い。

**`ProxyOverride`（バイパスリスト）は適用されない。**
curl は `-x` で指定されたプロキシに全 URL を送るため、ブラウザでは直結される
ホストもプロキシ経由になる。バイパスリストが設定されている場合は警告として表示する。

#### --asset オプション（テスト 5: API spec ダウンロード）

顧客の Exchange にある API spec のダウンロードをテストする場合に使用。
ACB の「Implement an API Specification」で API spec をダウンロードできない問題を診断する。

```cmd
Check-Maven.cmd --asset my-api-spec
```

- **assetId だけを指定**（Exchange の URL から確認）
- groupId（組織 ID）は `/accounts/api/me` から自動取得
- 指定がない場合、テスト 5 はスキップされる

#### VS Code settings.json の自動検出

以下の順で自動検出（`_Common.cmd` の `:find_vscode`、2 スクリプト共通）:
1. `--vscode` で指定されたパス（フォルダを渡した場合は `User\settings.json` を補う）
2. `%APPDATA%\Code\User\settings.json`（通常版）
3. `%APPDATA%\Code - Insiders\User\settings.json`（Insiders 版）

---

## Check-TLS.cmd

**TLS 証明書チェーンを検査し、社内プロキシの MITM を検出する。**

```cmd
Check-TLS.cmd
Check-TLS.cmd https://repository.mulesoft.org/releases/
Check-TLS.cmd --vscode C:\vscode https://repository.mulesoft.org/releases/
Check-TLS.cmd --proxy http://proxy.example.com:8080 https://repository.mulesoft.org/releases/
Check-TLS.cmd --help
```

URL を指定しない場合、[ACB プロキシ設定ドキュメント](https://docs.mulesoft.com/anypoint-code-builder/ref-proxy-settings) の allowlist に記載された全ホストをチェックする:

- `https://www.google.com`（一般的な接続確認）
- `https://repository.mulesoft.org/releases/`（POM/JAR ダウンロード・公開リポジトリ）
- `https://maven.anypoint.mulesoft.com/api/v3/maven/`（POM/JAR ダウンロード・Exchange 経由）
- `https://anypoint.mulesoft.com/`（Exchange API・組織情報取得）
- `https://exchange2-asset-manager-kprod.s3.amazonaws.com/`（Exchange アセット S3 直接ダウンロード）
- `https://repo.maven.apache.org/maven2/`（Maven Central）
- `https://repo1.maven.org/maven2/`（Maven Central ミラー）
- `https://download.eclipse.org/eclipse/updates/`（Eclipse 拡張アップデート）

`--proxy` の挙動は Check-Maven.cmd と同じ（`--proxy` > 環境変数 > 直接接続）。
`--proxy system` を指定したときだけ Windows の system proxy 設定を検索して使う。
`--show-proxy` で Windows のシステムプロキシ設定を表示して終了することもできる（Check-Maven.cmd と同じ）。

JDK（keytool）は以下の順で自動検出:
1. `settings.json` の `mule.homeDirectory` 配下の JDK（ACB 用）
2. `JAVA_HOME` 環境変数
3. `PATH` の keytool

### 出力例（プロキシ MITM 検出時）

```
============================================================
  https://repository.mulesoft.org/releases/
============================================================
  Certificate chain:
    [0] Subject :  CN=repository.mulesoft.org
         Issuer  :  CN=CompanyProxy-CA, O=YourCorp
    [1] Subject :  CN=CompanyProxy-CA, O=YourCorp
         Issuer  :  CN=CompanyProxy-CA, O=YourCorp
         *** Unknown CA (not in public CA list) ***
  Root CA        : Unknown (corporate proxy or test site)
  Windows cert store : OK
  Java cacerts       : NG - CA not in cacerts (PKIX path building failed)
```

### 判定表

| Root CA | Windows | Java cacerts | 状況 | 対処 |
|---------|---------|--------------|------|------|
| Trusted | OK | OK | 問題なし | — |
| Unknown | OK | OK | プロキシあり、両方で信頼済み | — |
| Unknown | OK | **NG** | プロキシあり、JDK が未信頼 | 下記「解決策」 |
| Trusted | OK | **NG** | プロキシなし、cacerts に CA がない | 下記「解決策」 |
| Unknown | NG | NG | Windows 自体も未信頼 | IT 管理者に依頼 |

---

## ACB-Trace.cmd

**ACB のデバッグトレースを有効化/無効化し、ログをまとめて収集する。**

```cmd
ACB-Trace.cmd --enable              trace設定を settings.json に追加
ACB-Trace.cmd --disable             trace設定を settings.json から削除
ACB-Trace.cmd --status              現在の trace 設定値を表示
ACB-Trace.cmd --collect             ログを logs\ に収集
ACB-Trace.cmd --collect --mask      ログを収集（トークンをマスク）
ACB-Trace.cmd --disable --collect --mask  ログ収集してから無効化（推奨）
ACB-Trace.cmd --acb "C:\path\to\AnypointCodeBuilder"  ACBホームを直接指定
```

### 推奨手順

```
1. ACB-Trace.cmd --enable          ← 有効化
2. VS Code を再起動
3. 問題を再現する
4. ACB-Trace.cmd --disable --collect --mask   ← ログ収集 + 無効化 + マスク
5. logs\ACB-logs-<日時>\ フォルダを確認・共有
```

### 収集されるログ

| ファイル | 内容 |
|----------|------|
| `settings.json` | VS Code の設定（`--mask` でトークンをマスク） |
| `acb-home-logs\ACBLog-*.log` | ACB の warn/error ログ |
| `vscode-exthost\` | VS Code 拡張ホストのデバッグトレース（JSON-RPC 通信含む） |

### --mask オプション

`token`、`refreshToken`、`access_token` の値を `***MASKED***` に置換してからコピーする。
他者に共有する場合は必ず `--mask` を付けること。

### --disable --collect の順序

`--disable --collect` を同時に指定した場合、**ログ収集を先に**実行してから設定を削除する。
trace が有効な状態のログをもれなく収集できる。

---

## Verify-Check-TLS.cmd

**Check-TLS.cmd の動作確認用（ネガティブチェック）**

Check-TLS.cmd が「未知の CA を正しく検出できるか」を確認するスクリプト。

```cmd
Verify-Check-TLS.cmd
```

### 期待される結果

| サイト | Root CA | 意味 |
|--------|---------|------|
| badssl.com | **Trusted** | 正規の証明書を正しく認識 |
| untrusted-root.badssl.com | **Unknown** | 未知 CA を正しく検出（ネガティブチェック） |
| self-signed.badssl.com | **Unknown** | 自己署名を正しく検出（ネガティブチェック） |

- badssl.com = Trusted、他2つ = Unknown なら **Check-TLS.cmd は正常**
- もし全部 Trusted になったら Check-TLS.cmd にバグあり
- **3つとも Unknown になった場合も Check-TLS.cmd は正常**で、
  あなたのネットワークが MITM プロキシ配下にあることを意味する
  （badssl.com の正規証明書までプロキシの CA に差し替えられている）

---

## 解決策

### 方法 A — Java に Windows 証明書ストアを使わせる（推奨）

Java 起動引数に追加:

```
-Djavax.net.ssl.trustStoreType=WINDOWS-ROOT
```

**Anypoint Code Builder の場合:**

VS Code の `settings.json` に追加:

```json
{
  "mule.platform.jvm.args": "-Xms512m -Xmx2g -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -Djavax.net.ssl.trustStoreType=WINDOWS-ROOT"
}
```

### 方法 B — cacerts に社内 CA を直接インポート

```cmd
"%JAVA_HOME%\bin\keytool.exe" -import -alias corporate-ca ^
    -file "C:\path\to\corporate-ca.cer" ^
    -keystore "%JAVA_HOME%\lib\security\cacerts" ^
    -storepass changeit -noprompt
```

**注意:** JDK を更新すると cacerts が上書きされるため、方法 A の方が恒久的。

---

## ライセンス

MIT
