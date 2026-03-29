#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${GREEN}开始检测系统环境并准备安装 Docker...${NC}"

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请以 root 用户运行或使用 sudo 执行此脚本${NC}"
    exit 1
fi

# 2. 识别系统发行版
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo -e "${RED}无法识别系统版本，请手动安装${NC}"
    exit 1
fi

echo -e "${YELLOW}检测到系统: $OS $VER${NC}"

# 3. 配置阿里云镜像源并安装 Docker
case $OS in
    ubuntu|debian|raspbian)
        apt-get update
        apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
        curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/$OS/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg --yes
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.aliyun.com/docker-ce/linux/$OS $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        ;;
    centos|rocky|almalinux|fedora)
        yum install -y yum-utils
        yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        # 如果是 Rocky/Alma 等，自动适配 repo 地址
        sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+g' /etc/yum.repos.d/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        ;;
    *)
        echo -e "${RED}暂不支持的系统类型: $OS${NC}"
        exit 1
        ;;
esac

# 4. 启动 Docker 并设置开机自启
systemctl enable --now docker

# 5. 配置 1ms.run 镜像加速源
echo -e "${YELLOW}正在配置 1ms.run 镜像加速...${NC}"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://1ms.run"]
}
EOF

# 重启服务使配置生效
systemctl daemon-reload
systemctl restart docker

# 6. 验证安装结果
echo -e "${GREEN}-------------------------------------------${NC}"
docker --version && echo -e "${GREEN}Docker 安装成功！${NC}"
docker compose version && echo -e "${GREEN}Docker Compose 安装成功！${NC}"
echo -e "${YELLOW}当前镜像加速源已设为: https://1ms.run${NC}"
echo -e "${GREEN}-------------------------------------------${NC}"
