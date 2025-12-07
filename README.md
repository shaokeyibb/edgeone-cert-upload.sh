# 腾讯云 EdgeOne 证书上传脚本

这是一个用于将 acme.sh 生成的 SSL 证书自动上传到腾讯云 EdgeOne 的 Bash 脚本。

## 功能特性

- ✅ 支持从 acme.sh 自动获取证书信息
- ✅ 支持命令行参数和配置文件两种配置方式
- ✅ 完善的错误处理和边界情况检查
- ✅ 支持日志输出到标准输出和日志文件
- ✅ 支持干运行模式（dry-run）
- ✅ 自动验证证书和私钥的匹配性
- ✅ 支持详细输出模式（verbose）
- ✅ 高度可配置化

## 前置要求

1. **安装腾讯云 CLI 工具 (tccli)**
   
   参考官方文档：https://cloud.tencent.com/document/product/440/34011
   
   ```bash
   pip install tccli
   ```

2. **获取腾讯云 API 密钥**
   
   在腾讯云控制台 -> 访问管理 -> API密钥管理 中创建密钥对

3. **获取 EdgeOne Zone ID**
   
   在腾讯云 EdgeOne 控制台中找到您的 Zone ID

4. **安装 openssl**（用于验证证书格式）

## 安装

1. 下载脚本：
   ```bash
   wget https://raw.githubusercontent.com/shaokeyibb/edgeone-cert-upload.sh/main/edgeone-cert-upload.sh
   chmod +x edgeone-cert-upload.sh
   ```

2. （可选）创建配置文件：
   ```bash
   cp edgeone-cert-upload.conf.example ~/.edgeone-cert-upload.conf
   # 编辑配置文件，填入您的配置信息
   vim ~/.edgeone-cert-upload.conf
   ```

## 使用方法

### 方法一：在 acme.sh 中使用（推荐）

在 acme.sh 的 `--reloadcmd` 参数中调用此脚本：

```bash
acme.sh --install-cert -d example.com \
    --key-file /path/to/private.key \
    --fullchain-file /path/to/fullchain.cer \
    --reloadcmd "/path/to/edgeone-cert-upload.sh"
```

acme.sh 会自动设置以下环境变量，脚本会自动读取：
- `CERT_PATH`: 证书文件路径
- `CERT_KEY_PATH`: 私钥文件路径
- `CERT_FULLCHAIN_PATH`: 完整证书链文件路径
- `CA_CERT_PATH`: CA 证书文件路径

### 方法二：直接调用

```bash
./edgeone-cert-upload.sh \
    --domain example.com \
    --cert-file /path/to/cert.pem \
    --key-file /path/to/key.pem \
    --zone-id your-zone-id \
    --secret-id your-secret-id \
    --secret-key your-secret-key
```

### 方法三：使用配置文件

1. 创建配置文件 `~/.edgeone-cert-upload.conf`：
   ```bash
   ZONE_ID=your-zone-id
   SECRET_ID=your-secret-id
   SECRET_KEY=your-secret-key
   LOG_FILE=/var/log/edgeone-cert-upload.log
   ```

2. 调用脚本（只需提供证书路径）：
   ```bash
   ./edgeone-cert-upload.sh \
       --domain example.com \
       --cert-file /path/to/cert.pem \
       --key-file /path/to/key.pem
   ```

## 配置说明

### 命令行参数

| 参数 | 说明 | 必需 |
|------|------|------|
| `-d, --domain DOMAIN` | 域名 | 否* |
| `-c, --cert-file FILE` | 证书文件路径 | 是* |
| `-k, --key-file FILE` | 私钥文件路径 | 是 |
| `-f, --fullchain-file FILE` | 完整证书链文件路径 | 否* |
| `--ca-file FILE` | CA 证书文件路径 | 否 |
| `-z, --zone-id ZONE_ID` | EdgeOne Zone ID | 是 |
| `--secret-id SECRET_ID` | 腾讯云 Secret ID | 是 |
| `--secret-key SECRET_KEY` | 腾讯云 Secret Key | 是 |
| `--tccli-path PATH` | tccli 命令路径 | 否 |
| `-l, --log-file FILE` | 日志文件路径 | 否 |
| `--cert-alias ALIAS` | 证书别名 | 否 |
| `--config-file FILE` | 配置文件路径 | 否 |
| `--dry-run` | 干运行模式 | 否 |
| `-v, --verbose` | 详细输出 | 否 |
| `--force` | 强制上传 | 否 |
| `-h, --help` | 显示帮助信息 | 否 |

