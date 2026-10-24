#!/bin/bash
# RVC翻唱工具 - 启动脚本（在Ubuntu虚拟环境中启动服务器）
# 适用于Android Termux环境

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "  RVC翻唱工具 - 启动中..."
echo "=========================================="
echo ""

# 检查Ubuntu是否已安装（兼容新旧版proot-distro目录）
UBUNTU_ROOTFS=""
for d in \
    "$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs" \
    "$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu"; do
    if [ -d "$d" ]; then
        UBUNTU_ROOTFS="$d"
        break
    fi
done

if [ -z "$UBUNTU_ROOTFS" ]; then
    echo "错误: 未检测到Ubuntu虚拟系统，请先运行:"
    echo "  bash ~/rvc-app/install.sh"
    exit 1
fi

# 检查容器内的应用代码（代码已复制进容器 rootfs 的 /root/rvc-app）
CONTAINER_APP="$UBUNTU_ROOTFS/root/rvc-app"
if [ ! -f "$CONTAINER_APP/server.py" ]; then
    echo "错误: 容器内找不到 rvc-app/server.py"
    echo "请先运行: bash ~/rvc-app/install.sh"
    exit 1
fi

# 检查模型目录（容器内）
if [ ! -d "$CONTAINER_APP/models" ]; then
    mkdir -p "$CONTAINER_APP/models"
fi

# 检查是否有模型文件（容器内）
MODEL_COUNT=$(find "$CONTAINER_APP/models" -name "*.pth" 2>/dev/null | wc -l)
if [ "$MODEL_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}警告: models目录中没有找到模型文件(.pth)${NC}"
    echo "请将你的RVC模型文件放到 ~/rvc-app/models/ 目录，然后重新运行"
    echo "  bash ~/rvc-app/install.sh"
    echo "（或运行后通过网页上传模型）"
    echo ""
fi

# 获取本机IP地址
LOCAL_IP=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)

if [ -z "$LOCAL_IP" ]; then
    LOCAL_IP="localhost"
fi

# 设置端口
PORT=${1:-8080}

echo -e "${GREEN}启动信息:${NC}"
echo "  本地访问: http://localhost:$PORT"
if [ "$LOCAL_IP" != "localhost" ]; then
    echo "  局域网访问: http://$LOCAL_IP:$PORT"
fi
echo ""
echo "  模型数量: $MODEL_COUNT"
echo ""
echo "按 Ctrl+C 停止服务器"
echo "=========================================="
echo ""

# 在Ubuntu虚拟环境中启动服务器（用系统python3，无需venv）
# 清除Android环境变量，避免某些库误判为Android系统
proot-distro login ubuntu -- bash -c "unset ANDROID_ROOT ANDROID_DATA ANDROID_STORAGE ANDROID_ART_ROOT ANDROID_DEXPREOPT_ROOT ANDROID_TZDATA_ROOT 2>/dev/null; cd /root/rvc-app && exec python3 server.py --host 0.0.0.0 --port $PORT"
