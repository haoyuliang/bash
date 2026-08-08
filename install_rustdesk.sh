#!/bin/bash

# =================================================
# RustDesk Server 一键管理脚本 - By Haoyl
# =================================================

# 基础配置
BASE_DATA_DIR="/data/rustdesk-server"
WORK_DIR="$BASE_DATA_DIR"
COMPOSE_FILE="$WORK_DIR/docker-compose.yml"
SERVER_DATA_DIR="$BASE_DATA_DIR/server"
API_DATA_DIR="$BASE_DATA_DIR/api"
PWD_FILE="$WORK_DIR/admin_password.txt"
UNIT_NAME="rustdesk-server"
OFFICIAL_IMAGE="lejianwen/rustdesk-server-s6:latest"
LOCAL_TAR_NAME="rustdesk-s6.tar" # 预留的本地镜像包名称
DOCKER_SCRIPT_URL="https://hcloud-1251153962.file.myqcloud.com/bash/install_docker.sh"

# 调整后的指定镜像加速列表
MIRROR_NAMES=(
    "华为云加速 (推荐 - 默认)"
    "毫秒加速"
    "1Panel加速"
)

MIRROR_URLS=(
    "swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/lejianwen/rustdesk-server-s6:latest"
    "docker.1ms.run/lejianwen/rustdesk-server-s6:latest"
    "docker.1panel.live/lejianwen/rustdesk-server-s6:latest"
)

# 初始化目录
mkdir -p "$WORK_DIR" "$SERVER_DATA_DIR" "$API_DATA_DIR"

# 兼容性指令
d_compose() {
    if docker compose version &> /dev/null; then
        docker compose "$@"
    elif docker-compose version &> /dev/null; then
        docker-compose "$@"
    else
        echo -e "\033[31m错误: 未检测到 docker compose 或 docker-compose 命令，请先安装 Docker Compose！\033[0m"
        read -n 1 -s -r -p "按任意键返回..."
        return 1
    fi
}

