#!/bin/bash

# 基础配置
BASE_DATA_DIR="/data/rustdesk-server"
WORK_DIR="$BASE_DATA_DIR"
COMPOSE_FILE="$WORK_DIR/docker-compose.yml"
SERVER_DATA_DIR="$BASE_DATA_DIR/server"
API_DATA_DIR="$BASE_DATA_DIR/api"
PWD_FILE="$WORK_DIR/admin_password.txt"
UNIT_NAME="rustdesk-server"
OFFICIAL_IMAGE="lejianwen/rustdesk-server-s6:latest"

# 镜像加速列表
MIRROR_IMAGES=(
    "docker.1ms.run/lejianwen/rustdesk-server-s6:latest"
    "docker.awsl9527.cn/lejianwen/rustdesk-server-s6:latest"
    "docker.m.daocloud.io/lejianwen/rustdesk-server-s6:latest"
)

mkdir -p "$WORK_DIR" "$SERVER_DATA_DIR" "$API_DATA_DIR"
cd "$WORK_DIR" || exit

d_compose() {
    if docker compose version &> /dev/null; then
        docker compose "$@"
    else
        docker-compose "$@"
    fi
}

get_public_ip() {
    local ip=$(curl -s --connect-timeout 5 http://ip.sb || echo "127.0.0.1")
    echo "$ip" | tr -d '\n' | tr -d ' '
}

# 1. 核心功能：状态管理与中控面板 (集成密码重置)
view_and_manage() {
    while true; do
        clear
        local current_ip=$(get_public_ip)
        local container_id=$(docker ps -a -q --filter "name=$UNIT_NAME" | head -c 12)
        local status=$(docker inspect -f '{{.State.Status}}' $UNIT_NAME 2>/dev/null || echo "未安装")
        
        echo "================================================="
        echo "              RustDesk 服务管理中控"
        echo "================================================="
        echo -e "  容器名称 : \033[1;32m$UNIT_NAME\033[0m"
        echo -e "  容器 ID  : \033[1;32m${container_id:-N/A}\033[0m"
        echo -e "  运行状态 : [ \033[1;33m$status\033[0m ]"
        echo "-------------------------------------------------"
        echo -e "  配置目录 : \033[36m$WORK_DIR\033[0m"
        echo -e "  数据挂载 : \033[36m$SERVER_DATA_DIR -> /data\033[0m"
        echo -e "  API 挂载 : \033[36m$API_DATA_DIR -> /app/data\033[0m"
        echo "-------------------------------------------------"
        
        if [ "$status" == "running" ]; then
            PUB_KEY_FILE="$SERVER_DATA_DIR/id_ed25519.pub"
            echo -e "  服务器地址 : $current_ip"
            echo -e "  API管理地址: http://$current_ip:21114"
            [ -f "$PWD_FILE" ] && echo -e "  默认管理密码: \033[1;33m$(cat "$PWD_FILE")\033[0m"
            [ -f "$PUB_KEY_FILE" ] && echo -e "  服务器公钥 : \033[32m$(cat "$PUB_KEY_FILE")\033[0m"
        fi
        
        echo "-------------------------------------------------"
        echo "  1. 重启服务 (Restart)"
        echo "  2. 启动服务 (Start)"
        echo "  3. 停止服务 (Stop)"
        echo "  4. 修改密码 (Change Password) [新增]"
        echo "  0. 返回上一级 (或直接按回车)"
        echo "-------------------------------------------------"
        read -e -r -p "请选择操作: " op
        
        case "$op" in
            1) echo "正在重启..."; d_compose restart ;;
            2) echo "正在启动..."; d_compose up -d ;;
            3) echo "正在停止..."; d_compose stop ;;
            4) 
                if [ "$status" != "running" ]; then
                    echo -e "\033[31m错误：必须先启动服务才能修改密码。\033[0m"
                    sleep 2
                else
                    echo -e "\n================================================="
                    read -e -p "请输入新的管理密码: " new_pwd
                    if [ -n "$new_pwd" ]; then
                        echo "正在容器内执行修改..."
                        # 执行用户提供的修改密码命令
                        docker exec -it "$UNIT_NAME" /app/apimain reset-admin-pwd "$new_pwd" >/dev/null 2>&1
                        if [ $? -eq 0 ]; then
                            # 同步更新本地文件以保持显示一致
                            echo "$new_pwd" > "$PWD_FILE"
                            echo -e "\033[32m密码修改成功，本地记录已同步。\033[0m"
                        else
                            echo -e "\033[31m执行失败，请检查容器内部环境。\033[0m"
                        fi
                    else
                        echo "输入为空，取消操作。"
                    fi
                    echo "================================================="
                    sleep 2
                fi
                ;;
            0|"") break ;;
            *) echo -e "\033[31m无效输入\033[0m"; sleep 1 ;;
        esac
    done
}

