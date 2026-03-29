#!/bin/bash
# =============================================
# Docker + Docker Compose 一键安装脚本
# 全系统适配 + 自动修复冲突 + 优先毫秒镜像
# =============================================

set -e

echo "=== Docker + Docker Compose 一键安装脚本（全系统适配版） ==="

# ==================== 1. 清理旧 Docker 残留 ====================
echo "正在清理旧的 Docker 源和密钥..."
sudo rm -f /etc/apt/sources.list.d/docker*.list
sudo rm -f /etc/apt/keyrings/docker*.gpg
sudo rm -f /etc/apt/keyrings/docker.asc
sudo rm -f /etc/yum.repos.d/docker-ce.repo 2>/dev/null || true

# ==================== 2. 检测系统 ====================
if [ -f /etc/os-release ]; then
    . /etc/os-release
else
    ID="unknown"
fi

echo "检测到系统: $ID $VERSION_ID"

# ==================== 3. 安装 Docker ====================
if command -v docker &> /dev/null; then
    echo "Docker 已安装，跳过安装步骤。"
else
    echo "正在安装 Docker..."

    case $ID in
        ubuntu|debian)
            echo "使用官方源安装（适配 Debian 13）..."
            sudo apt-get update
            sudo apt-get install -y ca-certificates curl gnupg lsb-release --fix-broken
            sudo mkdir -p /etc/apt/keyrings
            sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
            sudo chmod a+r /etc/apt/keyrings/docker.asc
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin --fix-broken
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
            echo "未知系统，使用官方通用脚本安装..."
            curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
            ;;
    esac

    echo "Docker 安装完成！"
fi

# ==================== 4. 启动 Docker ====================
sudo systemctl enable --now docker 2>/dev/null || true
sudo systemctl restart docker

# ==================== 5. 配置毫秒镜像加速源 ====================
echo "正在配置国内加速源（优先毫秒镜像）..."
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://dockerproxy.com",
    "https://docker.m.daocloud.io",
    "https://docker.1panel.live",
    "https://registry.docker-cn.com"
  ],
  "live-restore": true
}
EOF
sudo systemctl restart docker
echo "加速源配置完成！（已优先使用 https://docker.1ms.run）"

# ==================== 6. 验证 ====================
echo "验证 Docker..."
sudo docker run --rm hello-world

echo ""
echo "验证 Docker Compose..."
docker compose version

echo ""
echo "=========================================="
echo "✅ Docker + Docker Compose 安装并加速配置成功！"
echo "当前优先加速源：https://docker.1ms.run （毫秒镜像）"
echo "现在你可以直接安装 RustDesk 等项目了！"
echo "=========================================="
