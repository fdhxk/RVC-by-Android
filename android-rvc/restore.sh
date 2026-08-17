#!/bin/bash
# RVC翻唱工具 - 一键安装向导（客户使用）
#
# 使用方法（跟着做就行）：
#   1. 安装 Termux（用我们提供的安装包，不要用应用商店里的）
#   2. 打开 Termux 一次，等它初始化完成（出现绿色的提示）
#   3. 运行: termux-setup-storage
#      在弹出的系统弹窗中点击【允许】
#   4. 把 rvc-termux-backup-xxx.tar.gz 和本文件 放到手机【下载】文件夹
#   5. 运行: bash /sdcard/Download/restore.sh
#   6. 等它自动装完，关掉窗口重新打开 Termux 就能用了

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "  RVC翻唱工具 - 安装向导"
echo "=========================================="
echo ""

# 1. 检查存储权限
if [ ! -d "$HOME/storage/downloads" ]; then
    echo -e "${YELLOW}第一步：授权手机存储访问${NC}"
    echo "请运行: termux-setup-storage"
    echo "然后在弹出的系统弹窗中点击【允许】"
    echo "完成后重新运行: bash /sdcard/Download/restore.sh"
    exit 1
fi

# 2. 查找备份包
echo -e "${GREEN}[1/4] 查找备份包...${NC}"
BACKUP=""
for f in "$HOME"/storage/shared/Download/rvc-termux-backup-*.tar.gz; do
    [ -f "$f" ] && BACKUP="$f"
done

if [ -z "$BACKUP" ]; then
    echo -e "${RED}错误: 在【下载】文件夹没有找到备份包${NC}"
    echo "请把 rvc-termux-backup-xxx.tar.gz 放到手机【下载】文件夹后重新运行"
    echo "运行: bash /sdcard/Download/restore.sh"
    exit 1
fi
echo "  找到备份包: $(basename "$BACKUP")"
echo ""

# 3. 恢复环境
echo -e "${GREEN}[2/4] 正在恢复环境（约几分钟，请耐心等待，不要关窗口）...${NC}"
cd /data/data/com.termux/files
tar -xzf "$BACKUP"

# 验证恢复结果（兼容新旧版proot-distro目录）
UBUNTU_OK=""
for d in \
    "/data/data/com.termux/files/usr/var/lib/proot-distro/containers/ubuntu/rootfs" \
    "/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu"; do
    if [ -d "$d" ]; then
        UBUNTU_OK="$d"
        break
    fi
done
if [ -z "$UBUNTU_OK" ]; then
    echo -e "${RED}错误: 环境恢复不完整（缺少Ubuntu系统）${NC}"
    echo "可能是备份包损坏或下载不完整，请重新下载备份包后重试"
    exit 1
fi
if [ ! -f "$UBUNTU_OK/root/rvc-app/server.py" ]; then
    echo -e "${RED}错误: 环境恢复不完整（缺少应用代码）${NC}"
    echo "可能是备份包损坏或下载不完整，请重新下载备份包后重试"
    exit 1
fi
echo "  ✓ 环境恢复完成"
echo ""

# 4. 配置自动启动（以后打开 Termux 就自动启动服务）
echo -e "${GREEN}[3/4] 配置自动启动...${NC}"
if ! grep -q "RVC翻唱工具" "$HOME/.bashrc" 2>/dev/null; then
    cat >> "$HOME/.bashrc" << 'EOF'

# ===== RVC翻唱工具 自动启动 =====
# 查找Ubuntu容器路径（兼容新旧版proot-distro）
RVC_UBUNTU_ROOTFS=""
for RVC_D in \
    "$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs" \
    "$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu"; do
    if [ -d "$RVC_D" ]; then
        RVC_UBUNTU_ROOTFS="$RVC_D"
        break
    fi
done

RVC_PID_FILE="$RVC_UBUNTU_ROOTFS/root/rvc-app/server.pid"
rvc_is_running() {
    [ -f "$RVC_PID_FILE" ] && kill -0 "$(cat "$RVC_PID_FILE" 2>/dev/null)" 2>/dev/null
}

if [ -n "$RVC_UBUNTU_ROOTFS" ] && [ -f "$RVC_UBUNTU_ROOTFS/root/rvc-app/server.py" ] && ! rvc_is_running; then
    proot-distro login ubuntu -- bash -c 'unset ANDROID_ROOT ANDROID_DATA ANDROID_STORAGE ANDROID_ART_ROOT ANDROID_DEXPREOPT_ROOT ANDROID_TZDATA_ROOT 2>/dev/null; cd /root/rvc-app; nohup python3 server.py --host 0.0.0.0 --port 8080 > server.log 2>&1 & echo $! > server.pid'
    echo ""
    echo "[RVC] 服务正在后台启动（首次加载模型约需10-30秒）..."
    echo "[RVC] 本机打开: http://localhost:8080"
    if command -v ifconfig >/dev/null 2>&1; then
        RVC_IP=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)
        [ -n "$RVC_IP" ] && echo "[RVC] 其他设备打开: http://$RVC_IP:8080"
    fi
    echo ""
fi
unset RVC_UBUNTU_ROOTFS RVC_D RVC_PID_FILE RVC_IP 2>/dev/null
EOF
    echo "  ✓ 自动启动已配置"
else
    echo "  ✓ 已存在，跳过"
fi
echo ""

# 5. 完成
echo -e "${GREEN}[4/4] 完成！${NC}"
echo ""
echo "=========================================="
echo -e "${GREEN}安装完成！${NC}"
echo "=========================================="
echo ""
echo "使用方法:"
echo "  1. 关闭本窗口（输入 exit 回车，或点右上角X）"
echo "  2. 重新打开 Termux，服务会自动启动（首次稍慢，请等几秒）"
echo "  3. 在浏览器（自带浏览器即可）打开: http://localhost:8080"
echo ""
echo "注意事项:"
echo "  - 使用过程中请保持 Termux 窗口打开，不要清理后台"
echo "  - 手机连上 WiFi 后，电脑/平板可访问同一页面"
echo "    （打开 Termux 时屏幕会显示局域网地址）"
echo ""
