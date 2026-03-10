#!/bin/bash

# Cloudflare DDNS 更新脚本 (多主域名 + 独立小黄云控制 + 自动依赖)

CFG_DIR="$HOME/.cloudflare_ddns"
CONFIG_FILE="$CFG_DIR/config"

# 日志函数
log() {
    local msg="$1"
    local log_only=${2:-0}
    local log_entry="$(date +'%Y-%m-%d %H:%M:%S') - $msg"
    echo "$log_entry" >> "$LOG_FILE"
    if [[ $log_only -eq 0 ]]; then
        echo "$log_entry"
    fi
}

create_config_dir() {
    if [ ! -d "$CFG_DIR" ]; then
        mkdir -p "$CFG_DIR"
        chmod 700 "$CFG_DIR"
    fi
}

delete_config() {
    local config_dir=$(dirname "$CONFIG_FILE")
    local deleted_files=()
    if [ -f "$CONFIG_FILE" ]; then
        rm -f "$CONFIG_FILE"
        deleted_files+=("配置文件: $CONFIG_FILE")
    fi
    if [ -f "$LOG_FILE" ]; then
        rm -f "$LOG_FILE"
        deleted_files+=("日志文件: $LOG_FILE")
    fi
    if [ -d "$config_dir" ]; then
        rmdir "$config_dir" 2>/dev/null && deleted_files+=("配置目录: $config_dir")
    fi
    if [ ${#deleted_files[@]} -gt 0 ]; then
        echo "✅ 已删除以下文件:"
        for file in "${deleted_files[@]}"; do
            echo "  - $file"
        done
    else
        echo "⚠️ 未找到配置文件或日志文件"
    fi
}

init_config() {
    create_config_dir

    usage() {
        echo
        echo "Cloudflare DDNS 更新脚本 (多域名版)"
        echo
        echo "option:"
        echo "  -h, --help            显示此帮助信息"
        echo "  -reconfig             重置配置文件并重新配置"
        echo "  -delete               删除所有配置和日志文件"
    }
    
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -delete)
            delete_config
            exit 0
            ;;
        -reconfig)
            if [ -f "$CONFIG_FILE" ]; then
                rm -f "$CONFIG_FILE"
                echo "✅ 配置已重置，请重新运行脚本进行配置"
                exit 0
            else
                echo "配置文件不存在，无需重置"
                exit 0
            fi
            ;;
    esac
    
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        log "已加载配置文件: $CONFIG_FILE" 1
        return 0
    fi
    
    LOG_FILE="${CFG_DIR}/cloudflare_ddns.log"
    
    clear
    echo "╔══════════════════════════════════════════════════╗"
    echo "║        Cloudflare DDNS 多域名配置向导            ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo "提示：此版本支持同时更新多个主域名的 DNS 记录"
    echo "──────────────────────────────────────────────────"
    
    read -p "1. 请输入Cloudflare API Token: " API_TOKEN
    [ -z "$API_TOKEN" ] && { echo "错误：API Token不能为空！"; exit 1; }
    
    read -p "2. 全局记录类型 [A/AAAA] (默认: A): " RECORD_TYPE
    RECORD_TYPE=${RECORD_TYPE:-A}
    
    read -p "3. 全局TTL值 [1-86400] (默认: 60): " TTL
    TTL=${TTL:-60}

    echo "──────────────────────────────────────────────────"
    echo "接下来开始配置主域名 (Zone)。你可以添加多个不同的主域名。"
    
    # 声明存储各个Zone配置的数组
    declare -a ZONE_IDS=()
    declare -a ZONE_REMARKS=()
    declare -a RECORD_NAMES=()
    declare -a PROXIED_SETTINGS=()

    local zone_count=1
    while true; do
        echo
        echo "▶ 正在配置第 $zone_count 个主域名："
        
        read -p "  输入 Zone ID: " current_zone_id
        [ -z "$current_zone_id" ] && { echo "  ❌ Zone ID 不能为空，请重新输入。"; continue; }
        
        read -p "  输入该域名的备注 (如 example.com): " current_remark
        current_remark=${current_remark:-"未命名域名_$zone_count"}
        
        read -p "  输入该 Zone 下要更新的子域名 (多个用逗号分隔，如 mail.example.com,ddns.example.com): " current_records
        [ -z "$current_records" ] && { echo "  ❌ 子域名不能为空，请重新配置当前 Zone。"; continue; }
        
        read -p "  对应的代理状态(小黄云) (多个用逗号分隔，如 false,true) (默认: false): " current_proxieds
        current_proxieds=${current_proxieds:-false}

        # 将当前输入的数据存入数组
        ZONE_IDS+=("$current_zone_id")
        ZONE_REMARKS+=("$current_remark")
        RECORD_NAMES+=("$current_records")
        PROXIED_SETTINGS+=("$current_proxieds")

        echo "  ✅ 第 $zone_count 个主域名 [$current_remark] 配置已记录。"
        
        echo "──────────────────────────────────────────────────"
        read -p "❓ 是否需要继续添加另一个主域名(Zone ID)? [y/N]: " add_more
        case "$add_more" in
            [yY][eE][sS]|[yY])
                ((zone_count++))
                ;;
            *)
                break
                ;;
        esac
    done
    
    echo "──────────────────────────────────────────────────"
    read -p "4. 日志文件路径 (默认: ${CFG_DIR}/cloudflare_ddns.log): " input_log
    LOG_FILE=${input_log:-"${CFG_DIR}/cloudflare_ddns.log"}
    
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "===== DDNS 多域名配置创建于 $(date) =====" > "$LOG_FILE"
    
    # 将配置写入文件，使用 declare -p 完美保存 Bash 数组结构
    echo "#!/bin/bash" > "$CONFIG_FILE"
    echo "# Cloudflare DDNS 配置文件 (多域名版)" >> "$CONFIG_FILE"
    echo "API_TOKEN='$API_TOKEN'" >> "$CONFIG_FILE"
    echo "RECORD_TYPE='$RECORD_TYPE'" >> "$CONFIG_FILE"
    echo "TTL='$TTL'" >> "$CONFIG_FILE"
    echo "LOG_FILE='$LOG_FILE'" >> "$CONFIG_FILE"
    echo "" >> "$CONFIG_FILE"
    echo "$(declare -p ZONE_IDS)" >> "$CONFIG_FILE"
    echo "$(declare -p ZONE_REMARKS)" >> "$CONFIG_FILE"
    echo "$(declare -p RECORD_NAMES)" >> "$CONFIG_FILE"
    echo "$(declare -p PROXIED_SETTINGS)" >> "$CONFIG_FILE"
    
    chmod 600 "$CONFIG_FILE"
    
    echo "✅ 所有配置已保存到: $CONFIG_FILE"
}

