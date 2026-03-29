#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${GREEN}检查环境依赖...${NC}"

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请以 root 用户运行或使用 sudo 执行此脚本${NC}"
    exit 1
fi

# 2. 核心补丁：预安装 curl 和基础工具
echo -e "${YELLOW}正在确保系统拥有基础工具 (curl/gnupg)...${NC}"
if [ -f /etc/debian_version ]; then
    apt-get update && apt-get install -y curl gnupg ca-certificates lsb-release
elif [ -f /etc/redhat-release ]; then
    yum install -y curl gnupg2
fi

# 3. 识别系统发行版
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo -e "${RED}无法识别系统版本${NC}"
    exit 1
fi

echo -e "${YELLOW}检测到系统: $OS $VER${NC}"

# 4. 配置源并安装 (针对 Debian 12/13 特别适配)
case $OS in
    ubuntu|debian|raspbian)
        # 如果是 Debian 13 (trixie)，强制用 12 (bookworm) 的源，因为 13 目前还没出官方源
        DEB_VERSION=$VERSION_CODENAME
        if [ "$DEB_VERSION" == "trixie" ]; then
            DEB_VERSION="bookworm"
            echo -e "${YELLOW}检测到 Debian 13，正在使用 Bookworm 源进行兼容安装...${NC}"
        fi
        
        curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/$OS/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg --yes
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.aliyun.com/docker-ce/linux/$OS $DEB_VERSION stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        ;;
    centos|rocky|almalinux|fedora)
        yum install -y yum-utils
        yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+g' /etc/yum.repos.d/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        ;;
esac

# 5. 配置 1ms.run 镜像加速源
echo -e "${YELLOW}正在配置 1ms.run 镜像加速...${NC}"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://1ms.run"]
}
EOF

# 重启服务
systemctl daemon-reload
systemctl enable --now docker
systemctl restart docker

echo -e "${GREEN}安装完成！${NC}"
docker --version
docker compose version
