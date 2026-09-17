# acb-checker

Anypoint Code Builder (ACB) の Maven リポジトリ接続問題と、社内プロキシ（MITM）による TLS 証明書問題を診断するツール。

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
  Organization: fbc56842-5b3f-4a52-8d23-ab142791bb47

  Testing Exchange API file download...
  Asset: fbc56842-5b3f-4a52-8d23-ab142791bb47/my-api-spec

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
Check-Maven.cmd --token <TOKEN>           トークンを手動指定
Check-Maven.cmd --vscode <PATH>           VS Code settings.json のパスを指定
Check-Maven.cmd --proxy <URL>             プロキシを手動指定
```

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
`--proxy system` を明示的に指定したときだけ、レジストリを検索してその値を使う。

```cmd
Check-Maven.cmd --proxy system
```

Windows がプロキシではなく PAC スクリプト（自動構成スクリプト）を使っている場合、
PAC は自動解決できないため、実際のプロキシ host:port を調べて `--proxy` で指定する必要がある。

実行時に必ず使用中のプロキシ（または「direct connection」）を表示する。
`curl 7`（network unreachable）が出る場合、プロキシが必要な環境の可能性が高い。

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

以下の順で自動検出:
1. `--vscode` で指定されたパス
2. `%APPDATA%\Code\User\settings.json`（通常版）
3. `%APPDATA%\Code - Insiders\User\settings.json`（Insiders 版）

---

## Check-TLS.cmd

**TLS 証明書チェーンを検査し、社内プロキシの MITM を検出する。**

```cmd
Check-TLS.cmd https://repository.mulesoft.org/releases/
Check-TLS.cmd --vscode C:\vscode https://repository.mulesoft.org/releases/
Check-TLS.cmd --proxy http://proxy.example.com:8080 https://repository.mulesoft.org/releases/
```

`--proxy` の挙動は Check-Maven.cmd と同じ（`--proxy` > 環境変数 > 直接接続）。
`--proxy system` を指定したときだけ Windows の system proxy 設定を検索して使う。

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
