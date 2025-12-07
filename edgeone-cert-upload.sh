#!/bin/bash

###############################################################################
# 腾讯云 EdgeOne 证书上传脚本
# 
# 用途：将 acme.sh 生成的证书自动上传到腾讯云 EdgeOne
# 
# 使用方法：
#   1. 在 acme.sh 的 reloadcmd 中调用：
#      acme.sh --install-cert -d example.com \
#          --key-file /path/to/key.pem \
#          --fullchain-file /path/to/cert.pem \
#          --reloadcmd "/path/to/edgeone-cert-upload.sh"
#   
#   2. 直接调用（需要提供证书路径）：
#      ./edgeone-cert-upload.sh --domain example.com \
#          --cert-file /path/to/cert.pem \
#          --key-file /path/to/key.pem
#
# 配置文件：~/.edgeone-cert-upload.conf 或 /etc/edgeone-cert-upload.conf
###############################################################################

set -euo pipefail

# 脚本版本
SCRIPT_VERSION="1.0.0"

# 默认配置
DEFAULT_CONFIG_FILE="$HOME/.edgeone-cert-upload.conf"
SYSTEM_CONFIG_FILE="/etc/edgeone-cert-upload.conf"
DEFAULT_LOG_FILE=""
DEFAULT_TCCLI_PATH="tccli"

# 全局变量
DOMAIN=""
CERT_FILE=""
KEY_FILE=""
FULLCHAIN_FILE=""
CA_FILE=""
ZONE_ID=""
SECRET_ID=""
SECRET_KEY=""
TCCLI_PATH="${DEFAULT_TCCLI_PATH}"
LOG_FILE="${DEFAULT_LOG_FILE}"
CERT_ALIAS=""
DRY_RUN=false
VERBOSE=false
FORCE_UPLOAD=false

# 颜色输出（如果支持）
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

###############################################################################
# 日志函数
###############################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[${timestamp}] [${level}] ${message}"
    
    # 输出到标准输出
    case "$level" in
        ERROR)
            echo -e "${RED}${log_entry}${NC}" >&2
            ;;
        WARN)
            echo -e "${YELLOW}${log_entry}${NC}"
            ;;
        INFO)
            echo -e "${GREEN}${log_entry}${NC}"
            ;;
        DEBUG)
            if [[ "$VERBOSE" == "true" ]]; then
                echo -e "${BLUE}${log_entry}${NC}"
            fi
            ;;
        *)
            echo "$log_entry"
            ;;
    esac
    
    # 输出到日志文件（如果指定）
    if [[ -n "$LOG_FILE" ]]; then
        echo "$log_entry" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

log_info() {
    log "INFO" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_debug() {
    log "DEBUG" "$@"
}

###############################################################################
# 工具函数
###############################################################################

# 检查命令是否存在
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "命令不存在: $cmd"
        return 1
    fi
    return 0
}

# 检查文件是否存在且可读
check_file() {
    local file="$1"
    local desc="${2:-文件}"
    
    if [[ ! -f "$file" ]]; then
        log_error "${desc}不存在: $file"
        return 1
    fi
    
    if [[ ! -r "$file" ]]; then
        log_error "${desc}不可读: $file"
        return 1
    fi
    
    return 0
}

# 验证证书文件格式
validate_cert_file() {
    local file="$1"
    local type="$2"  # cert, key, fullchain, ca
    
    if ! check_file "$file" "证书${type}文件"; then
        return 1
    fi
    
    case "$type" in
        cert|fullchain|ca)
            if ! openssl x509 -in "$file" -noout -text &>/dev/null; then
                log_error "证书文件格式无效: $file"
                return 1
            fi
            ;;
        key)
            # 尝试验证 RSA 私钥
            if openssl rsa -in "$file" -check -noout &>/dev/null 2>&1; then
                return 0
            fi
            # 尝试验证 ECC 私钥（openssl ec 不支持 -check 参数）
            if openssl ec -in "$file" -noout &>/dev/null 2>&1; then
                return 0
            fi
            # 尝试验证通用私钥格式（PKCS#8 等）
            if openssl pkey -in "$file" -noout &>/dev/null 2>&1; then
                return 0
            fi
            log_error "私钥文件格式无效: $file"
            return 1
            ;;
    esac
    
    return 0
}

