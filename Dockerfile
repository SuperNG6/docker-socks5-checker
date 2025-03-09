FROM alpine:latest

RUN apk add --no-cache curl bash grep docker-cli tzdata ca-certificates && \
    mkdir -p /app

# 设置默认时区为Asia/Shanghai
ENV TZ=Asia/Shanghai

# 复制检查脚本
COPY check_socks.sh /app/
RUN chmod +x /app/check_socks.sh

# 设置工作目录
WORKDIR /app

# 设置环境变量及默认值
ENV CHECK_INTERVAL=300 \
    SOCKS5_HOST=socks5-container \
    SOCKS5_PORT=1080 \
    SOCKS5_CONTAINER_NAME=socks5-container \
    CHECK_URL=https://www.cloudflare.com/cdn-cgi/trace \
    CURL_TIMEOUT=10 \
    RESTART_WAIT=15 \
    LOG_LEVEL=info

# 添加健康检查
HEALTHCHECK --interval=60s --timeout=5s --start-period=5s --retries=3 CMD [ "sh", "-c", "ps aux | grep check_socks.sh | grep -v grep" ]


# 添加标签
LABEL maintainer="SuperNG6" \
      description="通过socks5代理定时检查网络连接状态并在失败时重启代理容器" \
      version="1.3.0"

# 运行脚本
CMD ["/app/check_socks.sh"]