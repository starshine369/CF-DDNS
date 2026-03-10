#!/bin/bash

# Cloudflare DDNS 更新脚本 (多域名 + 独立小黄云控制版)
# 增加了自动识别并安装依赖 (jq, curl) 的功能

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
    echo "║            Cloudflare DDNS 配置向导              ║"
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
