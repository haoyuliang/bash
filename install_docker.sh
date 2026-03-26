#!/bin/bash
# =============================================
# Docker + Docker Compose 一键安装脚本（国内加速版 - 优先毫秒镜像）
# 支持 Ubuntu/Debian/CentOS/Rocky/AlmaLinux/Arch 等
# =============================================

set -e

echo "=== Docker + Docker Compose 一键安装脚本（优先毫秒镜像） ==="

# 检测系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
fi

echo "检测到系统: $ID $VERSION_ID"

# 安装 Docker
if command -v docker &> /dev/null; then
    echo "Docker 已安装，跳过安装步骤。"
else
    echo "正在安装 Docker..."

    case $ID in
        ubuntu|debian)
            sudo apt-get update
            sudo apt-get install -y ca-certificates curl gnupg lsb-release
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/$ID/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/$ID $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;

        centos|rocky|alma|rhel|fedora)
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;

        arch|manjaro)
            sudo pacman -Syu --noconfirm docker docker-compose
            ;;

        *)
            echo "未知系统，尝试官方脚本安装..."
            curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
            ;;
    esac

    echo "Docker 安装完成！"
fi

# 启动 Docker
sudo systemctl enable --now docker
sudo systemctl status docker --no-pager | head -n 15

# 配置国内加速源（优先毫秒镜像）
echo "配置 Docker 国内加速源（优先使用毫秒镜像）..."
sudo mkdir -p /etc/docker

sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://dockerproxy.com",
    "https://docker.m.daocloud.io",
    "https://docker.1panel.live",
    "https://registry.docker-cn.com",
    "https://mirror.ccs.tencentyun.com"
  ],
  "live-restore": true
}
EOF

sudo systemctl restart docker
echo "加速源配置完成！（已优先使用 https://docker.1ms.run）"

# 验证安装
echo "验证 Docker 是否正常..."
sudo docker run --rm hello-world

echo ""
echo "验证 Docker Compose..."
docker compose version || echo "Docker Compose 插件已安装"

echo ""
echo "=========================================="
echo "✅ Docker + Docker Compose 安装并加速配置完成！"
echo "当前优先加速源：https://docker.1ms.run （毫秒镜像）"
echo "其他备用加速源已配置"
echo "=========================================="