# 获取公网 IPv4
get_public_ip() {
    local ip=$(curl -4 -s --connect-timeout 5 http://ip.sb || echo "127.0.0.1")
    echo "$ip" | tr -d '\n' | tr -d ' '
}

# 自动安装或检测 Docker 环境
check_and_install_docker() {
    # 动态识别系统包管理器并安装 curl
    if ! command -v curl &> /dev/null; then
        echo "未检测到 curl，正在尝试自动安装..."
        if command -v yum &> /dev/null; then
            yum install curl -y &>/dev/null
        elif command -v apt-get &> /dev/null; then
            apt-get update &>/dev/null && apt-get install curl -y &>/dev/null
        fi
    fi

    # 检测 Docker 状态
    if ! command -v docker &> /dev/null || ! docker info &> /dev/null; then
        echo -e "\033[33m检测到当前系统未安装 Docker 或 Docker 未启动！\033[0m"
        read -e -r -p "是否调用自定义一键脚本安装 Docker 与 Compose？(y/N): " install_docker_choice
        if [[ "$install_docker_choice" =~ ^[Yy]$ ]]; then
            echo "正在获取 Docker 安装脚本..."
            if curl -sSO "$DOCKER_SCRIPT_URL"; then
                chmod +x install_docker.sh
                ./install_docker.sh
                rm -f install_docker.sh
                
                # 再次验证是否安装成功
                if ! docker info &> /dev/null; then
                    echo -e "\033[31m错误: Docker 脚本执行完毕，但未成功检测到 Docker 运行状态！\033[0m"
                    read -n 1 -s -r -p "按任意键返回..."
                    return 1
                fi
            else
                echo -e "\033[31m错误: 无法下载 Docker 安装脚本，请检查网络连接。\033[0m"
                read -n 1 -s -r -p "按任意键返回..."
                return 1
            fi
        else
            echo "已取消安装，无法继续部署 RustDesk Server。"
            read -n 1 -s -r -p "按任意键返回..."
            return 1
        fi
    fi
    return 0
}

# 1. 核心功能：状态管理与中控面板
view_and_manage() {
    while true; do
        clear
        local current_ip=$(get_public_ip)
        local container_id=$(docker ps -a -q --filter "name=$UNIT_NAME" | head -c 12)
        local status=$(docker inspect -f '{{.State.Status}}' $UNIT_NAME 2>/dev/null || echo "未安装")
        
        echo "================================================="
        echo "            RustDesk 服务管理中控"
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
            echo -e "  管理用户名 : \033[1;33madmin\033[0m"
            [ -f "$PWD_FILE" ] && echo -e "  管理密码   : \033[1;33m$(cat "$PWD_FILE")\033[0m"
            [ -f "$PUB_KEY_FILE" ] && echo -e "  服务器公钥 : \033[32m$(cat "$PUB_KEY_FILE")\033[0m"
        fi
        
        echo "-------------------------------------------------"
        echo "  1. 重启服务 (Restart)"
        echo "  2. 启动服务 (Start)"
        echo "  3. 停止服务 (Stop)"
        echo "  4. 修改密码 (Change Password)"
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
                        docker exec -it "$UNIT_NAME" /app/apimain reset-admin-pwd "$new_pwd" >/dev/null 2>&1
                        if [ $? -eq 0 ]; then
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

# 2. 安装/更新服务
install_server() {
    clear
    echo "================================================="
    echo "               安装/更新 RustDesk Server"
    echo "================================================="
    
    # 检测并引导安装 Docker
    check_and_install_docker || return

    AUTO_IP=$(get_public_ip)
    read -e -p "请输入服务器域名 or IP [默认: $AUTO_IP]: " input_addr
    FINAL_ADDR=${input_addr:-$AUTO_IP}

    # 域名解析校验
    if [[ "$FINAL_ADDR" =~ [a-zA-Z] ]]; then
        echo -n "正在校验域名解析..."
        DNS_IP=$(getent hosts "$FINAL_ADDR" | awk '{print $1}' | head -n 1)
        
        if [ -z "$DNS_IP" ]; then
            echo -e "\n\033[31m[警告] 无法解析域名: $FINAL_ADDR\033[0m"
        elif [ "$DNS_IP" != "$AUTO_IP" ]; then
            echo -e "\n\033[33m[注意] 解析校验不匹配！\033[0m"
            echo -e "  - 域名解析地址: \033[1;31m$DNS_IP\033[0m"
            echo -e "  - 本机公网地址: \033[1;32m$AUTO_IP\033[0m"
            read -e -r -p "是否强制使用该域名继续安装? (y/N): " check_confirm
            if [[ ! "$check_confirm" =~ ^[Yy]$ ]]; then
                echo "安装已取消。"
                sleep 2
                return
            fi
        else
            echo -e " \033[32m[校验通过]\033[0m"
        fi
    fi

    # 环境变量配置
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

    # 优先检测本地镜像包
    PULL_SUCCESS=false
    if [ -f "./$LOCAL_TAR_NAME" ]; then
        echo "检测到当前目录下存在离线镜像包，正在本地导入..."
        docker load -i "./$LOCAL_TAR_NAME" && PULL_SUCCESS=true
    elif [ -f "$WORK_DIR/$LOCAL_TAR_NAME" ]; then
        echo "检测到配置目录下存在离线镜像包，正在本地导入..."
        docker load -i "$WORK_DIR/$LOCAL_TAR_NAME" && PULL_SUCCESS=true
    fi

    # 如果本地无包，进入网络拉取流程
    if [ "$PULL_SUCCESS" = false ]; then
        echo -e "\n-------------------------------------------------"
        echo "请选择要使用的 Docker 镜像拉取源:"
        echo "  1. ${MIRROR_NAMES[0]}"
        echo "  2. ${MIRROR_NAMES[1]}"
        echo "  3. ${MIRROR_NAMES[2]}"
        echo "-------------------------------------------------"
        read -e -p "请输入编号 [默认: 1]: " mirror_choice
        mirror_choice=${mirror_choice:-1}

        # 根据选择定位索引
        case "$mirror_choice" in
            1|2|3) idx=$((mirror_choice - 1)) ;;
            *)     idx=0 ;; # 任何非法输入一律默认回滚到华为云
        esac

        selected_mirror="${MIRROR_URLS[$idx]}"
        echo "正在通过选择的加速源拉取镜像: $selected_mirror ..."
        
        if docker pull "$selected_mirror"; then
            docker tag "$selected_mirror" "$OFFICIAL_IMAGE"
            docker rmi "$selected_mirror"
            PULL_SUCCESS=true
        else
            echo -e "\033[31m[错误] 所选加速源拉取失败！\033[0m"
        fi
    fi

    # 终极拦截
    if [ "$PULL_SUCCESS" = false ]; then
        echo -e "\n\033[31m镜像获取失败！网络连通异常或所选加速站均失效。\033[0m"
        echo -e "请将提前下载好的镜像包重命名为 $LOCAL_TAR_NAME 并上传到脚本同目录后再运行本地安装。"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    # 切换到工作目录确保 compose 在正确位置
    cd "$WORK_DIR" || exit

    # 写入 compose 文件
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
      - $SERVER_DATA_DIR:/data:z
      - $API_DATA_DIR:/app/data:z
    environment:
      - TZ=Asia/Shanghai
      - ENCRYPTED_ONLY=$env_encrypt
      - MUST_LOGIN=$env_login
      - TOTAL_BANDWIDTH=$env_total_bw
      - SINGLE_BANDWIDTH=$env_single_bw
      - LIMIT_SPEED=$env_limit_speed
      - RUSTDESK_API_APP_WEB_CLIENT=$env_web_client
      - RUSTDESK_API_ADMIN_HELLO=RustDesk Api
      - RELAY=$FINAL_ADDR:21117
      - RUSTDESK_API_RUSTDESK_ID_SERVER=$FINAL_ADDR:21116
      - RUSTDESK_API_RUSTDESK_RELAY_SERVER=$FINAL_ADDR:21117
      - RUSTDESK_API_RUSTDESK_API_SERVER=http://$FINAL_ADDR:21114
      - RUSTDESK_API_JWT_KEY=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 64)
      - KEY=_
