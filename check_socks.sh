#!/bin/bash
set -eo pipefail

# 配置日志函数
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$LOG_LEVEL" in
        debug)
            echo "[$timestamp] [$level] $message"
            ;;
        info)
            if [ "$level" != "DEBUG" ]; then
                echo "[$timestamp] [$level] $message"
            fi
            ;;
        warning)
            if [ "$level" = "WARNING" ] || [ "$level" = "ERROR" ]; then
                echo "[$timestamp] [$level] $message"
            fi
            ;;
        error)
            if [ "$level" = "ERROR" ]; then
                echo "[$timestamp] [$level] $message"
            fi
            ;;
    esac
}

# 检查必要环境变量
check_env_vars() {
    local missing=0
    if [ -z "$SOCKS5_HOST" ]; then
        log "ERROR" "缺少环境变量: SOCKS5_HOST"
        missing=1
    fi
    
    if [ -z "$SOCKS5_PORT" ]; then
        log "ERROR" "缺少环境变量: SOCKS5_PORT"
        missing=1
    fi
    
    if [ -z "$SOCKS5_CONTAINER_NAME" ]; then
        log "ERROR" "缺少环境变量: SOCKS5_CONTAINER_NAME"
        missing=1
    fi
    
    if [ -z "$CHECK_URL" ]; then
        log "ERROR" "缺少环境变量: CHECK_URL"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        exit 1
    fi
}

# 检查Docker连接
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        log "ERROR" "无法连接到Docker，请确保挂载了Docker socket并且有足够的权限"
        return 1
    fi
    return 0
}

# 检查容器是否存在
check_container_exists() {
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${SOCKS5_CONTAINER_NAME}$"; then
        log "ERROR" "容器 ${SOCKS5_CONTAINER_NAME} 不存在"
        return 1
    fi
    return 0
}

# 主函数
main() {
    log "INFO" "开始启动socks5连接检查器 v1.2.0"
    log "INFO" "每 $CHECK_INTERVAL 秒通过 $SOCKS5_HOST:$SOCKS5_PORT 检查URL: $CHECK_URL"
    log "INFO" "如果连接失败将重启容器 $SOCKS5_CONTAINER_NAME"
    
    # 检查环境变量
    check_env_vars
    
    # 检查Docker连接和容器存在性
    if ! check_docker || ! check_container_exists; then
        log "ERROR" "初始化检查失败，10秒后重试..."
        sleep 10
        if ! check_docker || ! check_container_exists; then
            log "ERROR" "初始化检查仍然失败，退出程序"
            exit 1
        fi
    fi
    
    # 连续失败计数器
    local fail_count=0
    
    while true; do
        log "DEBUG" "开始检查连接..."
        
        # 捕获 curl 返回值，避免 set -e 导致脚本退出
        if RESULT=$(curl -s --max-time "$CURL_TIMEOUT" --socks5-hostname "$SOCKS5_HOST:$SOCKS5_PORT" "$CHECK_URL"); then
            # 从结果中提取IP
            IP=$(echo "$RESULT" | grep -oE "ip=([0-9a-f.:]+)" | cut -d= -f2)
            
            if [ -n "$IP" ]; then
                log "INFO" "当前网络正常，IP地址为：$IP"
                # 重置失败计数
                fail_count=0
            else
                log "WARNING" "已连接到socks5代理但无法提取IP地址"
                ((fail_count++))
                if [ $fail_count -ge 3 ]; then
                    log "WARNING" "连续3次无法提取IP地址，尝试重启容器..."
                    if docker restart "$SOCKS5_CONTAINER_NAME"; then
                        log "INFO" "容器 $SOCKS5_CONTAINER_NAME 重启命令已发送"
                        log "INFO" "等待 $RESTART_WAIT 秒让容器重启..."
                        sleep "$RESTART_WAIT"
                        fail_count=0
                    else
                        log "ERROR" "重启容器 $SOCKS5_CONTAINER_NAME 失败"
                    fi
                fi
            fi
        else
            log "WARNING" "连接到socks5代理失败"
            ((fail_count++))
            if [ $fail_count -ge 2 ]; then
                log "WARNING" "连续2次连接失败，正在重启 $SOCKS5_CONTAINER_NAME 容器..."
                if docker restart "$SOCKS5_CONTAINER_NAME"; then
                    log "INFO" "容器 $SOCKS5_CONTAINER_NAME 重启命令已发送"
                    log "INFO" "等待 $RESTART_WAIT 秒让容器重启..."
                    sleep "$RESTART_WAIT"
                    fail_count=0
                else
                    log "ERROR" "重启容器 $SOCKS5_CONTAINER_NAME 失败"
                fi
            fi
        fi
        
        log "DEBUG" "等待 $CHECK_INTERVAL 秒后再次检查..."
        sleep "$CHECK_INTERVAL"
    done
}

# 捕获信号
trap 'log "INFO" "收到终止信号，正在退出..."; exit 0' SIGTERM SIGINT

# 启动主函数
main
