"""
RVC简化版推理脚本（翻唱专用）
只保留翻唱功能，去除训练和实时变声相关代码
"""

import os
import sys
import logging
import traceback
from pathlib import Path

import numpy as np
import torch
import soundfile as sf
from scipy.io import wavfile

# 设置日志
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# 添加当前目录到路径
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, current_dir)

# 导入RVC核心模块
from infer.lib.audio import load_audio
from infer.lib.infer_pack.models import (
    SynthesizerTrnMs256NSFsid,
    SynthesizerTrnMs256NSFsid_nono,
    SynthesizerTrnMs768NSFsid,
    SynthesizerTrnMs768NSFsid_nono,
)
from infer.modules.vc.pipeline import Pipeline
from infer.modules.vc.utils import get_index_path_from_model
from infer.lib.jit.get_hubert import get_hubert_model


class RVCInference:
    """RVC推理类，封装翻唱功能"""
    
    def __init__(self, models_dir="models", device=None):
        """
        初始化RVC推理器
        
        Args:
            models_dir: 模型存放目录
            device: 计算设备（cpu/cuda/mps）
        """
        self.models_dir = Path(models_dir)
        self.models_dir.mkdir(exist_ok=True)
        
        # 供pipeline使用：rmvpe音高提取会读 rmvpe_root 环境变量
        os.environ.setdefault("rmvpe_root", os.path.join(current_dir, "assets", "rmvpe"))
        
        # 设置设备
        if device:
            self.device = device
        elif torch.cuda.is_available():
            self.device = "cuda:0"
        elif hasattr(torch.backends, 'mps') and torch.backends.mps.is_available():
            self.device = "mps"
        else:
            self.device = "cpu"
        
        self.is_half = self.device.startswith("cuda")
        self.net_g = None
        self.pipeline = None
        self.hubert_model = None
        self.tgt_sr = None
        self.version = None
        self.if_f0 = None
        self.cpt = None
        self.current_model_path = None  # 跟踪当前加载的模型路径
        
        logger.info(f"RVC推理器初始化完成，设备: {self.device}")
    
    def load_model(self, model_path):
        """
        加载RVC模型
        
        Args:
            model_path: 模型文件路径（.pth格式）
        """
        # 如果是同一个模型，跳过重新加载
        if self.current_model_path == model_path and self.net_g is not None:
            logger.info(f"模型已加载，跳过: {model_path}")
            return
        
        logger.info(f"加载模型: {model_path}")
        self.current_model_path = model_path
        
        # 加载模型权重
        self.cpt = torch.load(model_path, map_location="cpu")
        self.tgt_sr = self.cpt["config"][-1]
        self.cpt["config"][-3] = self.cpt["weight"]["emb_g.weight"].shape[0]
        self.if_f0 = self.cpt.get("f0", 1)
        self.version = self.cpt.get("version", "v1")
        
        # 根据版本选择模型类
        synthesizer_class = {
            ("v1", 1): SynthesizerTrnMs256NSFsid,
            ("v1", 0): SynthesizerTrnMs256NSFsid_nono,
            ("v2", 1): SynthesizerTrnMs768NSFsid,
            ("v2", 0): SynthesizerTrnMs768NSFsid_nono,
        }
        
        model_class = synthesizer_class.get(
            (self.version, self.if_f0), SynthesizerTrnMs256NSFsid
        )
        
        self.net_g = model_class(*self.cpt["config"], is_half=self.is_half)
        del self.net_g.enc_q
        
        self.net_g.load_state_dict(self.cpt["weight"], strict=False)
        self.net_g.eval().to(self.device)
        
        if self.is_half:
            self.net_g = self.net_g.half()
        else:
            self.net_g = self.net_g.float()
        
        # 创建pipeline
        self.pipeline = Pipeline(self.tgt_sr, self._get_config())
        
        logger.info(f"模型加载完成，版本: {self.version}，采样率: {self.tgt_sr}")
    
    def _get_config(self):
        """获取配置对象"""
        class Config:
            def __init__(self, device, is_half):
                self.device = device
                self.is_half = is_half
                # 显存充足配置：x_pad=3, x_query=10, x_center=60, x_max=65
                # 内存受限配置：x_pad=1, x_query=6, x_center=38, x_max=41
                if is_half:
                    self.x_pad, self.x_query, self.x_center, self.x_max = 3, 10, 60, 65
                else:
                    self.x_pad, self.x_query, self.x_center, self.x_max = 1, 6, 38, 41
        
        return Config(self.device, self.is_half)
    
    def load_hubert(self):
        """加载HuBERT模型"""
        if self.hubert_model is not None:
            return
        
        hubert_path = os.path.join(current_dir, "assets", "hubert", "hubert_base.pt")
        if not os.path.exists(hubert_path):
            raise FileNotFoundError(f"HuBERT模型不存在: {hubert_path}")
        
        logger.info("加载HuBERT模型...")
        # 必须用官方get_hubert_model()加载：hubert_base.pt是fairseq checkpoint，
        # torch.load拿到的是dict，无法直接.to()；get_hubert_model内部会用
        # load_model_ensemble_and_task还原成真正的模型对象
        self.hubert_model = get_hubert_model(hubert_path, torch.device(self.device))
        if self.is_half:
            self.hubert_model = self.hubert_model.half()
        else:
            self.hubert_model = self.hubert_model.float()
        self.hubert_model.eval()
        logger.info("HuBERT模型加载完成")
    
    def convert(self, input_path, output_path, f0_up_key=0, f0_method="harvest",
                index_path=None, index_rate=0.66, filter_radius=3, 
                resample_sr=0, rms_mix_rate=1, protect=0.33):
        """
        执行语音转换（翻唱）
        
        Args:
            input_path: 输入音频路径
            output_path: 输出音频路径
            f0_up_key: 变调（半音）
            f0_method: 音高提取方法（harvest/pm/crepe）
            index_path: FAISS索引路径
            index_rate: 索引匹配率
            filter_radius: 滤波半径
            resample_sr: 重采样率
            rms_mix_rate: RMS混合率
            protect: 保护参数
        
        Returns:
            是否成功
        """
        try:
            if self.net_g is None:
                raise RuntimeError("请先加载模型")
            
            # 加载HuBERT
            self.load_hubert()
            
            # 加载音频
            logger.info(f"加载音频: {input_path}")
            audio = load_audio(input_path, 16000)
            audio_max = np.abs(audio).max() / 0.95
            if audio_max > 1:
                audio /= audio_max
            
            # 获取索引路径
            if index_path is None or index_path == "":
                index_path = ""
            elif not os.path.exists(index_path):
                logger.warning(f"索引文件不存在: {index_path}")
                index_path = ""
            
            # 执行转换
            logger.info("开始语音转换...")
            times = [0, 0, 0]
            audio_opt = self.pipeline.pipeline(
                self.hubert_model,
                self.net_g,
                0,  # sid
                audio,
                input_path,
                times,
                f0_up_key,
                f0_method,
                index_path,
                index_rate,
                self.if_f0,
                filter_radius,
                self.tgt_sr,
                resample_sr,
                rms_mix_rate,
                self.version,
                protect,
                None,  # f0_file
            )
            
            # 确定输出采样率
            if self.tgt_sr != resample_sr >= 16000:
                tgt_sr = resample_sr
            else:
                tgt_sr = self.tgt_sr
            
            # 保存音频
            logger.info(f"保存音频: {output_path}")
            wavfile.write(output_path, tgt_sr, audio_opt)
            
            logger.info(f"转换完成，耗时: npy={times[0]:.2f}s, f0={times[1]:.2f}s, infer={times[2]:.2f}s")
            return True
            
        except Exception as e:
            logger.error(f"转换失败: {str(e)}")
            logger.error(traceback.format_exc())
            return False
    
    def list_models(self):
        """列出所有可用模型"""
        models = []
        for f in self.models_dir.glob("*.pth"):
            models.append({
                "name": f.stem,
                "path": str(f),
                "size": f.stat().st_size
            })
        return models
    
    def get_model_info(self, model_path):
        """获取模型信息"""
        try:
            cpt = torch.load(model_path, map_location="cpu")
            return {
                "version": cpt.get("version", "v1"),
                "f0": cpt.get("f0", 1),
                "sample_rate": cpt["config"][-1],
                "speakers": cpt["config"][-3]
            }
        except Exception as e:
            logger.error(f"获取模型信息失败: {str(e)}")
            return None


# 全局推理器实例
_inference = None


def get_inference(models_dir="models"):
    """获取全局推理器实例"""
    global _inference
    if _inference is None:
        _inference = RVCInference(models_dir)
    return _inference


if __name__ == "__main__":
    # 命令行测试
    import argparse
    
    parser = argparse.ArgumentParser(description="RVC翻唱工具")
    parser.add_argument("--model", required=True, help="模型路径")
    parser.add_argument("--input", required=True, help="输入音频路径")
    parser.add_argument("--output", required=True, help="输出音频路径")
    parser.add_argument("--key", type=int, default=0, help="变调（半音）")
    parser.add_argument("--method", default="harvest", help="音高提取方法")
    parser.add_argument("--index", default="", help="索引文件路径")
    
    args = parser.parse_args()
    
    inference = RVCInference()
    inference.load_model(args.model)
    success = inference.convert(
        args.input, 
        args.output, 
        f0_up_key=args.key,
        f0_method=args.method,
        index_path=args.index
    )
    
    if success:
        print("转换完成！")
    else:
        print("转换失败！")
        sys.exit(1)