#!/bin/bash
# RVC翻唱工具 - 环境备份脚本（卖家使用）
# 在已经装好环境（install.sh 跑完）的 Termux 中运行
# 用法: bash backup.sh
#   完整版: 包含 hubert/rmvpe 模型文件，客户恢复后直接可用（推荐，默认）
#   精简版: bash backup.sh 精简 （不包含模型，备份包小，客户需自行放入 hubert/rmvpe）

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

MODE="${1:-完整}"

echo "=========================================="
echo "  RVC翻唱工具 - 环境备份"
echo "=========================================="
echo ""

# 1. 检查存储权限
if [ ! -d "$HOME/storage/downloads" ]; then
    echo -e "${RED}错误: 未授权访问手机存储${NC}"
    echo "请先运行: termux-setup-storage"
    echo "然后在弹出的系统弹窗中点击【允许】"
    exit 1
fi

# 2. 定位应用代码
APP_DIR="$HOME/rvc-app"
if [ ! -f "$APP_DIR/server.py" ]; then
    echo -e "${RED}错误: 找不到应用代码${NC}"
    echo "请把 RVC 应用代码（含 server.py 的文件夹）放到 ~/rvc-app"
    exit 1
fi

# 3. 检查Ubuntu环境是否已安装（兼容新旧版proot-distro目录）
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
    echo -e "${RED}错误: 未检测到Ubuntu虚拟系统${NC}"
    echo "请先运行: bash ~/rvc-app/install.sh"
    exit 1
fi

# 4. 提示模式
if [ "$MODE" = "精简" ]; then
    echo -e "${YELLOW}精简模式: 不包含 hubert/rmvpe 模型文件${NC}"
    echo "（客户恢复后需要把这两个文件放回对应目录）"
else
    echo -e "${GREEN}完整模式: 包含全部模型文件，客户恢复后直接可用${NC}"
fi
echo ""
echo -e "${YELLOW}注意: 环境较大（约3GB），打包可能需要10-30分钟，请保持屏幕常亮${NC}"
echo ""

# 5. 开始打包
cd /data/data/com.termux/files

BACKUP_NAME="rvc-termux-backup-$(date +%Y%m%d).tar.gz"
BACKUP_PATH="$HOME/storage/downloads/$BACKUP_NAME"

echo -e "${GREEN}[1/2] 正在打包运行环境（请耐心等待，不要关窗口）...${NC}"

# Ubuntu rootfs 在备份包内的相对路径（相对 /data/data/com.termux/files）
UBUNTU_REL="${UBUNTU_ROOTFS#$PREFIX/}"
# 容器内的 rvc-app 应用路径（打包时相对归档根）
CONTAINER_APP="usr/$UBUNTU_REL/root/rvc-app"

# 排除proot自动挂载的Android目录（宿主层无权限读取；客户恢复时proot会自动重建）
BIND_EXCLUDES=(
    --exclude="usr/$UBUNTU_REL/data"
    --exclude="usr/$UBUNTU_REL/mnt/sdcard"
    --exclude="usr/$UBUNTU_REL/sdcard"
    --exclude="usr/$UBUNTU_REL/storage"
    --exclude="usr/$UBUNTU_REL/apex"
    --exclude="usr/$UBUNTU_REL/odm"
    --exclude="usr/$UBUNTU_REL/product"
    --exclude="usr/$UBUNTU_REL/system"
    --exclude="usr/$UBUNTU_REL/system_ext"
    --exclude="usr/$UBUNTU_REL/vendor"
    --exclude="usr/$UBUNTU_REL/linkerconfig"
)

if [ "$MODE" = "精简" ]; then
    # 精简模式: 排除模型文件
    tar -czf "$BACKUP_PATH" \
        --exclude='usr/tmp/*' \
        --exclude='usr/var/cache/*' \
        --exclude='usr/var/log/*' \
        --exclude='usr/var/tmp/*' \
        --exclude='usr/var/lib/apt/*' \
        --exclude="usr/$UBUNTU_REL/var/cache/apt/*" \
        --exclude="usr/$UBUNTU_REL/root/.cache/*" \
        --exclude="usr/$UBUNTU_REL/tmp/*" \
        --exclude='*/__pycache__/*' \
        --exclude='*.pyc' \
        --exclude="$CONTAINER_APP/venv" \
        --exclude="$CONTAINER_APP/uploads/*" \
        --exclude="$CONTAINER_APP/outputs/*" \
        --exclude="$CONTAINER_APP/server.log" \
        --exclude="$CONTAINER_APP/assets/hubert/hubert_base.pt" \
        --exclude="$CONTAINER_APP/assets/rmvpe/rmvpe.pt" \
        --exclude="$CONTAINER_APP/models/*.pth" \
        "${BIND_EXCLUDES[@]}" \
        usr
else
    tar -czf "$BACKUP_PATH" \
        --exclude='usr/tmp/*' \
        --exclude='usr/var/cache/*' \
        --exclude='usr/var/log/*' \
        --exclude='usr/var/tmp/*' \
        --exclude='usr/var/lib/apt/*' \
        --exclude="usr/$UBUNTU_REL/var/cache/apt/*" \
        --exclude="usr/$UBUNTU_REL/root/.cache/*" \
        --exclude="usr/$UBUNTU_REL/tmp/*" \
        --exclude='*/__pycache__/*' \
        --exclude='*.pyc' \
        --exclude="$CONTAINER_APP/venv" \
        --exclude="$CONTAINER_APP/uploads/*" \
        --exclude="$CONTAINER_APP/outputs/*" \
        --exclude="$CONTAINER_APP/server.log" \
        "${BIND_EXCLUDES[@]}" \
        usr
fi

# 6. 计算大小
SIZE=$(du -h "$BACKUP_PATH" | cut -f1)

echo -e "${GREEN}[2/2] 打包完成！${NC}"
echo ""
echo "=========================================="
echo "  备份文件: $BACKUP_PATH"
echo "  文件大小: $SIZE"
echo "=========================================="
echo ""
echo "分发方法:"
echo "  1. 把备份文件拷到电脑（文件在 手机/Download 目录）"
echo "  2. 连同 Termux 安装包、restore.sh 一起发给客户"
echo "  3. 客户按 restore.sh 里的说明操作，恢复后直接可用"
echo ""
