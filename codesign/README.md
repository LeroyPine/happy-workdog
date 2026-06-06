# 本地代码签名材料

这里是 Happy Workdog 用于本地打包的自签名代码签名证书。
**仅供本人在自己机器上使用** — 不是 Apple Developer ID，不能给别人分发用。

## 文件清单

| 文件 | 用途 | 是否进 git |
|---|---|---|
| `cert.pem` | 公钥证书（X.509 PEM） | ✅ 进 git，公开无所谓 |
| `key.pem` | 私钥（RSA 2048） | ❌ `.gitignore` 排除 |
| `hwd-codesign.p12` | 证书+私钥的 PKCS12 打包，导入钥匙串用 | ❌ `.gitignore` 排除 |
| `codesign.cnf` | OpenSSL 生成证书的配置 | ✅ 进 git |
| `README.md` | 本文档 | ✅ 进 git |

PKCS12 密码不要写进公开仓库。下面示例用 `P12_PASSWORD` 环境变量代替。

证书有效期：10 年（生成于 2026-06，到 2036-06）。

## 在新机器上恢复签名身份

把 `key.pem` 和 `hwd-codesign.p12` 通过安全渠道（U 盘 / 1Password / iCloud Drive 等）
拷到新机器，放回 `codesign/` 目录，然后跑：

```bash
cd codesign

# 导入证书+私钥到登录钥匙串
security import hwd-codesign.p12 \
  -k ~/Library/Keychains/login.keychain-db \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -A

# 把证书设为代码签名可信（仅本用户作用域，不需要 sudo）
security add-trusted-cert -d -r trustRoot \
  -p codeSign \
  -k ~/Library/Keychains/login.keychain-db \
  cert.pem
# ↑ 这一步会弹 Touch ID / 密码框，确认即可

# 验证
security find-identity -v -p codesigning
# 应该看到 "Happy Workdog Self-Signed" 一行
```

## 重新生成（万一私钥丢了）

```bash
cd codesign

openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem \
  -days 3650 -nodes -config codesign.cnf

openssl pkcs12 -export -inkey key.pem -in cert.pem \
  -out hwd-codesign.p12 -name "Happy Workdog Self-Signed" \
  -passout env:P12_PASSWORD \
  -legacy
```

⚠️ 注意：换了证书等于换了签名身份，重打包后 macOS 会把 app 当成新 app，
所有 TCC 权限（屏幕录制、辅助功能等）需要重新授权一次。

## 用证书打包

```bash
SIGN_IDENTITY="Happy Workdog Self-Signed" ./scripts/package_app.sh
```

不传 `SIGN_IDENTITY` 会回落到 adhoc 签名（`-`），TCC 权限会在每次重打包后失效，
只适合临时调试。

## 安全提示

- `key.pem` 和 `hwd-codesign.p12` **绝对不要提交到 git** — `.gitignore` 已经排除。
- PKCS12 密码只用于导入流程，私钥本身没有强保护；泄露风险等同于私钥泄露。
  不要把本地私钥或 p12 文件公开传播。
- 这个证书只用来签 `com.luobaosong.happy-workdog`，别拿去签别的东西。
