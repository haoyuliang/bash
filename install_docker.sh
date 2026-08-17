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
    SYS_VERSION=${VERSION_ID%%.*}
    SYS_NAME=$ID
    SYS_LIKE=${ID_LIKE:-""}
else
    echo "错误: 无法识别系统版本，请手动检查。"
    exit 1
fi

# ----------------------------------------------------
# 自动化网络检查与 DNS 修复
# ----------------------------------------------------
check_network() {
    if ! ping -c 1 baidu.com &>/dev/null; then
        echo "警告: 无法连接外网，正在尝试自动修复 DNS 配置..."
        echo -e "nameserver 223.5.5.5\nnameserver 119.29.29.29" > /etc/resolv.conf
        if ! ping -c 1 baidu.com &>/dev/null; then
            echo "错误: 修复 DNS 后仍无法连接外网，请检查服务器网络设置。"
            exit 1
        fi
    fi
}

# ----------------------------------------------------
# CentOS 7/8 专属旧源修复逻辑
# ----------------------------------------------------
if [ "$SYS_NAME" = "centos" ]; then
    check_network

    # CentOS 7 修复
    if [ "$SYS_VERSION" = "7" ]; then
        if grep -q "mirrorlist.centos.org" /etc/yum.repos.d/*.repo 2>/dev/null || ! yum makecache &>/dev/null; then
            echo "检测到 CentOS 7 官方源配置异常，正在切换为阿里云 Vault 归档源..."
            mkdir -p /etc/yum.repos.d/bak
            mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/ 2>/dev/null

            curl -sSL -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
            sed -i -e 's/mirror.centos.org/mirrors.aliyun.com/g' \
                   -e 's/$releasever/7.9.2009/g' \
                   -e 's/http:/https:/g' /etc/yum.repos.d/CentOS-Base.repo
            yum clean all && yum makecache
        fi
        if ! command -v yum-config-manager &>/dev/null; then
            yum install -y yum-utils device-mapper-persistent-data lvm2
        fi

    # CentOS 8 修复
    elif [ "$SYS_VERSION" = "8" ]; then
        if grep -q "mirrorlist.centos.org" /etc/yum.repos.d/*.repo 2>/dev/null || ! dnf makecache &>/dev/null; then
            echo "检测到 CentOS 8 官方源配置异常，正在切换为阿里云 Vault 归档源..."
            mkdir -p /etc/yum.repos.d/bak
            mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/ 2>/dev/null

            curl -sSL -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-8.repo
            sed -i -e 's/mirror.centos.org/mirrors.aliyun.com/g' \
                   -e 's/$mirrorlist/mirrorlist/g' \
                   -e 's/http:/https:/g' /etc/yum.repos.d/CentOS-Base.repo
            sed -i 's/\/centos\/\$releasever/\/centos-vault\/8.5.2111/g' /etc/yum.repos.d/CentOS-Base.repo
            dnf clean all && dnf makecache
        fi
    fi
fi

# ----------------------------------------------------
# 核心 Docker 安装逻辑 (包含 RedHat 系 / Debian 系)
# ----------------------------------------------------
echo "正在为 $PRETTY_NAME 安装 Docker (使用阿里云源)..."

# 判断是否属于 RHEL 系 (CentOS, Rocky, AlmaLinux, RHEL 等)
if [ "$SYS_NAME" = "centos" ] || [ "$SYS_NAME" = "rocky" ] || [ "$SYS_NAME" = "almalinux" ] || [[ "$SYS_LIKE" =~ "rhel"|"fedora" ]]; then
    check_network
    
    # 卸载旧版本
    yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine &>/dev/null
    
    if command -v dnf &>/dev/null; then
        # 补齐 dnf config-manager 工具
        dnf install -y dnf-plugins-core &>/dev/null
        dnf config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin --allowerasing
    else
        yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi

# 判断是否属于 Debian/Ubuntu 系
elif [ "$SYS_NAME" = "ubuntu" ] || [ "$SYS_NAME" = "debian" ] || [[ "$SYS_LIKE" =~ "debian" ]]; then
    check_network
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/$SYS_NAME/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/$SYS_NAME $VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
    echo "错误: 暂不支持当前系统分支 ($SYS_NAME)。"
    exit 1
fi

# ----------------------------------------------------
# 配置 1ms.run 镜像加速器及启动服务
# ----------------------------------------------------
echo "配置 1ms.run 镜像加速器..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://1ms.run"]
}
EOF

# 启动并自启 Docker 服务
systemctl daemon-reload
systemctl enable docker
systemctl restart docker

# 验证安装结果
if command -v docker &>/dev/null; then
    echo "-------------------------------------------"
    docker --version
    if docker compose version &>/dev/null; then
        docker compose version
    fi
    echo "加速源: https://1ms.run"
    echo "Docker 安装成功！"
    echo "-------------------------------------------"
else
    echo "错误: Docker 安装失败，请检查上方日志。"
fi
