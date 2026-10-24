#!/bin/bash
# RVC翻唱工具 - 一键安装脚本（Ubuntu虚拟环境方案）
# 适用于Android Termux环境
# 原理: 在Termux中用proot-distro安装一个虚拟Ubuntu系统，
#       RVC跑在Ubuntu里，所有依赖都能正常pip安装

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "  RVC翻唱工具 - 安装脚本"
echo "=========================================="
echo ""

# 检查是否在Termux中运行
if [ -z "$TERMUX_VERSION" ]; then
    echo -e "${YELLOW}警告: 此脚本专为Termux设计，可能在其他环境中无法正常工作${NC}"
fi

# 检查代码位置
if [ ! -f "$HOME/rvc-app/server.py" ]; then
    echo -e "${RED}错误: 找不到 ~/rvc-app/server.py${NC}"
    echo "请先把代码（含 server.py 的文件夹）放到 ~/rvc-app"
    exit 1
fi

# 1. 更新包管理器并安装proot-distro
echo -e "${GREEN}[1/5] 更新包管理器并安装proot-distro...${NC}"
pkg update -y
pkg install -y proot-distro

# 2. 安装Ubuntu虚拟系统（若已安装则跳过）
echo -e "${GREEN}[2/5] 检查Ubuntu虚拟系统...${NC}"
# proot-distro 目录兼容检查（新版5.x用 containers/<名>/rootfs，旧版用 installed-rootfs/<名>）
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
    # 优先使用手机Download里已下载好的本地镜像（国内连Docker Hub会超时）
    LOCAL_ROOTFS=""
    for f in "$HOME"/storage/shared/Download/ubuntu-*.tar.xz "$HOME"/storage/shared/Download/ubuntu-*.tar.gz; do
        [ -f "$f" ] && LOCAL_ROOTFS="$f"
    done
    if [ -n "$LOCAL_ROOTFS" ]; then
        echo "检测到本地Ubuntu镜像: $(basename "$LOCAL_ROOTFS")"
        echo "正在导入（需要几分钟，请耐心等待）..."
        # 新版proot-distro(5.x)语法: install -n <容器名> <本地rootfs文件>
        # 必须指定 -n ubuntu，否则容器名会变成文件名，后续login会找不到
        proot-distro install -n ubuntu "$LOCAL_ROOTFS"
    else
        echo "未找到本地镜像，尝试在线下载Ubuntu系统（约500MB）"
        echo "提示: 国内网络下载Docker Hub可能超时。如果超时，请先在电脑上下载:"
        echo "  https://cloud-images.ubuntu.com/releases/jammy/release-20260320/ubuntu-22.04-server-cloudimg-arm64-root.tar.xz"
        echo "把文件放到手机Download目录后，重新运行本脚本即可自动导入"
        proot-distro install ubuntu
    fi
    # 重新确定容器路径（新安装的容器目录）
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
        echo -e "${RED}错误: Ubuntu安装后找不到容器目录，安装中止${NC}"
        exit 1
    fi
else
    echo "Ubuntu已安装，跳过"
fi

# 3. 将代码复制到Ubuntu容器内
# 重要: proot-distro登录后，容器内的 /root 就是容器rootfs的 /root，
#       不会自动共享Termux的home目录，所以代码必须复制进容器
echo -e "${GREEN}[3/5] 将代码复制到Ubuntu中...${NC}"
# 确保容器内有 /root 目录
mkdir -p "$UBUNTU_ROOTFS/root"
# 删除旧的venv（现在直接用系统python，不再使用venv）
rm -rf "$UBUNTU_ROOTFS/root/rvc-app"
cp -r "$HOME/rvc-app" "$UBUNTU_ROOTFS/root/rvc-app"
# 清掉运行时目录（上传/输出文件由服务器运行时自动创建）
rm -rf "$UBUNTU_ROOTFS/root/rvc-app/uploads" "$UBUNTU_ROOTFS/root/rvc-app/outputs"

# 4. 生成Ubuntu内的环境安装脚本（写入容器rootfs，登录后容器内可见）
echo -e "${GREEN}[4/5] 在Ubuntu中安装环境（软件源/依赖，需要几分钟）...${NC}"
cat > "$UBUNTU_ROOTFS/root/rvc_setup_ubuntu.sh" << 'SETUP'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# 确保DNS可用（proot环境可能没有resolv.conf）
if [ ! -s /etc/resolv.conf ]; then
    printf "nameserver 223.5.5.5\nnameserver 114.114.114.114\n" > /etc/resolv.conf
