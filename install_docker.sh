#!/bin/bash
# =============================================
# Docker + Docker Compose 一键安装脚本（国内优化版）
# 支持 Ubuntu/Debian/CentOS/Rocky/AlmaLinux 等
# =============================================

set -e

echo "=== Docker + Docker Compose 一键安装脚本（国内加速） ==="

# 1. 检测系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
fi

echo "检测到系统: $ID $VERSION_ID"

# 2. 安装 Docker
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
            echo "未知系统类型 ($ID)，尝试使用官方脚本安装..."
            curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
            ;;
    esac

    echo "Docker 安装完成！"
fi

# 3. 启动并设置开机自启
sudo systemctl enable --now docker
sudo systemctl status docker --no-pager | head -n 10

# 4. 配置国内镜像加速源（多个强加速）
echo "配置 Docker 国内加速源..."
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "registry-mirrors": [
    "https://dockerproxy.com",
    "https://docker.m.daocloud.io",
    "https://registry.docker-cn.com",
    "https://hub-mirror.c.163.com",
    "https://mirror.ccs.tencentyun.com"
  ],
  "live-restore": true
}
EOF

sudo systemctl restart docker
echo "Docker 加速源配置完成！"

# 5. 验证安装
echo "验证 Docker 是否正常运行..."
sudo docker run --rm hello-world

# 6. 验证 Docker Compose
echo "验证 Docker Compose..."
docker compose version || echo "Docker Compose 插件安装成功（使用 docker compose 命令）"

echo ""
echo "=========================================="
echo "✅ Docker + Docker Compose 安装成功！"
echo "快捷命令："
echo "  docker --version"
echo "  docker compose version"
echo "  sudo systemctl status docker"
echo "=========================================="
echo "现在你可以直接运行 RustDesk 等 Docker 项目了！"