get_ip() {
    local ip_services
    local max_retry=3
    
    if [ "$RECORD_TYPE" = "A" ]; then
        ip_services=("https://api.ipify.org" "https://ipv4.icanhazip.com" "https://checkip.amazonaws.com")
    else
        ip_services=("https://api64.ipify.org" "https://ipv6.icanhazip.com" "https://v6.ident.me")
    fi
    
    for service in "${ip_services[@]}"; do
        for ((i=1; i<=max_retry; i++)); do
            ip=$(curl -${RECORD_TYPE/#A/4} -s --fail --max-time 10 "$service" 2>/dev/null)
            if [ -n "$ip" ]; then
                echo "$ip"
                return 0
            fi
            sleep 1
        done
    done
    return 1
}

cf_api_request() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    # 注意：这里使用全局变量 $CURRENT_ZONE_ID 进行动态替换
    local url="https://api.cloudflare.com/client/v4/zones/$CURRENT_ZONE_ID/$endpoint"
    
    local curl_cmd="curl -s -X $method '$url' \
        -H 'Authorization: Bearer $API_TOKEN' \
        -H 'Content-Type: application/json'"
    
    [ -n "$data" ] && curl_cmd+=" --data '$data'"
    eval "$curl_cmd"
}

main() {
    init_config "$@"
    
    log "===== DDNS 多域名批量更新任务开始 ====="
    
    # 获取公网IP (只需要获取一次)
    log "正在获取公网IP地址..." 1
    CURRENT_IP=$(get_ip)
    if [ -z "$CURRENT_IP" ]; then
        log "❌ 错误：无法获取公网IP地址，请检查网络连接"
        log "===== DDNS 更新失败 ====="
        return 1
    fi
    log "当前公网IP: $CURRENT_IP"
    
    # 遍历所有保存的 Zone ID
    for idx in "${!ZONE_IDS[@]}"; do
        CURRENT_ZONE_ID="${ZONE_IDS[$idx]}"
        REMARK="${ZONE_REMARKS[$idx]}"
        RECORDS_STR="${RECORD_NAMES[$idx]}"
        PROXIED_STR="${PROXIED_SETTINGS[$idx]}"
        
        log "========================================"
        log "🌐 开始处理主域名: $REMARK"
        
        # 将当前 Zone 的记录和代理状态转换为数组
        RECORD_NAMES_ARRAY=(${RECORDS_STR//,/ })
        PROXIED_ARRAY=(${PROXIED_STR//,/ })
        
        # 循环处理当前 Zone 下的每一个子域名
        for j in "${!RECORD_NAMES_ARRAY[@]}"; do
            current_domain="${RECORD_NAMES_ARRAY[$j]}"
            current_proxied="${PROXIED_ARRAY[$j]:-false}"
            
            log "-----------------"
            log "⏳ 正在检查: $current_domain (小黄云: $current_proxied)"
            
            RECORD_INFO=$(cf_api_request "GET" "dns_records?name=$current_domain&type=$RECORD_TYPE")
            
            if ! jq -e '.success' <<< "$RECORD_INFO" >/dev/null; then
                ERROR_MSG=$(jq -r '.errors[0].message' <<< "$RECORD_INFO" 2>/dev/null || echo "未知错误")
                log "❌ [$current_domain] API错误: $ERROR_MSG"
                continue 
            fi
            
            RECORD_COUNT=$(jq -r '.result | length' <<< "$RECORD_INFO")
            
            # 如果记录不存在，直接创建
            if [ "$RECORD_COUNT" -eq 0 ] || [ "$RECORD_COUNT" = "null" ]; then
                log "⚠️ 未找到记录，正在创建..."
                CREATE_DATA="{\"type\":\"$RECORD_TYPE\",\"name\":\"$current_domain\",\"content\":\"$CURRENT_IP\",\"ttl\":$TTL,\"proxied\":$current_proxied}"
                CREATE_RESULT=$(cf_api_request "POST" "dns_records" "$CREATE_DATA")
                
                if jq -e '.success' <<< "$CREATE_RESULT" >/dev/null; then
                    log "✅ 创建成功 -> $CURRENT_IP"
                else
                    ERROR_MSG=$(jq -r '.errors[0].message' <<< "$CREATE_RESULT" 2>/dev/null || echo "未知错误")
                    log "❌ 创建失败: $ERROR_MSG"
                fi
                continue
            fi
            
            # 记录已存在，获取当前的 IP 和 小黄云状态
            RECORD_ID=$(jq -r '.result[0].id' <<< "$RECORD_INFO")
            EXISTING_IP=$(jq -r '.result[0].content' <<< "$RECORD_INFO")
            EXISTING_PROXIED=$(jq -r '.result[0].proxied' <<< "$RECORD_INFO")
            
            # 校验是否需要更新
            if [ "$CURRENT_IP" = "$EXISTING_IP" ] && [ "$current_proxied" = "$EXISTING_PROXIED" ]; then
                log "🔄 无需更新 (IP与状态一致)"
            else
                log "🔄 正在更新 (IP: $EXISTING_IP → $CURRENT_IP | 小黄云: $EXISTING_PROXIED → $current_proxied)"
                UPDATE_DATA="{\"type\":\"$RECORD_TYPE\",\"name\":\"$current_domain\",\"content\":\"$CURRENT_IP\",\"ttl\":$TTL,\"proxied\":$current_proxied}"
                UPDATE_RESULT=$(cf_api_request "PUT" "dns_records/$RECORD_ID" "$UPDATE_DATA")
                
                if jq -e '.success' <<< "$UPDATE_RESULT" >/dev/null; then
                    log "✅ 更新成功"
                else
                    ERROR_MSG=$(jq -r '.errors[0].message' <<< "$UPDATE_RESULT" 2>/dev/null || echo "未知错误")
                    log "❌ 更新失败: $ERROR_MSG"
                fi
            fi
        done
    done
    
    log "========================================"
    log "===== DDNS 批量更新任务完成 ====="
}

# 自动检查并安装依赖函数
check_dependencies() {
    local deps=("curl" "jq")
    local missing_deps=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "⚠️ 检测到缺少依赖项: ${missing_deps[*]}"
        echo "⏳ 正在尝试自动下载并安装..."

        local SUDO=""
        if [ "$EUID" -ne 0 ]; then
            if command -v sudo &> /dev/null; then
                SUDO="sudo"
            else
                echo "❌ 错误：当前不是 root 用户且未找到 sudo 命令。请手动安装: ${missing_deps[*]}"
                exit 1
            fi
        fi

        if command -v apt-get &> /dev/null; then
            $SUDO apt-get update -yq >/dev/null 2>&1
            $SUDO apt-get install -yq "${missing_deps[@]}" >/dev/null 2>&1
        elif command -v yum &> /dev/null; then
            $SUDO yum install -yq "${missing_deps[@]}" >/dev/null 2>&1
        elif command -v dnf &> /dev/null; then
            $SUDO dnf install -yq "${missing_deps[@]}" >/dev/null 2>&1
        elif command -v apk &> /dev/null; then
            $SUDO apk add --no-cache "${missing_deps[@]}" >/dev/null 2>&1
        elif command -v pacman &> /dev/null; then
            $SUDO pacman -Sy --noconfirm "${missing_deps[@]}" >/dev/null 2>&1
        else
            echo "❌ 错误：未知的系统包管理器，请手动安装依赖: ${missing_deps[*]}"
            exit 1
        fi

        for dep in "${missing_deps[@]}"; do
            if ! command -v "$dep" &> /dev/null; then
                echo "❌ 错误：自动安装 $dep 失败，请检查网络或手动安装。"
                exit 1
            fi
        done
        echo "✅ 依赖项 ${missing_deps[*]} 自动安装成功！"
        echo "──────────────────────────────────────────────────"
    fi
}

check_dependencies
main "$@"
