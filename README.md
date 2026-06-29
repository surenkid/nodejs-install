# nodejs-install

一键安装 nodejs, 适配 CI/CD 场景。自动判断 LTS / 最新版, 国内网络自动走腾讯云镜像加速, 下载后做 SHA256 完整性校验。

> Fork 自 [Jrohy/nodejs-install](https://github.com/Jrohy/nodejs-install)

## 使用

### 安装/更新 最新长期支持版 (LTS)
```bash
source <(curl -L https://raw.githubusercontent.com/surenkid/nodejs-install/master/install.sh)
```

国内加速 (通过 gh-proxy.com):
```bash
source <(curl -L https://gh-proxy.com/https://raw.githubusercontent.com/surenkid/nodejs-install/master/install.sh)
```

### 安装/更新 最新当前发布版
```bash
source <(curl -L https://raw.githubusercontent.com/surenkid/nodejs-install/master/install.sh) -l
```

### 安装/更新 指定版本
```bash
source <(curl -L https://raw.githubusercontent.com/surenkid/nodejs-install/master/install.sh) -v 24.18.0
```

### 强制更新
默认同版本不重复安装, 加 `-f` 强制更新:
```bash
source <(curl -L https://raw.githubusercontent.com/surenkid/nodejs-install/master/install.sh) -f
```

## 参数
| 参数 | 说明 |
|------|------|
| `-v, --version <版本>` | 安装指定版本 (如 `24.18.0` 或 `v24.18.0`) |
| `-l` | 安装最新当前发布版 (Current), 默认安装最新 LTS |
| `-f` | 强制更新, 即使已安装相同版本 |

## 特性
- 自动识别最新 LTS / Current 版本 (通过官方 `dist/index.json`)
- 国内网络自动走腾讯云镜像: node 二进制 + npm registry
- HTTP 探测识别网络环境, 兼容禁用 ICMP 的 CI 容器
- 下载后 SHA256 完整性校验
- 零外部依赖, 仅需 `curl` / `grep` / `awk`