# 读取配置文件
load_config() {
    local config_file=""
    
    # 优先使用用户配置文件，然后是系统配置文件
    if [[ -f "$DEFAULT_CONFIG_FILE" ]]; then
        config_file="$DEFAULT_CONFIG_FILE"
    elif [[ -f "$SYSTEM_CONFIG_FILE" ]]; then
        config_file="$SYSTEM_CONFIG_FILE"
    fi
    
    if [[ -z "$config_file" ]]; then
        log_debug "未找到配置文件，使用默认值或环境变量"
        return 0
    fi
    
    log_debug "加载配置文件: $config_file"
    
    # 读取配置文件（忽略注释和空行）
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 移除前后空白和注释
        line=$(echo "$line" | sed 's/#.*$//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        
        # 跳过空行
        [[ -z "$line" ]] && continue
        
        # 解析配置项
        if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # 移除引号
            value=$(echo "$value" | sed "s/^['\"]//" | sed "s/['\"]$//")
            
            case "$key" in
                ZONE_ID)
                    [[ -z "$ZONE_ID" ]] && ZONE_ID="$value"
                    ;;
                SECRET_ID)
                    [[ -z "$SECRET_ID" ]] && SECRET_ID="$value"
                    ;;
                SECRET_KEY)
                    [[ -z "$SECRET_KEY" ]] && SECRET_KEY="$value"
                    ;;
                TCCLI_PATH)
                    [[ -z "$TCCLI_PATH" ]] && TCCLI_PATH="$value"
                    ;;
                LOG_FILE)
                    [[ -z "$LOG_FILE" ]] && LOG_FILE="$value"
                    ;;
                CERT_ALIAS)
                    [[ -z "$CERT_ALIAS" ]] && CERT_ALIAS="$value"
                    ;;
            esac
        fi
    done < "$config_file"
}

# 从 acme.sh 环境变量获取证书信息
load_acme_env() {
    # acme.sh 会设置以下环境变量
    if [[ -n "${CERT_PATH:-}" ]]; then
        CERT_FILE="${CERT_PATH}"
        log_debug "从环境变量 CERT_PATH 获取证书文件: $CERT_FILE"
    fi
    
    if [[ -n "${CERT_KEY_PATH:-}" ]]; then
        KEY_FILE="${CERT_KEY_PATH}"
        log_debug "从环境变量 CERT_KEY_PATH 获取私钥文件: $KEY_FILE"
    fi
    
    if [[ -n "${CERT_FULLCHAIN_PATH:-}" ]]; then
        FULLCHAIN_FILE="${CERT_FULLCHAIN_PATH}"
        log_debug "从环境变量 CERT_FULLCHAIN_PATH 获取完整链文件: $FULLCHAIN_FILE"
    fi
    
    if [[ -n "${CA_CERT_PATH:-}" ]]; then
        CA_FILE="${CA_CERT_PATH}"
        log_debug "从环境变量 CA_CERT_PATH 获取 CA 文件: $CA_FILE"
    fi
    
    # 从证书文件路径提取域名（如果未指定）
    if [[ -z "$DOMAIN" ]] && [[ -n "$CERT_FILE" ]]; then
        # 尝试从文件路径提取域名（acme.sh 通常会在路径中包含域名）
        local cert_dir=$(dirname "$CERT_FILE")
        local cert_basename=$(basename "$CERT_FILE")
        # 这里可以根据实际情况调整域名提取逻辑
        log_debug "尝试从证书路径提取域名: $CERT_FILE"
    fi
}

