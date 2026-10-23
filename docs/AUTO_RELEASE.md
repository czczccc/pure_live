# 自动发布

合并到 `master` 的每次改动都会自动：

1. `Auto Release` 工作流把 `pubspec.yaml` 的补丁号和构建号各加 1（例如 3.1.19+4108 → 3.1.20+4109），提交 `[skip ci]`。
2. 触发 `PureLive All-Platform Release`，编译安卓和 Windows，发布 GitHub Release `v3.1.20`。
3. 发布成功后更新 `assets/version.json` 和 `assets/releases.json`。已安装的 App 检查更新时读取本仓库的 `version.json`，于是提示升级。

只改 `docs/`、`*.md` 或 `sync_server/` 的提交不会触发发布。

## 一次性配置：安卓签名

发布版必须用固定签名，否则每次的 APK 签名不同，无法覆盖安装。没配置时发布任务会直接失败并提示 `Release signing secrets are required.`

在自己电脑上生成密钥（只做一次，妥善保存 `.jks` 和密码，丢了以后就不能覆盖升级）：

```bash
keytool -genkeypair -v -keystore pure-live-release.jks -alias purelive \
  -keyalg RSA -keysize 2048 -validity 36500
# Windows PowerShell 转 base64：
[Convert]::ToBase64String([IO.File]::ReadAllBytes("pure-live-release.jks")) | Set-Clipboard
# macOS/Linux：
base64 -w0 pure-live-release.jks
```

打开仓库 Settings → Secrets and variables → Actions → New repository secret，添加：

| 名称 | 值 |
|---|---|
| `KEYSTORE_BASE64` | 上面得到的 base64 字符串 |
| `STORE_PASSWORD` | keystore 密码 |
| `KEY_PASSWORD` | key 密码（keytool 没单独设置时与上面相同） |
| `KEY_ALIAS` | `purelive` |

注意：之前装的测试 APK 是 CI 临时调试签名，换成正式签名后需要先卸载一次再安装。卸载前先用服务器同步或备份保存数据。

Windows 的 MSIX 证书（`CERTIFICATE`、`CERTIFICATE_PASSWORD`）可选；不配置时只出安装版 EXE 和便携版 ZIP。

## 手动发布

在 Actions 里手动运行 `Auto Release` 也会走同样流程。