*注：证书文件（`--cert-file` 或 `--fullchain-file`）和域名（`--domain`）至少提供一个。如果未提供域名，脚本会尝试从证书中提取。

### 配置文件

配置文件支持以下配置项：

```bash
# EdgeOne Zone ID（必需）
ZONE_ID=your-zone-id

# 腾讯云 API 密钥（必需）
SECRET_ID=your-secret-id
SECRET_KEY=your-secret-key

# tccli 命令路径（可选，默认: tccli）
TCCLI_PATH=tccli

# 日志文件路径（可选）
LOG_FILE=/var/log/edgeone-cert-upload.log

# 证书别名（可选）
CERT_ALIAS=MyCertificate
```

配置文件优先级：
1. 命令行参数（最高优先级）
2. 用户配置文件 `~/.edgeone-cert-upload.conf`
3. 系统配置文件 `/etc/edgeone-cert-upload.conf`
4. 默认值

## 日志

脚本支持两种日志输出方式：

1. **标准输出**：所有日志都会输出到标准输出（支持颜色）
2. **日志文件**：如果指定了 `--log-file` 或配置文件中的 `LOG_FILE`，日志会同时写入文件

日志级别：
- `INFO`: 一般信息（绿色）
- `WARN`: 警告信息（黄色）
- `ERROR`: 错误信息（红色）
- `DEBUG`: 调试信息（蓝色，仅在 verbose 模式下显示）

## 示例

### 示例 1：基本使用

```bash
./edgeone-cert-upload.sh \
    -d example.com \
    -c /etc/ssl/certs/example.com.crt \
    -k /etc/ssl/private/example.com.key \
    -z zone-123456 \
    --secret-id AKIDxxxxx \
    --secret-key xxxxx
```

### 示例 2：使用完整证书链

```bash
./edgeone-cert-upload.sh \
    -d example.com \
    -f /etc/ssl/certs/example.com-fullchain.crt \
    -k /etc/ssl/private/example.com.key \
    -z zone-123456 \
    --secret-id AKIDxxxxx \
    --secret-key xxxxx
```

### 示例 3：在 acme.sh 中使用

```bash
# 编辑 acme.sh 的配置
acme.sh --install-cert -d example.com \
    --key-file /root/.acme.sh/example.com/example.com.key \
    --fullchain-file /root/.acme.sh/example.com/fullchain.cer \
    --reloadcmd "/path/to/edgeone-cert-upload.sh"
```

### 示例 4：干运行模式

```bash
./edgeone-cert-upload.sh \
    -d example.com \
    -c /path/to/cert.pem \
    -k /path/to/key.pem \
    -z zone-123456 \
    --secret-id AKIDxxxxx \
    --secret-key xxxxx \
    --dry-run \
    --verbose
```

## 错误处理

脚本包含完善的错误处理机制：

1. **参数验证**：检查所有必需参数是否提供
2. **文件验证**：检查证书和私钥文件是否存在、可读
3. **格式验证**：使用 openssl 验证证书和私钥格式
4. **匹配验证**：验证证书和私钥是否匹配
5. **工具检查**：检查 tccli 工具是否安装
6. **API 错误处理**：检查腾讯云 API 调用是否成功

## 故障排查

### 问题 1：找不到 tccli 命令

**解决方案**：
```bash
# 安装 tccli
pip install tccli

# 或指定完整路径
./edgeone-cert-upload.sh --tccli-path /usr/local/bin/tccli ...
```

### 问题 2：证书上传失败

**可能原因**：
- API 密钥无效
- 证书格式不正确
- 网络连接问题

**解决方案**：
- 检查 API 密钥是否正确
- 使用 `--verbose` 参数查看详细错误信息
- 检查证书文件格式

### 问题 3：证书绑定失败

**可能原因**：
- Zone ID 不正确
- 域名不在该 Zone 中
- 证书 ID 无效

**解决方案**：
- 确认 Zone ID 正确
- 确认域名已添加到 EdgeOne
- 查看详细错误信息

## 安全建议

1. **保护 API 密钥**：
   - 使用配置文件时，设置适当的文件权限：`chmod 600 ~/.edgeone-cert-upload.conf`
   - 不要将配置文件提交到版本控制系统

2. **保护私钥文件**：
   - 确保私钥文件权限正确：`chmod 600 /path/to/key.pem`
   - 不要将私钥文件暴露在公共位置

3. **使用最小权限原则**：
   - 为脚本创建专用的 API 密钥，只授予必要的权限

## 许可证

EdgeOne Cert Upload is licensed under the [MIT License](LICENSE.txt).
