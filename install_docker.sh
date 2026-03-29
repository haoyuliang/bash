#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 1. 识别系统并设置源 (适配 Debian 12/13 及主流 RHEL 系)
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    DEB_VERSION=$VERSION_CODENAME
    # 如果是 Debian 13 (trixie)，强制使用 12 (bookworm) 源
    [ "$DEB_VERSION" == "trixie" ] && DEB_VERSION="bookworm"
else
    echo -e "${RED}无法识别系统版本${NC}"
    exit 1
fi

echo -e "${YELLOW}正在为 $OS $VERSION_ID 安装 Docker (使用阿里云源)...${NC}"

if [[ "$OS" =~ ^(debian|ubuntu|raspbian)$ ]]; then
    # Debian 系安装逻辑
    apt-get update
    apt-get install -y apt-transport-https ca-certificates gnupg lsb-release
    curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/$OS/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg --yes
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.aliyun.com/docker-ce/linux/$OS $DEB_VERSION stable" > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
else
    # RedHat/CentOS/Rocky 逻辑
    yum install -y yum-utils
    yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
    sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+g' /etc/yum.repos.d/docker-ce.repo
    yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

# 2. 配置 1ms.run 镜像加速
echo -e "${YELLOW}配置 1ms.run 镜像加速器...${NC}"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://1ms.run"]
}
EOF

# 3. 启动并验证
systemctl daemon-reload
systemctl enable --now docker
systemctl restart docker

echo -e "${GREEN}-------------------------------------------${NC}"
docker --version && echo -e "${GREEN}Docker 安装成功！${NC}"
docker compose version && echo -e "${GREEN}Compose 安装成功！${NC}"
echo -e "${YELLOW}加速源: https://1ms.run${NC}"
echo -e "${GREEN}-------------------------------------------${NC}"
