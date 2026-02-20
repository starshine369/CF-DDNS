#!/bin/bash

# Cloudflare DDNS 更新脚本 (多域名 + 独立小黄云控制版)

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
        echo "Cloudflare DDNS 更新脚本"
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
    echo "║           Cloudflare DDNS 配置向导               ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo "提示：括号内为默认值，直接按回车使用默认设置"
    echo "──────────────────────────────────────────────────"
    
    read -p "1. 请输入Cloudflare API Token: " API_TOKEN
    [ -z "$API_TOKEN" ] && { echo "错误：API Token不能为空！"; exit 1; }
    
    read -p "2. 请输入Zone ID: " ZONE_ID
    [ -z "$ZONE_ID" ] && { echo "错误：Zone ID不能为空！"; exit 1; }
    
    read -p "3. 请输入要更新的域名(多个域名用逗号分隔，如 a.com,b.com): " RECORD_NAME
    RECORD_NAME=${RECORD_NAME:-ddns.example.com}
    
    read -p "4. 记录类型 [A/AAAA] (默认: A): " RECORD_TYPE
    RECORD_TYPE=${RECORD_TYPE:-A}
    
    read -p "5. TTL值 [1-86400] (默认: 60): " TTL
    TTL=${TTL:-60}

    read -p "6. 是否开启代理(小黄云) (多个用逗号分隔，如 false,true) (默认: false): " PROXIED
    PROXIED=${PROXIED:-false}
    
    read -p "7. 日志文件路径 (默认: ${CFG_DIR}/cloudflare_ddns.log): " input_log
    LOG_FILE=${input_log:-"${CFG_DIR}/cloudflare_ddns.log"}
    
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "===== DDNS 配置创建于 $(date) =====" > "$LOG_FILE"
    
    echo "#!/bin/bash" > "$CONFIG_FILE"
    echo "# Cloudflare DDNS 配置文件" >> "$CONFIG_FILE"
    echo "API_TOKEN='$API_TOKEN'" >> "$CONFIG_FILE"
    echo "ZONE_ID='$ZONE_ID'" >> "$CONFIG_FILE"
    echo "RECORD_NAME='$RECORD_NAME'" >> "$CONFIG_FILE"
    echo "RECORD_TYPE='$RECORD_TYPE'" >> "$CONFIG_FILE"
    echo "TTL='$TTL'" >> "$CONFIG_FILE"
    echo "PROXIED='$PROXIED'" >> "$CONFIG_FILE"
    echo "LOG_FILE='$LOG_FILE'" >> "$CONFIG_FILE"
    
    chmod 600 "$CONFIG_FILE"
    
    echo "──────────────────────────────────────────────────"
    echo "✅ 配置已保存到: $CONFIG_FILE"
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
    local url="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/$endpoint"
    
    local curl_cmd="curl -s -X $method '$url' \
        -H 'Authorization: Bearer $API_TOKEN' \
        -H 'Content-Type: application/json'"
    
    [ -n "$data" ] && curl_cmd+=" --data '$data'"
    eval "$curl_cmd"
}