# 显示使用帮助
show_help() {
    cat << EOF
腾讯云 EdgeOne 证书上传脚本 v${SCRIPT_VERSION}

用法:
    $0 [选项]

选项:
    -d, --domain DOMAIN           域名，支持多个域名用逗号分隔（必需，除非从 acme.sh 环境变量获取）
    -c, --cert-file FILE          证书文件路径（.crt 或 .pem）
    -k, --key-file FILE           私钥文件路径（.key）
    -f, --fullchain-file FILE     完整证书链文件路径
    --ca-file FILE                CA 证书文件路径
    -z, --zone-id ZONE_ID         EdgeOne Zone ID（必需）
    --secret-id SECRET_ID         腾讯云 Secret ID（必需）
    --secret-key SECRET_KEY       腾讯云 Secret Key（必需）
    --tccli-path PATH             tccli 命令路径（默认: ${DEFAULT_TCCLI_PATH}）
    -l, --log-file FILE           日志文件路径（可选）
    --cert-alias ALIAS            证书别名（可选）
    --config-file FILE            配置文件路径（默认: ~/.edgeone-cert-upload.conf）
    --dry-run                     仅显示将要执行的操作，不实际执行
    -v, --verbose                 详细输出
    --force                       强制上传（即使证书已存在）
    -h, --help                    显示此帮助信息

配置文件格式:
    配置文件支持以下配置项（每行一个，格式为 KEY=VALUE）:
    
    ZONE_ID=your-zone-id
    SECRET_ID=your-secret-id
    SECRET_KEY=your-secret-key
    TCCLI_PATH=/usr/local/bin/tccli
    LOG_FILE=/var/log/edgeone-cert-upload.log
    CERT_ALIAS=MyCertificate

环境变量:
    脚本会自动从 acme.sh 设置的环境变量中读取证书路径:
    - CERT_PATH: 证书文件路径
    - KEY_PATH: 私钥文件路径
    - FULLCHAIN_PATH: 完整证书链文件路径
    - CA_PATH: CA 证书文件路径

示例:
    # 在 acme.sh 中使用
    acme.sh --install-cert -d example.com \\
        --key-file /path/to/key.pem \\
        --fullchain-file /path/to/cert.pem \\
        --reloadcmd "$0"

    # 直接调用（单个域名）
    $0 -d example.com \\
        -c /path/to/cert.pem \\
        -k /path/to/key.pem \\
        -z zone-id \\
        --secret-id secret-id \\
        --secret-key secret-key

    # 直接调用（多个域名，逗号分隔）
    $0 -d "example.com,www.example.com,api.example.com" \\
        -c /path/to/cert.pem \\
        -k /path/to/key.pem \\
        -z zone-id \\
        --secret-id secret-id \\
        --secret-key secret-key

EOF
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--domain)
                DOMAIN="$2"
                shift 2
                ;;
            -c|--cert-file)
                CERT_FILE="$2"
                shift 2
                ;;
            -k|--key-file)
                KEY_FILE="$2"
                shift 2
                ;;
            -f|--fullchain-file)
                FULLCHAIN_FILE="$2"
                shift 2
                ;;
            --ca-file)
                CA_FILE="$2"
                shift 2
                ;;
            -z|--zone-id)
                ZONE_ID="$2"
                shift 2
                ;;
            --secret-id)
                SECRET_ID="$2"
                shift 2
                ;;
            --secret-key)
                SECRET_KEY="$2"
                shift 2
                ;;
            --tccli-path)
                TCCLI_PATH="$2"
                shift 2
                ;;
            -l|--log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            --cert-alias)
                CERT_ALIAS="$2"
                shift 2
                ;;
            --config-file)
                DEFAULT_CONFIG_FILE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --force)
                FORCE_UPLOAD=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 验证必需参数
