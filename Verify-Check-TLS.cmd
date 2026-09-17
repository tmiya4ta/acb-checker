@echo off
setlocal enabledelayedexpansion

echo.
echo ============================================================
echo  Check-TLS.cmd 動作確認テスト
echo ============================================================
echo.
echo  このスクリプトは Check-TLS.cmd が正しく動作するかを確認します。
echo  badssl.com のテストサイトを使用します。
echo.
echo  [期待される結果]
echo    badssl.com              : Root CA = Trusted   (正規の証明書)
echo    untrusted-root.badssl.com : Root CA = Unknown   (意図的に未知の CA)
echo    self-signed.badssl.com    : Root CA = Unknown   (意図的に自己署名)
echo.
echo  untrusted-root / self-signed で Unknown が出るのは正常です。
echo  これは「Check-TLS が未知 CA を検出できる」ことの確認です。
echo  (ネガティブチェック: 検出機能が動いている証拠)
echo.
echo  もし全部 Trusted になったら Check-TLS.cmd にバグがあります。
echo ============================================================
echo.
pause

call "%~dp0Check-TLS.cmd" https://badssl.com/ https://untrusted-root.badssl.com/ https://self-signed.badssl.com/

echo.
echo ============================================================
echo  結果の見方
echo ============================================================
echo.
echo  badssl.com が Trusted / 他2つが Unknown なら正常です。
echo  Check-TLS.cmd は正しく動作しています。
echo.
echo  [あなたのネットワークでプロキシ MITM があるかの確認方法]
echo  Check-TLS.cmd https://google.com を実行して:
echo    Root CA = Trusted  : プロキシなし
echo    Root CA = Unknown  : プロキシが MITM している
echo ============================================================

endlocal
