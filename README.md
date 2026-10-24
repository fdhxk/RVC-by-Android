# RVC Android 翻唱工具

在 Android 手机上运行 [RVC](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI)（Retrieval-based Voice Conversion）语音转换的开源方案，专注于**离线翻唱**功能，无需实时变声。

核心思路：通过 Termux + proot-distro 运行一个虚拟 Ubuntu 环境，在标准 Linux 环境下安装 PyTorch 等依赖，用 Flask 提供一个极简的 Web 界面，浏览器上传音频 → 转换 → 下载结果。

## 特性

- 纯离线运行，不依赖云端服务
- 无需 root 权限
- CPU 推理，无需 GPU
- Web 界面，手机自带浏览器即可使用
- 支持模型上传、音频上传、变调、音高提取方法选择
- 一键安装 / 一键恢复分发

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

## 目录结构

```
android-rvc-app/
├── server.py            # Flask Web 服务器
├── rvc_inference.py     # RVC 推理封装
├── infer/               # RVC 核心推理模块
├── assets/
│   ├── hubert/          # hubert_base.pt（需自行下载）
│   └── rmvpe/           # rmvpe.pt（需自行下载）
├── models/              # 声音模型 (.pth)
├── templates/           # 网页模板
├── static/              # 前端资源
├── requirements.txt     # Python 依赖
├── install.sh           # 开发者安装脚本
├── start.sh             # 手动启动脚本
├── backup.sh            # 环境打包脚本
└── restore.sh           # 一键恢复脚本
```

## 快速开始（开发者 / 从源码安装）

1. 安装 [Termux](https://github.com/termux/termux-app/releases)（arm64 版本）
2. 打开 Termux，授权存储访问：

```bash
termux-setup-storage
```

3. 将本仓库代码放到 `~/rvc-app`，并准备模型文件（见下方「模型文件」）
4. 运行安装脚本：

```bash
bash ~/rvc-app/install.sh
```

5. 启动服务：

```bash
bash ~/rvc-app/start.sh
```

6. 浏览器打开 `http://localhost:8080`

## 分发方式

`backup.sh` 会将整个运行环境（含依赖、代码）打包成一个 `.tar.gz` 备份包，`restore.sh` 在目标设备上一键恢复。适合批量部署到非技术用户设备。

## 模型文件

以下模型文件因体积较大或版权原因，未包含在本仓库中，需自行下载后放入对应目录：

| 文件 | 目录 | 说明 |
|------|------|------|
| `hubert_base.pt` | `assets/hubert/` | HuBERT 特征提取模型，约 380MB |
| `rmvpe.pt` | `assets/rmvpe/` | RMVPE 音高提取模型 |
| `*.pth` | `models/` | RVC 声音模型（转换目标音色） |

`models/kikiV1.pth` 为官方示例模型，可自行替换。

## 依赖

主要依赖见 `requirements.txt`，包括：

- `torch==2.3.1` / `torchaudio==2.3.1`（CPU 版）
- `fairseq==0.12.2`、`faiss-cpu`、`librosa`、`parselmouth`、`pyworld`、`torchcrepe`
- `flask`、`flask-cors`、`av`

## 声明

本工具仅供学习研究使用，请勿用于以下用途：

- 冒充他人身份、伪造语音进行诈骗或误导
- 未经授权的商业用途，或侵犯他人声音权、肖像权

使用本工具所产生的一切后果由使用者自行承担。

## 第三方代码

- `infer/` 目录基于 [RVC-Project/Retrieval-based-Voice-Conversion-WebUI](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI)（MIT 协议）改造，版权归原作者所有，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

## 许可证

[GPL-3.0](LICENSE)