main() {
    init_config "$@"
    PROXIED=${PROXIED:-false}
    
    log "===== DDNS 批量更新任务开始 ====="
    
    # 获取公网IP
    log "正在获取公网IP地址..." 1
    CURRENT_IP=$(get_ip)
    if [ -z "$CURRENT_IP" ]; then
        log "❌ 错误：无法获取公网IP地址，请检查网络连接"
        log "===== DDNS 更新失败 ====="
        return 1
    fi
    log "当前公网IP: $CURRENT_IP"
    
    # 核心修改：将域名和代理状态都转换成数组，以支持一一对应
    RECORD_NAMES_ARRAY=(${RECORD_NAME//,/ })
    PROXIED_ARRAY=(${PROXIED//,/ })
    
    # 循环处理每一个域名
    for i in "${!RECORD_NAMES_ARRAY[@]}"; do
        current_domain="${RECORD_NAMES_ARRAY[$i]}"
        # 获取对应的代理状态，如果没填，默认取 false
        current_proxied="${PROXIED_ARRAY[$i]:-false}"
        
        log "----------------------------------------"
        log "⏳ 正在处理: $current_domain (小黄云设定: $current_proxied)"
        
        RECORD_INFO=$(cf_api_request "GET" "dns_records?name=$current_domain&type=$RECORD_TYPE")
        
        if ! jq -e '.success' <<< "$RECORD_INFO" >/dev/null; then
            ERROR_MSG=$(jq -r '.errors[0].message' <<< "$RECORD_INFO" 2>/dev/null || echo "未知错误")
            log "❌ [$current_domain] API错误: $ERROR_MSG"
            continue 
        fi
        
        RECORD_COUNT=$(jq -r '.result | length' <<< "$RECORD_INFO")
        
        # 如果记录不存在，直接创建
        if [ "$RECORD_COUNT" -eq 0 ] || [ "$RECORD_COUNT" = "null" ]; then
            log "⚠️ 未找到 [$current_domain] 的记录，正在创建..."
            CREATE_DATA="{\"type\":\"$RECORD_TYPE\",\"name\":\"$current_domain\",\"content\":\"$CURRENT_IP\",\"ttl\":$TTL,\"proxied\":$current_proxied}"
            CREATE_RESULT=$(cf_api_request "POST" "dns_records" "$CREATE_DATA")
            
            if jq -e '.success' <<< "$CREATE_RESULT" >/dev/null; then
                log "✅ 创建成功: $current_domain -> $CURRENT_IP (小黄云: $current_proxied)"
            else
                ERROR_MSG=$(jq -r '.errors[0].message' <<< "$CREATE_RESULT" 2>/dev/null || echo "未知错误")
                log "❌ 创建失败 [$current_domain]: $ERROR_MSG"
            fi
            continue
        fi
        
        # 记录已存在，获取当前的 IP 和 小黄云状态
        RECORD_ID=$(jq -r '.result[0].id' <<< "$RECORD_INFO")
        EXISTING_IP=$(jq -r '.result[0].content' <<< "$RECORD_INFO")
        EXISTING_PROXIED=$(jq -r '.result[0].proxied' <<< "$RECORD_INFO")
        
        # 双重校验：不仅检查 IP 是否变化，还检查小黄云状态是否和你在 config 里设定的不一致
        if [ "$CURRENT_IP" = "$EXISTING_IP" ] && [ "$current_proxied" = "$EXISTING_PROXIED" ]; then
            log "🔄 [$current_domain] IP 和 小黄云状态 均未变化，无需更新"
        else
            log "🔄 [$current_domain] 需要更新 (IP: $EXISTING_IP → $CURRENT_IP | 小黄云: $EXISTING_PROXIED → $current_proxied)"
            UPDATE_DATA="{\"type\":\"$RECORD_TYPE\",\"name\":\"$current_domain\",\"content\":\"$CURRENT_IP\",\"ttl\":$TTL,\"proxied\":$current_proxied}"
            UPDATE_RESULT=$(cf_api_request "PUT" "dns_records/$RECORD_ID" "$UPDATE_DATA")
            
            if jq -e '.success' <<< "$UPDATE_RESULT" >/dev/null; then
                log "✅ 更新成功: $current_domain -> $CURRENT_IP (小黄云: $current_proxied)"
            else
                ERROR_MSG=$(jq -r '.errors[0].message' <<< "$UPDATE_RESULT" 2>/dev/null || echo "未知错误")
                log "❌ 更新失败 [$current_domain]: $ERROR_MSG"
            fi
        fi
    done
    
    log "----------------------------------------"
    log "===== DDNS 批量更新任务完成 ====="
}

check_jq() {
    if ! command -v jq &> /dev/null; then
        echo "❌ 错误：需要jq工具但未安装"
        exit 1
    fi
}

check_jq
main "$@"
