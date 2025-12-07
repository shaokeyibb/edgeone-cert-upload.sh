# 快速使用指南

## 快速开始

### 1. 准备配置文件

```bash
# 复制示例配置文件
cp edgeone-cert-upload.conf.example ~/.edgeone-cert-upload.conf

# 编辑配置文件
vim ~/.edgeone-cert-upload.conf
```

填入以下必需信息：
- `ZONE_ID`: 您的 EdgeOne Zone ID
- `SECRET_ID`: 腾讯云 API Secret ID
- `SECRET_KEY`: 腾讯云 API Secret Key

### 2. 在 acme.sh 中配置

```bash
acme.sh --install-cert -d example.com \
    --key-file /root/.acme.sh/example.com/example.com.key \
    --fullchain-file /root/.acme.sh/example.com/fullchain.cer \
    --reloadcmd "/path/to/edgeone-cert-upload.sh"
```

### 3. 测试（干运行模式）

```bash
./edgeone-cert-upload.sh \
    -d example.com \
    -c /path/to/cert.pem \
    -k /path/to/key.pem \
    --dry-run \
    --verbose
```

## 常见场景

### 场景 1：首次配置

```bash
# 1. 创建配置文件
cat > ~/.edgeone-cert-upload.conf << EOF
ZONE_ID=zone-1234567890
SECRET_ID=AKIDxxxxxxxxxxxxxxxxxxxx
SECRET_KEY=xxxxxxxxxxxxxxxxxxxxxxxx
LOG_FILE=/var/log/edgeone-cert-upload.log
EOF

# 2. 设置权限
chmod 600 ~/.edgeone-cert-upload.conf

# 3. 测试配置
./edgeone-cert-upload.sh \
    -d example.com \
    -c /path/to/cert.pem \
    -k /path/to/key.pem \
    --dry-run
```

### 场景 2：多个域名

为每个域名创建单独的配置或使用不同的证书别名：

```bash
# 方式 1：使用不同的证书别名
./edgeone-cert-upload.sh \
    -d example1.com \
    -c /path/to/example1.com.crt \
    -k /path/to/example1.com.key \
    --cert-alias example1-com-cert

./edgeone-cert-upload.sh \
    -d example2.com \
    -c /path/to/example2.com.crt \
    -k /path/to/example2.com.key \
    --cert-alias example2-com-cert
```

### 场景 3：自动化部署

在 acme.sh 中配置后，每次证书更新时自动上传：

```bash
# acme.sh 会在证书更新后自动调用 reloadcmd
acme.sh --renew -d example.com
```

## 故障排查命令

```bash
# 1. 检查脚本语法
bash -n edgeone-cert-upload.sh

# 2. 检查 tccli 是否安装
which tccli
tccli --version

# 3. 测试 API 连接
export TENCENTCLOUD_SECRET_ID=your-secret-id
export TENCENTCLOUD_SECRET_KEY=your-secret-key
tccli ssl DescribeCertificates

# 4. 验证证书格式
openssl x509 -in /path/to/cert.pem -noout -text
openssl rsa -in /path/to/key.pem -check -noout

# 5. 查看详细日志
./edgeone-cert-upload.sh ... --verbose --log-file /tmp/test.log
cat /tmp/test.log
```

## 注意事项

1. **首次使用前务必测试**：使用 `--dry-run` 参数测试配置是否正确
2. **保护敏感信息**：配置文件包含 API 密钥，务必设置正确的文件权限
3. **日志文件权限**：确保脚本有权限写入日志文件
4. **证书路径**：确保脚本有权限读取证书和私钥文件

