#!/bin/bash

# Cloudflare DDNS 更新脚本 (混合双栈多域名 + 自动依赖 + 全自动定时任务版)

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
    
    if command -v crontab &> /dev/null; then
        local tmp_cron=$(mktemp)
        crontab -l 2>/dev/null | grep -v "cloudflare_ddns" > "$tmp_cron"
        crontab "$tmp_cron"
        rm -f "$tmp_cron"
        deleted_files+=("定时任务: 已从 crontab 中移除相关计划")
    fi

    if [ -f "$CONFIG_FILE" ]; then
        rm -f "$CONFIG_FILE"
        deleted_files+=("配置文件: $CONFIG_FILE")
    fi
    if [ -f "$LOG_FILE" ]; then
        rm -f "$LOG_FILE"
        deleted_files+=("日志文件: $LOG_FILE")
    fi
    find "$CFG_DIR" -name "cloudflare_ddns.log.*" -delete 2>/dev/null
    
    if [ -d "$config_dir" ]; then
        rmdir "$config_dir" 2>/dev/null && deleted_files+=("配置目录: $config_dir")
    fi
    
    if [ ${#deleted_files[@]} -gt 0 ]; then
        echo "✅ 已删除以下文件及配置:"
        for file in "${deleted_files[@]}"; do
            echo "  - $file"
        done
    else
        echo "⚠️ 未找到配置文件或日志文件"
    fi
}

setup_cron() {
    echo "──────────────────────────────────────────────────"
    read -p "❓ 是否自动配置定时任务 (每5分钟在后台自动执行一次)? [Y/n]: " setup_cron_task
    setup_cron_task=${setup_cron_task:-Y}
    
    if [[ "$setup_cron_task" =~ ^[Yy]$ ]]; then
        if ! command -v crontab &> /dev/null; then
            echo "⏳ 检测到未安装 cron(定时任务) 服务，正在自动安装..."
            local SUDO=""
            [ "$EUID" -ne 0 ] && command -v sudo &> /dev/null && SUDO="sudo"
            
            if command -v apt-get &> /dev/null; then
                $SUDO apt-get update -yq >/dev/null 2>&1
                $SUDO apt-get install -yq cron >/dev/null 2>&1
                $SUDO systemctl enable --now cron >/dev/null 2>&1
            elif command -v yum &> /dev/null; then
                $SUDO yum install -yq cronie >/dev/null 2>&1
                $SUDO systemctl enable --now crond >/dev/null 2>&1
            elif command -v dnf &> /dev/null; then
                $SUDO dnf install -yq cronie >/dev/null 2>&1
                $SUDO systemctl enable --now crond >/dev/null 2>&1
            elif command -v apk &> /dev/null; then
                $SUDO apk add --no-cache dcron >/dev/null 2>&1
                $SUDO rc-update add crond >/dev/null 2>&1
                $SUDO rc-service crond start >/dev/null 2>&1
            elif command -v pacman &> /dev/null; then
                $SUDO pacman -Sy --noconfirm cronie >/dev/null 2>&1
                $SUDO systemctl enable --now cronie >/dev/null 2>&1
            fi
            
            if ! command -v crontab &> /dev/null; then
                echo "❌ 自动安装 cron 失败，请手动安装后重试配置。"
                return
            fi
        fi

        local SCRIPT_TARGET="/usr/local/bin/cloudflare_ddns.sh"
        local CURRENT_SCRIPT=$(realpath "$0")
        local SUDO=""
        [ "$EUID" -ne 0 ] && command -v sudo &> /dev/null && SUDO="sudo"

        if [ "$CURRENT_SCRIPT" != "$SCRIPT_TARGET" ]; then
            $SUDO cp "$CURRENT_SCRIPT" "$SCRIPT_TARGET"
            $SUDO chmod +x "$SCRIPT_TARGET"
            echo "✅ 脚本已自动部署到: $SCRIPT_TARGET"
        fi

        local tmp_cron=$(mktemp)
        crontab -l 2>/dev/null | grep -v "cloudflare_ddns" > "$tmp_cron"
        
        echo "*/5 * * * * $SCRIPT_TARGET >> $LOG_FILE 2>&1" >> "$tmp_cron"
        echo "✅ 定时更新任务已添加 (频率: 每 5 分钟)"
        
        read -p "❓ 是否配置日志自动清理 (每天凌晨切割日志并清理7天前的记录)? [Y/n]: " setup_log_clean
        setup_log_clean=${setup_log_clean:-Y}
        if [[ "$setup_log_clean" =~ ^[Yy]$ ]]; then
            local log_dir=$(dirname "$LOG_FILE")
            local log_base=$(basename "$LOG_FILE")
            local clean_cmd="0 0 * * * cp $LOG_FILE $LOG_FILE.\$(date +\\%Y\\%m\\%d) && > $LOG_FILE && find $log_dir -name \"$log_base.*\" -mtime +7 -delete"
            echo "$clean_cmd" >> "$tmp_cron"
            echo "✅ 日志清理任务已添加 (保留7天)"
        fi

        crontab "$tmp_cron"
        rm -f "$tmp_cron"
        echo "──────────────────────────────────────────────────"
        echo "🎉 所有定时调度配置完毕！"
    fi
}

init_config() {
    create_config_dir

    usage() {
        echo
        echo "Cloudflare DDNS 更新脚本 (混合双栈版)"
        echo "option:"
        echo "  -h, --help            显示帮助信息"
        echo "  -reconfig             重置配置并重新运行向导"
        echo "  -delete               彻底删除配置、日志及定时任务"
    }
    
    case "$1" in
        -h|--help)
            usage; exit 0 ;;
        -delete)
            delete_config; exit 0 ;;
        -reconfig)
            if [ -f "$CONFIG_FILE" ]; then
                rm -f "$CONFIG_FILE"
                echo "✅ 配置已重置，请重新运行脚本进行配置"
                exit 0
            else
                echo "配置文件不存在，无需重置"; exit 0
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
    echo "║       Cloudflare DDNS 终极部署向导 (双栈版)      ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo "提示：此版本支持为每个子域名单独指定解析 IPv4(A) 或 IPv6(AAAA)"
    echo "──────────────────────────────────────────────────"
    
    read -p "1. 请输入Cloudflare API Token: " API_TOKEN
    [ -z "$API_TOKEN" ] && { echo "错误：API Token不能为空！"; exit 1; }
    
    read -p "2. 全局TTL值 [1-86400] (默认: 60): " TTL
    TTL=${TTL:-60}

    echo "──────────────────────────────────────────────────"
    echo "接下来开始配置主域名 (Zone)。你可以添加多个不同的主域名。"
    
    declare -a ZONE_IDS=()
    declare -a ZONE_REMARKS=()
    declare -a RECORD_NAMES=()
    declare -a RECORD_TYPES_SETTINGS=()
    declare -a PROXIED_SETTINGS=()

    local zone_count=1
    while true; do
        echo
        echo "▶ 正在配置第 $zone_count 个主域名："
        
        read -p "  输入 Zone ID: " current_zone_id
        [ -z "$current_zone_id" ] && { echo "  ❌ Zone ID 不能为空，请重新输入。"; continue; }
        
        read -p "  输入该域名的备注 (如 starshine369.top): " current_remark
        current_remark=${current_remark:-"未命名域名_$zone_count"}
        
        read -p "  输入子域名 (多个用逗号分隔，如 v4.a.com,v6.a.com): " current_records
        [ -z "$current_records" ] && { echo "  ❌ 子域名不能为空，请重新配置当前 Zone。"; continue; }
        
        read -p "  对应的记录类型 (如 A,AAAA) (默认全为 A): " current_types
        current_types=${current_types:-A}

        read -p "  对应的代理状态 (如 false,true) (默认全为 false): " current_proxieds
        current_proxieds=${current_proxieds:-false}

        ZONE_IDS+=("$current_zone_id")
        ZONE_REMARKS+=("$current_remark")
        RECORD_NAMES+=("$current_records")
        RECORD_TYPES_SETTINGS+=("$current_types")
        PROXIED_SETTINGS+=("$current_proxieds")

        echo "  ✅ 第 $zone_count 个主域名 [$current_remark] 配置已记录。"
        
        echo "──────────────────────────────────────────────────"
        read -p "❓ 是否需要继续添加另一个主域名(Zone ID)? [y/N]: " add_more
        case "$add_more" in
            [yY][eE][sS]|[yY]) ((zone_count++)) ;;
            *) break ;;
        esac
    done
    
    echo "──────────────────────────────────────────────────"
    read -p "3. 日志文件路径 (默认: ${CFG_DIR}/cloudflare_ddns.log): " input_log
    LOG_FILE=${input_log:-"${CFG_DIR}/cloudflare_ddns.log"}
    
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "===== DDNS 多域名双栈配置创建于 $(date) =====" > "$LOG_FILE"
    
    echo "#!/bin/bash" > "$CONFIG_FILE"
    echo "# Cloudflare DDNS 配置文件 (双栈多域名版)" >> "$CONFIG_FILE"
    echo "API_TOKEN='$API_TOKEN'" >> "$CONFIG_FILE"
    echo "TTL='$TTL'" >> "$CONFIG_FILE"
    echo "LOG_FILE='$LOG_FILE'" >> "$CONFIG_FILE"
    echo "" >> "$CONFIG_FILE"
    echo "$(declare -p ZONE_IDS)" >> "$CONFIG_FILE"
    echo "$(declare -p ZONE_REMARKS)" >> "$CONFIG_FILE"
    echo "$(declare -p RECORD_NAMES)" >> "$CONFIG_FILE"
    echo "$(declare -p RECORD_TYPES_SETTINGS)" >> "$CONFIG_FILE"
    echo "$(declare -p PROXIED_SETTINGS)" >> "$CONFIG_FILE"
    
    chmod 600 "$CONFIG_FILE"
    echo "✅ 所有配置参数已保存到: $CONFIG_FILE"
    
    setup_cron
}