fi

# 清除Android环境变量（proot会从Termux继承），
# 否则pip的platformdirs会误判为Android系统并报错
unset ANDROID_ROOT ANDROID_DATA ANDROID_STORAGE \
      ANDROID_ART_ROOT ANDROID_DEXPREOPT_ROOT ANDROID_TZDATA_ROOT 2>/dev/null || true

echo "[Ubuntu] 配置国内软件源（加速下载）..."
if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
    sed -i \
        -e 's@http://ports.ubuntu.com/ubuntu-ports@http://mirrors.huaweicloud.com/ubuntu-ports@g' \
        -e 's@http://[a-z.]*archive\.ubuntu\.com/ubuntu@http://mirrors.huaweicloud.com/ubuntu@g' \
        -e 's@http://security\.ubuntu\.com/ubuntu@http://mirrors.huaweicloud.com/ubuntu@g' \
        /etc/apt/sources.list.d/ubuntu.sources
else
    sed -i \
        -e 's@http://ports.ubuntu.com/ubuntu-ports@http://mirrors.huaweicloud.com/ubuntu-ports@g' \
        -e 's@http://[a-z.]*archive\.ubuntu\.com/ubuntu@http://mirrors.huaweicloud.com/ubuntu@g' \
        -e 's@http://security\.ubuntu\.com/ubuntu@http://mirrors.huaweicloud.com/ubuntu@g' \
        /etc/apt/sources.list
fi

echo "[Ubuntu] 更新软件源..."
apt update -y

echo "[Ubuntu] 安装Python 3.10和基础工具..."
apt install -y python3.10 python3-pip ffmpeg libsndfile1 build-essential

echo "[Ubuntu] 安装Python依赖（torch较大，需要几分钟）..."
# 固定pip为24.0: 新版pip(24.1+)会拒绝omegaconf旧版metadata
# （`PyYAML (>=5.1.*)` 写法），导致fairseq依赖无法解析
pip3 install "pip==24.0" -i https://mirrors.huaweicloud.com/repository/pypi/simple
# --ignore-installed: Ubuntu系统自带的blinker等旧包是distutils安装的，
# pip无法卸载它们（Cannot uninstall 'blinker'），直接覆盖安装新版本
# 使用华为云pip镜像加速国内下载
pip3 install --ignore-installed -i https://mirrors.huaweicloud.com/repository/pypi/simple \
    -r /root/rvc-app/requirements.txt

echo "[Ubuntu] 环境准备完成"
SETUP

# 5. 在Ubuntu中执行安装
proot-distro login ubuntu -- bash /root/rvc_setup_ubuntu.sh
rm -f "$UBUNTU_ROOTFS/root/rvc_setup_ubuntu.sh"

# 6. 创建必要目录（容器内）
echo -e "${GREEN}[5/5] 创建必要目录...${NC}"
mkdir -p "$UBUNTU_ROOTFS/root/rvc-app/models" \
         "$UBUNTU_ROOTFS/root/rvc-app/uploads" \
         "$UBUNTU_ROOTFS/root/rvc-app/outputs"

# 完成
echo -e "${GREEN}安装完成！${NC}"
echo "=========================================="
echo ""
echo "接下来（打包分发给客户）:"
echo "  1. 运行备份脚本打包整个环境:"
echo "     bash ~/rvc-app/backup.sh"
echo "  2. 打包好的文件在 手机/Download 目录，连同 Termux 安装包和"
echo "     restore.sh 一起发给客户即可"
echo ""
echo "自己测试（可选）:"
echo "  1. 将你的RVC模型文件(.pth)放到 ~/rvc-app/models/ 目录后"
echo "     重新运行本脚本（代码会重新同步进Ubuntu）"
echo "  2. 运行: bash ~/rvc-app/start.sh"
echo "  3. 浏览器打开: http://localhost:8080"
echo ""
echo "如果遇到问题:"
echo "  - 需要至少3GB可用存储空间"
echo "  - 需要稳定的网络（要下载约1.5GB）"
echo "  - 安装中断可重新运行本脚本（会跳过已完成的步骤）"
echo ""
