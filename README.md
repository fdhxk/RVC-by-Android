# RVC Android 翻唱工具

在 Android 手机上运行 [RVC](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI)（Retrieval-based Voice Conversion）语音转换的开源方案，专注**离线翻唱**：浏览器上传音频 → 转换 → 下载结果。

无需 root、无需 GPU、纯离线运行，全程在手机上完成。

## 工作原理

```
Android
 └── Termux
      └── proot-distro (虚拟 Ubuntu 22.04)
           ├── Python 3.10 + PyTorch (CPU)
           ├── RVC 推理核心 (infer/)
           ├── Flask Web 服务器 (server.py)
           └── Web 界面 (templates/ + static/)
```

## 特性

- 纯离线运行，不依赖云端服务
- 无需 root 权限，CPU 推理
- Web 界面，手机自带浏览器即可使用
- 支持模型上传、音频上传、变调、音高提取方法选择
- 一键安装 / 一键恢复分发，适合非技术用户

## 快速开始

### 方式一：一键恢复（推荐，非技术用户）

1. 从 [Releases](https://github.com/fdhxk/RVC-by-Android/releases) 下载：
   - `Termux.apk`（Termux 安装包，请勿使用应用商店版本）
   - `rvc-termux-backup-xxx.tar.gz`（已打包好的完整运行环境）
   - `restore.sh`（安装向导）
2. 安装并打开 Termux，运行 `termux-setup-storage` 并允许存储权限
3. 将备份包和 `restore.sh` 放到手机「下载」文件夹
4. 运行：`bash /sdcard/Download/restore.sh`
5. 完成后重新打开 Termux，浏览器访问 `http://localhost:8080`

### 方式二：从源码部署（开发者）

1. 安装 Termux（arm64 版本）并运行 `termux-setup-storage`
2. 将本仓库代码放到 `~/rvc-app`，并准备模型文件
3. 运行 `bash ~/rvc-app/install.sh`，再运行 `bash ~/rvc-app/start.sh`
4. 浏览器打开 `http://localhost:8080`

详细说明见 [android-rvc/README.md](android-rvc/README.md)。

## 目录结构

```
RVC-by-Android/
├── android-rvc/           # 应用源码（Flask 服务器 + RVC 推理 + Web 界面）
│   ├── server.py          # Flask Web 服务器
│   ├── rvc_inference.py   # RVC 推理封装
│   ├── infer/             # RVC 核心推理模块（基于 RVC-Project，MIT 协议）
│   ├── install.sh         # 开发者安装脚本
│   └── README.md          # 开发者文档
├── restore.sh             # 一键安装向导（客户使用）
└── step.txt               # 安装步骤速查
```

## 模型文件

以下模型文件体积较大，未包含在 Git 仓库中，需自行下载或从 [Releases](https://github.com/fdhxk/RVC-by-Android/releases) 获取：

| 文件 | 目录 | 说明 |
|------|------|------|
| `hubert_base.pt` | `android-rvc/assets/hubert/` | HuBERT 特征提取模型，约 180MB |
| `rmvpe.pt` | `android-rvc/assets/rmvpe/` | RMVPE 音高提取模型 |
| `*.pth` | `android-rvc/models/` | RVC 声音模型（转换目标音色），仓库内置官方示例模型 |

## 声明

本工具仅供学习研究使用，请勿用于：

- 冒充他人身份、伪造语音进行诈骗或误导
- 未经授权的商业用途，或侵犯他人声音权、肖像权

使用本工具所产生的一切后果由使用者自行承担。

## 许可证

- `android-rvc/infer/` 基于 [RVC-Project/Retrieval-based-Voice-Conversion-WebUI](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI)（MIT 协议）改造，版权归原作者所有，详见 [THIRD_PARTY_NOTICES.md](android-rvc/THIRD_PARTY_NOTICES.md)
- 整体项目：[GPL-3.0](android-rvc/LICENSE)