validate_params() {
    local missing_params=()
    
    # 检查必需参数
    if [[ -z "$ZONE_ID" ]]; then
        missing_params+=("ZONE_ID (--zone-id 或配置文件)")
    fi
    
    if [[ -z "$SECRET_ID" ]]; then
        missing_params+=("SECRET_ID (--secret-id 或配置文件)")
    fi
    
    if [[ -z "$SECRET_KEY" ]]; then
        missing_params+=("SECRET_KEY (--secret-key 或配置文件)")
    fi
    
    # 检查证书文件
    if [[ -z "$FULLCHAIN_FILE" ]] && [[ -z "$CERT_FILE" ]]; then
        missing_params+=("证书文件 (--cert-file 或 --fullchain-file)")
    fi
    
    if [[ -z "$KEY_FILE" ]]; then
        missing_params+=("私钥文件 (--key-file)")
    fi
    
    # 检查域名（如果提供了证书文件，可以尝试从证书中提取）
    if [[ -z "$DOMAIN" ]]; then
        # 尝试从证书文件提取域名
        local cert_file_to_check="${FULLCHAIN_FILE:-$CERT_FILE}"
        if [[ -n "$cert_file_to_check" ]] && [[ -f "$cert_file_to_check" ]]; then
            DOMAIN=$(openssl x509 -in "$cert_file_to_check" -noout -subject 2>/dev/null | \
                     sed -n 's/.*CN=\([^,]*\).*/\1/p' | head -1)
            if [[ -n "$DOMAIN" ]]; then
                log_info "从证书中提取域名: $DOMAIN"
            fi
        fi
        
        if [[ -z "$DOMAIN" ]]; then
            log_warn "未指定域名，将使用证书中的 CN 作为域名"
        fi
    fi
    
    if [[ ${#missing_params[@]} -gt 0 ]]; then
        log_error "缺少必需参数:"
        for param in "${missing_params[@]}"; do
            log_error "  - $param"
        done
        return 1
    fi
    
    return 0
}

# 验证文件
validate_files() {
    local errors=0
    
    # 验证证书文件
    if [[ -n "$FULLCHAIN_FILE" ]]; then
        if ! validate_cert_file "$FULLCHAIN_FILE" "fullchain"; then
            ((errors++))
        fi
    elif [[ -n "$CERT_FILE" ]]; then
        if ! validate_cert_file "$CERT_FILE" "cert"; then
            ((errors++))
        fi
    fi
    
    # 验证私钥文件
    if [[ -n "$KEY_FILE" ]]; then
        if ! validate_cert_file "$KEY_FILE" "key"; then
            ((errors++))
        fi
    fi
    
    # 验证 CA 文件（如果提供）
    if [[ -n "$CA_FILE" ]]; then
        if ! validate_cert_file "$CA_FILE" "ca"; then
            ((errors++))
        fi
    fi
    
    # 验证证书和私钥是否匹配
    if [[ -n "$KEY_FILE" ]]; then
        local cert_file="${FULLCHAIN_FILE:-$CERT_FILE}"
        if [[ -n "$cert_file" ]] && [[ -f "$cert_file" ]] && [[ -f "$KEY_FILE" ]]; then
            # 提取证书中的公钥
            local cert_pubkey=$(openssl x509 -in "$cert_file" -noout -pubkey 2>/dev/null)
            
            if [[ -z "$cert_pubkey" ]]; then
                log_warn "无法从证书中提取公钥，跳过匹配验证"
            else
                # 从私钥提取公钥
                local key_pubkey=$(openssl pkey -in "$KEY_FILE" -pubout 2>/dev/null)
                
                # 如果 openssl pkey 失败，尝试 RSA 或 ECC 特定命令
                if [[ -z "$key_pubkey" ]]; then
                    key_pubkey=$(openssl rsa -in "$KEY_FILE" -pubout 2>/dev/null)
                fi
                
                if [[ -z "$key_pubkey" ]]; then
                    key_pubkey=$(openssl ec -in "$KEY_FILE" -pubout 2>/dev/null)
                fi
                
                if [[ -z "$key_pubkey" ]]; then
                    log_warn "无法从私钥中提取公钥，跳过匹配验证"
                else
                    # 比较公钥是否匹配
                    if [[ "$cert_pubkey" != "$key_pubkey" ]]; then
                        log_error "证书和私钥不匹配！"
                        ((errors++))
                    else
                        log_debug "证书和私钥匹配验证通过"
                    fi
                fi
            fi
        fi
    fi
    
    return $errors
}

# 检查 tccli 工具
check_tccli() {
    if ! check_command "$TCCLI_PATH"; then
        log_error "未找到 tccli 工具: $TCCLI_PATH"
        log_error "请安装腾讯云 CLI 工具: https://cloud.tencent.com/document/product/440/34011"
        return 1
    fi
    
    log_debug "找到 tccli 工具: $TCCLI_PATH"
    return 0
}

# 上传证书到腾讯云 SSL
upload_certificate() {
    local cert_content
    local key_content
    local cert_id=""
    
    # 读取证书内容
    if [[ -n "$FULLCHAIN_FILE" ]]; then
        cert_content=$(cat "$FULLCHAIN_FILE")
    else
        cert_content=$(cat "$CERT_FILE")
        # 如果有 CA 文件，追加到证书内容
        if [[ -n "$CA_FILE" ]]; then
            cert_content="${cert_content}"$'\n'"$(cat "$CA_FILE")"
        fi
    fi
    
    # 读取私钥内容
    key_content=$(cat "$KEY_FILE")
    
    # 生成证书别名（如果未指定）
    local alias="${CERT_ALIAS:-}"
    if [[ -z "$alias" ]]; then
        # 如果多个域名，使用第一个域名
        local first_domain
        if [[ -n "$DOMAIN" ]]; then
            IFS=',' read -ra domains_array <<< "$DOMAIN"
            first_domain=$(echo "${domains_array[0]}" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        fi
        alias="${first_domain:-cert}-$(date +%Y%m%d-%H%M%S)"
    fi
    
    log_info "开始上传证书到腾讯云 SSL..." >&2
    log_debug "证书别名: $alias" >&2
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] 将执行证书上传操作" >&2
        log_debug "[DRY RUN] 证书文件: ${FULLCHAIN_FILE:-$CERT_FILE}" >&2
        log_debug "[DRY RUN] 私钥文件: $KEY_FILE" >&2
        # 干运行模式下也输出一个占位符，保持接口一致性
        echo "DRY_RUN_CERT_ID"
        return 0
    fi
    
    # 设置环境变量
    export TENCENTCLOUD_SECRET_ID="$SECRET_ID"
    export TENCENTCLOUD_SECRET_KEY="$SECRET_KEY"
    
    # 调用 tccli 上传证书
    local response
    response=$("$TCCLI_PATH" ssl UploadCertificate \
        --CertificatePublicKey "$cert_content" \
        --CertificatePrivateKey "$key_content" \
        --Alias "$alias" 2>&1) || {
        # 提取具体的错误信息
        local error_msg=$(echo "$response" | grep -oP '(?<=message:)[^,}]+' | head -1 || echo "")
        local error_code=$(echo "$response" | grep -oP '(?<=code:)[^,}]+' | head -1 || echo "")
        
        if [[ -n "$error_code" ]] && [[ -n "$error_msg" ]]; then
            log_error "证书上传失败：[$error_code] $error_msg" >&2
        else
            log_error "证书上传失败" >&2
            log_error "响应: $response" >&2
        fi
        return 1
    }
    
    # 检查响应中的错误（包括 TencentCloudSDKException）
    if echo "$response" | grep -qiE '"Error"|TencentCloudSDKException|InvalidParameter'; then
        # 提取具体的错误信息
        local error_msg=$(echo "$response" | grep -oP '(?<=message:)[^,}]+' | head -1 || echo "")
        local error_code=$(echo "$response" | grep -oP '(?<=code:)[^,}]+' | head -1 || echo "")
        
        if [[ -n "$error_code" ]] && [[ -n "$error_msg" ]]; then
            log_error "证书上传失败：[$error_code] $error_msg" >&2
        else
            log_error "证书上传失败" >&2
        fi
        log_debug "完整响应: $response" >&2
        return 1
    fi
    
    # 提取证书 ID
    cert_id=$(echo "$response" | grep -oP '(?<="CertificateId": ")[^"]+' | head -1)
    
    if [[ -z "$cert_id" ]]; then
        log_error "无法从响应中提取证书 ID" >&2
        log_error "响应: $response" >&2
        return 1
    fi
    
    log_info "证书上传成功，证书 ID: $cert_id" >&2
    # 只输出证书 ID 到标准输出（用于命令替换）
    echo "$cert_id"
    return 0
}

# 解析逗号分隔的域名列表
parse_domains() {
    local domains_str="$1"
    local -a domains_array=()
    
    if [[ -z "$domains_str" ]]; then
        echo ""
        return 0
    fi
    
    # 使用 IFS 分割逗号分隔的字符串
    IFS=',' read -ra domains_array <<< "$domains_str"
    
    # 清理每个域名的空白字符
    local -a cleaned_domains=()
    for domain in "${domains_array[@]}"; do
        # 移除前后空白
        domain=$(echo "$domain" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        if [[ -n "$domain" ]]; then
            cleaned_domains+=("$domain")
        fi
    done
    
    # 输出为空格分隔的字符串（用于数组）
    echo "${cleaned_domains[*]}"
}

# 构建 JSON 数组（用于域名列表）
build_hosts_json() {
    local domains_str="$1"
    local -a domains_array
    local hosts_json="["
    local first=true
    
    # 解析域名
    IFS=' ' read -ra domains_array <<< "$(parse_domains "$domains_str")"
    
    for domain in "${domains_array[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            hosts_json+=","
        fi
        # JSON 转义：转义双引号和反斜杠
        domain=$(echo "$domain" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
        hosts_json+="\"${domain}\""
    done
    
    hosts_json+="]"
    echo "$hosts_json"
}

# 绑定证书到 EdgeOne
bind_certificate_to_edgeone() {
    local cert_id="$1"
    
    if [[ -z "$cert_id" ]]; then
        log_error "证书 ID 为空，无法绑定"
        return 1
    fi
    
    # 解析域名列表
    local -a domains_array
    IFS=' ' read -ra domains_array <<< "$(parse_domains "$DOMAIN")"
    
    if [[ ${#domains_array[@]} -eq 0 ]]; then
        log_error "未指定域名，无法绑定证书"
        return 1
    fi
    
    log_info "开始将证书绑定到 EdgeOne..."
    log_debug "Zone ID: $ZONE_ID"
    log_debug "域名数量: ${#domains_array[@]}"
    log_debug "域名列表: ${domains_array[*]}"
    log_debug "证书 ID: $cert_id"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] 将执行证书绑定操作"
        log_info "[DRY RUN] 将绑定以下域名: ${domains_array[*]}"
        return 0
    fi
    
    # 设置环境变量
    export TENCENTCLOUD_SECRET_ID="$SECRET_ID"
    export TENCENTCLOUD_SECRET_KEY="$SECRET_KEY"
    
    # 构建 ServerCertInfo JSON
    local server_cert_info="[{\"CertId\":\"${cert_id}\"}]"
    
    # 构建 Hosts JSON 数组（支持多个域名）
    local hosts_json
    hosts_json=$(build_hosts_json "$DOMAIN")
    
    log_debug "Hosts JSON: $hosts_json"
    log_debug "ServerCertInfo JSON: $server_cert_info"
    
    # 调用 tccli 绑定证书
    local response
    response=$("$TCCLI_PATH" teo ModifyHostsCertificate \
        --ZoneId "$ZONE_ID" \
        --Hosts "$hosts_json" \
        --Mode "sslcert" \
        --ServerCertInfo "$server_cert_info" 2>&1) || {
        # 检查是否是域名不存在错误
        if echo "$response" | grep -qi "DomainNotFound\|查询不到指定域名"; then
            log_error "证书绑定失败：以下域名在 EdgeOne 中不存在或不属于当前账号"
            for domain in "${domains_array[@]}"; do
                log_error "  - $domain"
            done
            log_error "请确保："
            log_error "  1. 所有域名已添加到 EdgeOne Zone ID: $ZONE_ID"
            log_error "  2. 域名格式正确（可能需要使用根域名或完整的子域名）"
            log_error "  3. 当前账号拥有这些域名的管理权限"
        else
            log_error "证书绑定失败"
            log_error "响应: $response"
        fi
        return 1
    }
    
    # 检查响应中的错误（包括 TencentCloudSDKException）
    if echo "$response" | grep -qiE '"Error"|TencentCloudSDKException|InvalidParameter'; then
        # 提取具体的错误信息
        local error_msg=$(echo "$response" | grep -oP '(?<=message:)[^,}]+' | head -1 || echo "")
        local error_code=$(echo "$response" | grep -oP '(?<=code:)[^,}]+' | head -1 || echo "")
        
        if [[ -n "$error_code" ]] && [[ -n "$error_msg" ]]; then
            log_error "证书绑定失败：[$error_code] $error_msg"
        else
            log_error "证书绑定失败"
        fi
        
        # 特殊处理域名不存在错误
        if echo "$response" | grep -qi "DomainNotFound\|查询不到指定域名"; then
            log_error "请确保以下域名已添加到 EdgeOne Zone ID: $ZONE_ID"
            for domain in "${domains_array[@]}"; do
                log_error "  - $domain"
            done
        fi
        
        log_debug "完整响应: $response"
        return 1
    fi
    
    log_info "证书绑定成功"
    return 0
}

# 主函数
main() {
    log_info "=========================================="
    log_info "腾讯云 EdgeOne 证书上传脚本 v${SCRIPT_VERSION}"
    log_info "=========================================="
    
    # 加载配置
    load_config
    
    # 从 acme.sh 环境变量加载
    load_acme_env
    
    # 解析命令行参数
    parse_args "$@"
    
    # 验证参数
    if ! validate_params; then
        exit 1
    fi
    
    # 验证文件
    if ! validate_files; then
        exit 1
    fi
    
    # 检查 tccli
    if ! check_tccli; then
        exit 1
    fi
    
    # 显示配置信息
    log_info "配置信息:"
    if [[ -n "$DOMAIN" ]]; then
        local -a domains_array
        IFS=' ' read -ra domains_array <<< "$(parse_domains "$DOMAIN")"
        if [[ ${#domains_array[@]} -gt 1 ]]; then
            log_info "  域名 (${#domains_array[@]}个): ${domains_array[*]}"
        else
            log_info "  域名: ${DOMAIN}"
        fi
    else
        log_info "  域名: 未指定"
    fi
    log_info "  证书文件: ${FULLCHAIN_FILE:-$CERT_FILE}"
    log_info "  私钥文件: $KEY_FILE"
    log_info "  Zone ID: $ZONE_ID"
    if [[ -n "$LOG_FILE" ]]; then
        log_info "  日志文件: $LOG_FILE"
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "  模式: 干运行（不会实际执行）"
    fi
    
    # 上传证书
    local cert_id
    cert_id=$(upload_certificate) || {
        log_error "证书上传过程失败"
        exit 1
    }
    
    # 绑定证书到 EdgeOne
    if [[ -n "$cert_id" ]] && [[ "$DRY_RUN" != "true" ]]; then
        bind_certificate_to_edgeone "$cert_id" || {
            log_error "证书绑定过程失败"
            exit 1
        }
    fi
    
    log_info "=========================================="
    log_info "证书上传和绑定完成！"
    log_info "=========================================="
}

# 执行主函数
main "$@"

