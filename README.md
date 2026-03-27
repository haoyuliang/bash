# RustDesk Server (S6版) 一键管理脚本

这是一个专为 **RustDesk Server (S6 盒子版)** 设计的全自动部署与管理脚本。支持一键安装、更新、启动、停止及重启操作，内置多镜像加速源，解决国内环境拉取镜像慢的问题。

## 🌟 功能亮点
* **交互式安装**：自定义端口、带宽限制、加密策略等环境变量。
* **服务中控台**：实时查看容器状态、ID、映射路径、公钥及 API 管理密码。
* **智能加速**：内置多个 Docker 代理镜像源，自动切换确保拉取成功。
* **Readline 优化**：完美解决 Bash 脚本中常见的方向键乱码问题。
* **固定配置**：预设 `RUSTDESK_API_ADMIN_HELLO` 等优化参数。

## 🚀 快速开始

### 1. 一键执行命令 (推荐)
使用进程替换方式运行，可完美支持键盘交互，避免 `read` 命令失效：

```bash
bash <(curl -sSL [https://raw.githubusercontent.com/haoyuliang/bash/main/install_rustdesk.sh](https://raw.githubusercontent.com/haoyuliang/bash/main/install_rustdesk.sh))