EOF

    echo "启动中..."
    if d_compose up -d; then
        EXTRACTED=""
        echo -n "正在探测初始配置..."
        for i in {1..20}; do
            EXTRACTED=$(docker logs $UNIT_NAME 2>&1 | grep "Admin Password Is:" | tail -n 1 | sed 's/.*Admin Password Is: \([A-Za-z0-9]*\).*/\1/')
            if [ -n "$EXTRACTED" ]; then
                echo -e "\n\033[32m探测成功！已获取新初始密码。\033[0m"
                echo "$EXTRACTED" > "$PWD_FILE"
                break
            fi
            echo -ne "\r正在探测初始配置... [已用时 ${i}s / 20s]"
            sleep 1
        done
        echo -e "\r系统状态确认完成！                                       "
        
        chmod +x "$0"
        clear
        echo -e "\033[1;32m#################################################"
        echo "               RUSTDESK 安装部署成功！"
        echo -e "#################################################\033[0m"
        echo ""
        PUB_KEY_FILE="$SERVER_DATA_DIR/id_ed25519.pub"
        echo -e "\033[1;37m服务器地址 : \033[1;36m$FINAL_ADDR\033[0m"
        echo "================================================="
        echo -e "\033[1;37mAPI管理地址: \033[1;36mhttp://$FINAL_ADDR:21114\033[0m"
        echo "================================================="
        echo -e "\033[1;37m管理用户名 : \033[1;33madmin\033[0m"
        [ -f "$PWD_FILE" ] && echo -e "\033[1;37m管理密码   : \033[1;33m$(cat "$PWD_FILE")\033[0m"
        echo "================================================="
        [ -f "$PUB_KEY_FILE" ] && echo -e "\033[1;37m服务器公钥 : \033[32m$(cat "$PUB_KEY_FILE")\033[0m"
        echo ""
        read -n 1 -s -r -p "配置已完成。按 [任意键] 返回主菜单..."
    else
        echo -e "\033[31m容器启动失败，请检查 Docker Compose 配置或端口是否被占用。\033[0m"
        read -n 1 -s -r -p "按任意键返回..."
    fi
}

# 3. 卸载
uninstall_server() {
    read -e -r -p "确定卸载吗？此操作将停止并删除容器 (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "正在清理并卸载容器..."
        d_compose down --rmi all
        rm -f "$COMPOSE_FILE"
        
        read -e -r -p "是否保留核心数据目录 ($BASE_DATA_DIR)？(Y/n) [默认: Y]: " keep_data
        keep_data=${keep_data:-Y}
        
        if [[ "$keep_data" =~ ^[Nn]$ ]]; then
            echo "正在彻底删除数据目录..."
            rm -rf "$BASE_DATA_DIR"
            echo "服务已完全卸载，数据目录已彻底清除。"
        else
            echo "服务已卸载，核心数据目录已妥善保留。"
        fi
        
        read -n 1 -s -r -p "按任意键返回..."
    fi
}

# 主菜单
while true; do
    clear
    echo "================================================="
    echo "      RustDesk Server (S6版) 管理脚本"
    echo "================================================="
    echo "  1. 查看信息 & 状态管理"
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