get_ip() {
    local ip_version=$1
    local ip_services
    local max_retry=3
    
    if [ "$ip_version" = "4" ]; then
        ip_services=("https://ipv4.icanhazip.com" "https://api.ipify.org" "https://checkip.amazonaws.com")
    else
        ip_services=("https://ipv6.icanhazip.com" "https://api64.ipify.org" "https://v6.ident.me")
    fi
    
    for service in "${ip_services[@]}"; do
        for ((i=1; i<=max_retry; i++)); do
            ip=$(curl -$ip_version -s --fail --max-time 10 "$service" 2>/dev/null)
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
    local url="https://api.cloudflare.com/client/v4/zones/$CURRENT_ZONE_ID/$endpoint"
    
    local curl_cmd="curl -s -X $method '$url' \
        -H 'Authorization: Bearer $API_TOKEN' \
        -H 'Content-Type: application/json'"
    
    [ -n "$data" ] && curl_cmd+=" --data '$data'"
    eval "$curl_cmd"
}

main() {
    init_config "$@"
    
    log "===== DDNS 混合双栈批量更新任务开始 ====="
    
    # 统一获取本机的 IPv4 和 IPv6 地址
    log "正在检测本机网络环境..." 1
    CURRENT_IPV4=$(get_ip 4)
    CURRENT_IPV6=$(get_ip 6)
    
    [ -n "$CURRENT_IPV4" ] && log "本机 IPv4: $CURRENT_IPV4" || log "本机 IPv4: 未获取到"
    [ -n "$CURRENT_IPV6" ] && log "本机 IPv6: $CURRENT_IPV6" || log "本机 IPv6: 未获取到"
    
    if [ -z "$CURRENT_IPV4" ] && [ -z "$CURRENT_IPV6" ]; then
        log "❌ 错误：无法获取任何公网IP地址，请检查网络连接！"
        log "===== DDNS 更新失败 ====="
        return 1
    fi
    
    for idx in "${!ZONE_IDS[@]}"; do
        CURRENT_ZONE_ID="${ZONE_IDS[$idx]}"
        REMARK="${ZONE_REMARKS[$idx]}"
        RECORDS_STR="${RECORD_NAMES[$idx]}"
        TYPES_STR="${RECORD_TYPES_SETTINGS[$idx]}"
        PROXIED_STR="${PROXIED_SETTINGS[$idx]}"
        
        log "========================================"
        log "🌐 开始处理主域名: $REMARK"
        
        RECORD_NAMES_ARRAY=(${RECORDS_STR//,/ })
        RECORD_TYPES_ARRAY=(${TYPES_STR//,/ })
        PROXIED_ARRAY=(${PROXIED_STR//,/ })
        
        for j in "${!RECORD_NAMES_ARRAY[@]}"; do
            current_domain="${RECORD_NAMES_ARRAY[$j]}"
            
            # 解析记录类型，默认为 A，并自动转为大写
            current_type="${RECORD_TYPES_ARRAY[$j]:-A}"
            current_type=$(echo "$current_type" | tr 'a-z' 'A-Z')
            
            # 代理状态，默认为 false
            current_proxied="${PROXIED_ARRAY[$j]:-false}"
            
            # 根据记录类型选择目标 IP
            local target_ip=""
            if [ "$current_type" = "AAAA" ]; then
                target_ip="$CURRENT_IPV6"
                if [ -z "$target_ip" ]; then
                    log "⚠️ [$current_domain] 需要 AAAA 记录，但未获取到本机的 IPv6 地址，已跳过。"
                    continue
                fi
            else
                current_type="A" # 防呆纠错，非 AAAA 一律视为 A
                target_ip="$CURRENT_IPV4"
                if [ -z "$target_ip" ]; then
                    log "⚠️ [$current_domain] 需要 A 记录，但未获取到本机的 IPv4 地址，已跳过。"
                    continue
                fi
            fi
            
            log "-----------------"
            log "⏳ 正在检查: $current_domain (类型: $current_type | 小黄云: $current_proxied)"
            
            RECORD_INFO=$(cf_api_request "GET" "dns_records?name=$current_domain&type=$current_type")
            
            if ! jq -e '.success' <<< "$RECORD_INFO" >/dev/null; then
                ERROR_MSG=$(jq -r '.errors[0].message' <<< "$RECORD_INFO" 2>/dev/null || echo "未知错误")
                log "❌ [$current_domain] API错误: $ERROR_MSG"
                continue 
            fi
            
            RECORD_COUNT=$(jq -r '.result | length' <<< "$RECORD_INFO")
            
            if [ "$RECORD_COUNT" -eq 0 ] || [ "$RECORD_COUNT" = "null" ]; then
                log "⚠️ 未找到 $current_type 记录，正在创建..."
                CREATE_DATA="{\"type\":\"$current_type\",\"name\":\"$current_domain\",\"content\":\"$target_ip\",\"ttl\":$TTL,\"proxied\":$current_proxied}"
                CREATE_RESULT=$(cf_api_request "POST" "dns_records" "$CREATE_DATA")
                
                if jq -e '.success' <<< "$CREATE_RESULT" >/dev/null; then
                    log "✅ 创建成功 -> $target_ip"
                else
                    ERROR_MSG=$(jq -r '.errors[0].message' <<< "$CREATE_RESULT" 2>/dev/null || echo "未知错误")
                    log "❌ 创建失败: $ERROR_MSG"
                fi
                continue
            fi
            
            RECORD_ID=$(jq -r '.result[0].id' <<< "$RECORD_INFO")
            EXISTING_IP=$(jq -r '.result[0].content' <<< "$RECORD_INFO")
            EXISTING_PROXIED=$(jq -r '.result[0].proxied' <<< "$RECORD_INFO")
            
            if [ "$target_ip" = "$EXISTING_IP" ] && [ "$current_proxied" = "$EXISTING_PROXIED" ]; then
                log "🔄 无需更新 (IP与代理状态均一致)"
            else
                log "🔄 正在更新 (IP: $EXISTING_IP → $target_ip | 小黄云: $EXISTING_PROXIED → $current_proxied)"
                UPDATE_DATA="{\"type\":\"$current_type\",\"name\":\"$current_domain\",\"content\":\"$target_ip\",\"ttl\":$TTL,\"proxied\":$current_proxied}"
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

check_dependencies() {
    local deps=("curl" "jq")
    local missing_deps=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "⚠️ 检测到缺少核心依赖: ${missing_deps[*]}"
        echo "⏳ 正在尝试自动安装..."

        local SUDO=""
        [ "$EUID" -ne 0 ] && command -v sudo &> /dev/null && SUDO="sudo"

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
            echo "❌ 错误：未知的包管理器，请手动安装依赖: ${missing_deps[*]}"
            exit 1
        fi

        for dep in "${missing_deps[@]}"; do
            if ! command -v "$dep" &> /dev/null; then
                echo "❌ 自动安装 $dep 失败，请检查网络或手动安装。"
                exit 1
            fi
        done
        echo "✅ 依赖 ${missing_deps[*]} 自动安装成功！"
        echo "──────────────────────────────────────────────────"
    fi
}

check_dependencies
main "$@"
