#!/bin/bash

# 确保脚本以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "错误: 请以 root 权限运行此脚本。"
    exit 1
fi

echo "正在检测系统环境..."

# 检测系统版本
if [ -f /etc/os-release ]; then
    . /etc/os-release
    SYS_VERSION=${VERSION_ID%%.*} # 只取大版本号，例如 7 或 8
    SYS_NAME=$ID
else
    echo "错误: 无法识别系统版本，请手动检查。"
    exit 1
fi

# ----------------------------------------------------
# 自动化网络检查与 DNS 修复 (Google DNS + Cloudflare DNS)
# ----------------------------------------------------
check_network() {
    if ! ping -c 1 1.1.1.1 &>/dev/null; then
        echo "警告: 无法连接外网，正在尝试自动修复 DNS 配置..."
        echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1\nnameserver 8.8.4.4\nnameserver 1.0.0.1" > /etc/resolv.conf
        if ! ping -c 1 1.1.1.1 &>/dev/null; then
            echo "错误: 修复 DNS 后仍无法连接外网，请检查服务器网络设置。"
            exit 1
        fi
    fi
}

# ----------------------------------------------------
# CentOS 专属换源与依赖修复逻辑 (智能双重检查)
# ----------------------------------------------------
if [ "$SYS_NAME" = "centos" ]; then
    check_network

    # ----------- CentOS 7 修复逻辑 -----------
    if [ "$SYS_VERSION" = "7" ]; then
        # 检查是否包含官方失效域名，或者 YUM 本身已瘫痪
        if grep -q "mirrorlist.centos.org" /etc/yum.repos.d/*.repo 2>/dev/null || ! yum makecache &>/dev/null; then
            echo "检测到 CentOS 7 官方源配置或 YUM 缓存异常，正在切换为阿里云 Vault 归档源..."
            mkdir -p /etc/yum.repos.d/bak
            mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/ 2>/dev/null

            curl -sSL -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
            sed -i -e 's/mirror.centos.org/mirrors.aliyun.com/g' \
                   -e 's/$releasever/7.9.2009/g' \
                   -e 's/http:/https:/g' /etc/yum.repos.d/CentOS-Base.repo
            yum clean all && yum makecache
        else
            echo "检测到当前 CentOS 7 已配置第三方有效源，跳过换源步骤。"
        fi

        # 确保补齐基础组件
        if ! command -v yum-config-manager &>/dev/null; then
            echo "正在安装 CentOS 7 基础组件 (yum-utils)..."
            yum install -y yum-utils device-mapper-persistent-data lvm2
        fi

    # ----------- CentOS 8 修复逻辑 -----------
    elif [ "$SYS_VERSION" = "8" ]; then
        # 检查是否包含官方失效域名，或者 DNF 本身已瘫痪
        if grep -q "mirrorlist.centos.org" /etc/yum.repos.d/*.repo 2>/dev/null || ! dnf makecache &>/dev/null; then
            echo "检测到 CentOS 8 官方源配置或 DNF 缓存异常，正在切换为阿里云 Vault 归档源..."
            mkdir -p /etc/yum.repos.d/bak
            mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/ 2>/dev/null

            curl -sSL -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-8.repo
            
            # 将域名全部替换为 vault.centos.org 的阿里镜像并修正具体路径
            sed -i -e 's/mirror.centos.org/mirrors.aliyun.com/g' \
                   -e 's/$mirrorlist/mirrorlist/g' \
                   -e 's/http:/https:/g' /etc/yum.repos.d/CentOS-Base.repo
            sed -i 's/\/centos\/\$releasever/\/centos-vault\/8.5.2111/g' /etc/yum.repos.d/CentOS-Base.repo
            
            dnf clean all && dnf makecache
        else
            echo "检测到当前 CentOS 8 已配置第三方有效源，跳过换源步骤。"
        fi

        # 确保补齐基础组件
        if ! command -v dnf config-manager &>/dev/null && ! command -v yum-config-manager &>/dev/null; then
            echo "正在安装 CentOS 8 基础组件 (dnf-plugins-core)..."
            dnf install -y dnf-plugins-core
        fi
    fi
fi

# ----------------------------------------------------
# 核心 Docker 安装逻辑 (使用 Docker 官方源)
# ----------------------------------------------------
echo "正在为 $PRETTY_NAME 安装 Docker (使用 Docker 官方源)..."

if [ "$SYS_NAME" = "centos" ]; then
    # 卸载可能冲突的旧版本
    yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
    
    # 根据系统命令调用对应的配置工具
    if command -v dnf &>/dev/null; then
        dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        # --allowerasing 用于解决 CentOS 8 中 Podman 与 Docker 的依赖冲突
        dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin --allowerasing
    else
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
elif [ "$SYS_NAME" = "ubuntu" ] || [ "$SYS_NAME" = "debian" ]; then
    check_network
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    # 添加 Docker 官方 GPG 密钥与源
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$SYS_NAME/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$SYS_NAME $VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# ----------------------------------------------------
# 启动并自启 Docker 服务
# ----------------------------------------------------
systemctl daemon-reload
systemctl enable docker
systemctl restart docker

# 验证安装结果
if command -v docker &>/dev/null; then
    echo "-------------------------------------------"
    docker --version
    if docker compose version &>/dev/null; then
        docker compose version
    elif docker-compose --version &>/dev/null; then
        docker-compose --version
    fi
    echo "镜像下载源: Docker Official (官方网络)"
    echo "Docker 安装成功！"
    echo "-------------------------------------------"
else
    echo "错误: Docker 安装失败，请检查上方日志。"
fi