# 2. 安装/更新服务 (包含固定环境变量)
install_server() {
    clear
    echo "================================================="
    echo "              安装/更新 RustDesk Server"
    echo "================================================="
    AUTO_IP=$(get_public_ip)
    read -e -p "请输入服务器域名或IP [默认: $AUTO_IP]: " server_addr
    server_addr=${server_addr:-$AUTO_IP}

    read -e -p "1. 强制加密连接 (1:加密 0:不加密) [默认: 1]: " env_encrypt
    env_encrypt=${env_encrypt:-1}
    read -e -p "2. 强制登录发起连接 (Y/N) [默认: Y]: " env_login
    env_login=${env_login:-Y}
    read -e -p "3. 总带宽限制 (Mbps) [默认: 1000]: " env_total_bw
    env_total_bw=${env_total_bw:-1000}
    read -e -p "4. 单个连接限速 (Mbps) [默认: 100]: " env_single_bw
    env_single_bw=${env_single_bw:-100}
    read -e -p "5. 传输文件限速 (Mbps) [默认: 1000]: " env_limit_speed
    env_limit_speed=${env_limit_speed:-1000}
    read -e -p "6. 启用 WebClient (1:启用 0:不启用) [默认: 1]: " env_web_client
    env_web_client=${env_web_client:-1}

    echo "正在拉取镜像..."
    PULL_SUCCESS=false
    for mirror in "${MIRROR_IMAGES[@]}"; do
        if docker pull "$mirror"; then
            docker tag "$mirror" "$OFFICIAL_IMAGE"
            docker rmi "$mirror"
            PULL_SUCCESS=true
            break
        fi
    done

    [ "$PULL_SUCCESS" = false ] && { echo "拉取失败"; read -n 1 -s -r -p "按任意键返回..."; return; }

    cat <<EOF > "$COMPOSE_FILE"
services:
  $UNIT_NAME:
    image: $OFFICIAL_IMAGE
    container_name: $UNIT_NAME
    restart: unless-stopped
    ports:
      - "21114:21114/tcp"
      - "21115:21115/tcp"
      - "21116:21116/tcp"
      - "21116:21116/udp"
      - "21117:21117/tcp"
      - "21118:21118/tcp"
      - "21119:21119/tcp"
    volumes:
      - $SERVER_DATA_DIR:/data
      - $API_DATA_DIR:/app/data
    environment:
      - TZ=Asia/Shanghai
      - ENCRYPTED_ONLY=$env_encrypt
      - MUST_LOGIN=$env_login
      - TOTAL_BANDWIDTH=$env_total_bw
      - SINGLE_BANDWIDTH=$env_single_bw
      - LIMIT_SPEED=$env_limit_speed
      - RUSTDESK_API_APP_WEB_CLIENT=$env_web_client
      - RUSTDESK_API_ADMIN_HELLO=RustDesk Api
      - RELAY=$server_addr:21117
      - RUSTDESK_API_RUSTDESK_ID_SERVER=$server_addr:21116
      - RUSTDESK_API_RUSTDESK_RELAY_SERVER=$server_addr:21117
      - RUSTDESK_API_RUSTDESK_API_SERVER=http://$server_addr:21114
      - RUSTDESK_API_JWT_KEY=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 64)
EOF

    echo "启动中..."
    if d_compose up -d; then
        echo -n "正在初始化系统，请稍候..."
        for i in {30..1}; do
            echo -ne "\r正在初始化系统，请稍候... [剩余 $i 秒] "
            sleep 1
        done
        echo -e "\r系统初始化完成！                         "
        
        EXTRACTED=$(docker logs $UNIT_NAME 2>&1 | grep "Admin Password Is:" | tail -n 1 | sed 's/.*Admin Password Is: \([A-Za-z0-9]*\).*/\1/')
        [ -n "$EXTRACTED" ] && echo "$EXTRACTED" > "$PWD_FILE"
        
        clear
        echo -e "\033[1;32m#################################################"
        echo "             RUSTDESK 安装部署成功！"
        echo -e "#################################################\033[0m"
        echo ""
        local current_ip=$(get_public_ip)
        PUB_KEY_FILE="$SERVER_DATA_DIR/id_ed25519.pub"
        
        echo -e "\033[1;37m服务器地址 : \033[1;36m$current_ip\033[0m"
        echo "================================================="
        echo -e "\033[1;37mAPI管理地址: \033[1;36mhttp://$current_ip:21114\033[0m"
        echo "================================================="
        echo -e "\033[1;37m管理用户名 : \033[1;33madmin\033[0m"
        [ -f "$PWD_FILE" ] && echo -e "\033[1;37m默认密码   : \033[1;33m$(cat "$PWD_FILE")\033[0m"
        echo "================================================="
        [ -f "$PUB_KEY_FILE" ] && echo -e "\033[1;37m服务器公钥 : \033[32m$(cat "$PUB_KEY_FILE")\033[0m"
        echo ""
        echo -e "\033[1;32m#################################################\033[0m"
        echo ""
        read -n 1 -s -r -p "配置已完成。按 [任意键] 返回主菜单..."
    fi
}

# 3. 卸载
uninstall_server() {
    read -e -r -p "确定卸载吗？核心数据将保留 (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        d_compose down --rmi all
        rm -f "$COMPOSE_FILE" "$PWD_FILE"
        echo "卸载完成。"
        read -n 1 -s -r -p "按任意键返回..."
    fi
}

# 主菜单
while true; do
    clear
    echo "================================================="
    echo "      RustDesk Server (S6版) 管理脚本"
    echo "================================================="
    echo "  1. 查看信息 & 状态管理 (重启/启动/停止/密码重置)"
    echo "  2. 安装/更新 RustDesk Server"
    echo "  3. 卸载 RustDesk Server"
    echo "  0. 退出脚本"
    echo "================================================="
    read -e -r -p "请输入选项: " choice
    case "$choice" in
        1) view_and_manage ;;
        2) install_server ;;
        3) uninstall_server ;;
        0) exit 0 ;;
        *) echo -e "\033[31m输入错误\033[0m"; sleep 1 ;;
    esac
done
