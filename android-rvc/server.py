"""
RVC翻唱工具 Web服务器
提供翻唱功能的Web API
"""

import os
import sys
import uuid
import logging
import re
import time
from pathlib import Path

from flask import Flask, request, jsonify, send_file, render_template
from flask_cors import CORS
from werkzeug.utils import secure_filename

# 添加当前目录到路径
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, current_dir)

from rvc_inference import RVCInference

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 创建Flask应用
app = Flask(__name__, 
            static_folder='static',
            template_folder='templates')
CORS(app)

# 配置
app.config['UPLOAD_FOLDER'] = os.path.join(current_dir, 'uploads')
app.config['OUTPUT_FOLDER'] = os.path.join(current_dir, 'outputs')
app.config['MODELS_FOLDER'] = os.path.join(current_dir, 'models')
app.config['MAX_CONTENT_LENGTH'] = 1024 * 1024 * 1024  # 1GB限制（RVC模型.pth可能达上百MB）

# 允许的音频格式
ALLOWED_EXTENSIONS = {'wav', 'mp3', 'flac', 'ogg', 'm4a', 'aac'}

# 确保目录存在
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
os.makedirs(app.config['OUTPUT_FOLDER'], exist_ok=True)
os.makedirs(app.config['MODELS_FOLDER'], exist_ok=True)

# 文件清理配置
FILE_RETENTION_HOURS = 24  # 文件保留时间（小时）


def cleanup_old_files(folder, hours=FILE_RETENTION_HOURS):
    """清理指定目录中超过保留时间的文件"""
    try:
        cutoff_time = time.time() - hours * 3600
        for f in os.listdir(folder):
            filepath = os.path.join(folder, f)
            if os.path.isfile(filepath):
                if os.path.getmtime(filepath) < cutoff_time:
                    os.remove(filepath)
                    logger.info(f"已清理过期文件: {filepath}")
    except Exception as e:
        logger.error(f"清理文件失败: {str(e)}")

# 初始化RVC推理器
inference = RVCInference(models_dir=app.config['MODELS_FOLDER'])


def allowed_file(filename):
    """检查文件是否允许上传"""
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


@app.route('/')
def index():
    """主页"""
    return render_template('index.html')


@app.route('/api/models', methods=['GET'])
def list_models():
    """获取所有可用模型"""
    try:
        models = inference.list_models()
        return jsonify({
            'success': True,
            'models': models
        })
    except Exception as e:
        logger.error(f"获取模型列表失败: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/models/upload', methods=['POST'])
def upload_model():
    """上传模型文件"""
    try:
        if 'model' not in request.files:
            return jsonify({
                'success': False,
                'error': '没有上传模型文件'
            }), 400
        
        file = request.files['model']
        if file.filename == '':
            return jsonify({
                'success': False,
                'error': '未选择文件'
            }), 400
        
        if not file.filename.endswith('.pth'):
            return jsonify({
                'success': False,
                'error': '只支持.pth格式的模型文件'
            }), 400
        
        # 保存模型文件
        filename = secure_filename(file.filename)
        filepath = os.path.join(app.config['MODELS_FOLDER'], filename)
        file.save(filepath)
        
        # 获取模型信息
        model_info = inference.get_model_info(filepath)
        
        logger.info(f"模型上传成功: {filename}")
        return jsonify({
            'success': True,
            'message': '模型上传成功',
            'model': {
                'name': filename.rsplit('.', 1)[0],
                'path': filepath,
                'info': model_info
            }
        })
        
    except Exception as e:
        logger.error(f"模型上传失败: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/models/<model_name>/info', methods=['GET'])
def get_model_info(model_name):
    """获取模型详细信息"""
    try:
        # 验证模型名称
        if not re.match(r'^[\w\-]+$', model_name):
            return jsonify({
                'success': False,
                'error': '无效的模型名称'
            }), 400
        
        model_path = os.path.join(app.config['MODELS_FOLDER'], f"{model_name}.pth")
        if not os.path.exists(model_path):
            return jsonify({
                'success': False,
                'error': f'模型不存在: {model_name}'
            }), 404
        
        model_info = inference.get_model_info(model_path)
        
        return jsonify({
            'success': True,
            'model': {
                'name': model_name,
                'info': model_info
            }
        })
        
    except Exception as e:
        logger.error(f"获取模型信息失败: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/convert', methods=['POST'])
def convert_audio():
    """执行音频转换"""
    try:
        # 检查音频文件
        if 'audio' not in request.files:
            return jsonify({
                'success': False,
                'error': '没有上传音频文件'
            }), 400
        
        audio_file = request.files['audio']
        if audio_file.filename == '':
            return jsonify({
                'success': False,
                'error': '未选择音频文件'
            }), 400
        
        if not allowed_file(audio_file.filename):
            return jsonify({
                'success': False,
                'error': f'不支持的音频格式，支持: {", ".join(ALLOWED_EXTENSIONS)}'
            }), 400
        
        # 获取参数并验证范围
        model_name = request.form.get('model', '')
        
        try:
            f0_up_key = int(request.form.get('key', 0))
            if f0_up_key < -12 or f0_up_key > 12:
                return jsonify({'success': False, 'error': '变调参数必须在-12到12之间'}), 400
        except ValueError:
            return jsonify({'success': False, 'error': '无效的变调参数'}), 400
        
        f0_method = request.form.get('method', 'harvest')
        if f0_method not in ['harvest', 'pm', 'crepe']:
            return jsonify({'success': False, 'error': '无效的音高提取方法'}), 400
        
        try:
            index_rate = float(request.form.get('index_rate', 0.66))
            if index_rate < 0 or index_rate > 1:
                return jsonify({'success': False, 'error': '索引匹配率必须在0到1之间'}), 400
        except ValueError:
            return jsonify({'success': False, 'error': '无效的索引匹配率'}), 400
        
        try:
            filter_radius = int(request.form.get('filter_radius', 3))
            if filter_radius < 0 or filter_radius > 7:
                return jsonify({'success': False, 'error': '滤波半径必须在0到7之间'}), 400
        except ValueError:
            return jsonify({'success': False, 'error': '无效的滤波半径'}), 400
        
        try:
            rms_mix_rate = float(request.form.get('rms_mix_rate', 1.0))
            if rms_mix_rate < 0 or rms_mix_rate > 1:
                return jsonify({'success': False, 'error': 'RMS混合率必须在0到1之间'}), 400
        except ValueError:
            return jsonify({'success': False, 'error': '无效的RMS混合率'}), 400
        
        try:
            protect = float(request.form.get('protect', 0.33))
            if protect < 0 or protect > 0.5:
                return jsonify({'success': False, 'error': '保护参数必须在0到0.5之间'}), 400
        except ValueError:
            return jsonify({'success': False, 'error': '无效的保护参数'}), 400
        
        if not model_name:
            return jsonify({
                'success': False,
                'error': '未选择模型'
            }), 400
        
        # 查找模型文件
        model_path = os.path.join(app.config['MODELS_FOLDER'], f"{model_name}.pth")
        if not os.path.exists(model_path):
            return jsonify({
                'success': False,
                'error': f'模型不存在: {model_name}'
            }), 400
        
        # 保存上传的音频
        audio_filename = secure_filename(audio_file.filename)
        unique_filename = f"{uuid.uuid4().hex}_{audio_filename}"
        input_path = os.path.join(app.config['UPLOAD_FOLDER'], unique_filename)
        audio_file.save(input_path)
        
        # 生成输出文件名
        output_filename = f"converted_{unique_filename.rsplit('.', 1)[0]}.wav"
        output_path = os.path.join(app.config['OUTPUT_FOLDER'], output_filename)
        
        # 加载模型（如果需要或切换了模型）
        if inference.current_model_path != model_path or inference.net_g is None:
            inference.load_model(model_path)
        
        # 查找索引文件
        index_path = ""
        index_files = list(Path(app.config['MODELS_FOLDER']).glob(f"{model_name}*.index"))
        if index_files:
            index_path = str(index_files[0])
        
        # 执行转换
        logger.info(f"开始转换: {audio_filename} -> {output_filename}")
        success = inference.convert(
            input_path=input_path,
            output_path=output_path,
            f0_up_key=f0_up_key,
            f0_method=f0_method,
            index_path=index_path,
            index_rate=index_rate,
            filter_radius=filter_radius,
            rms_mix_rate=rms_mix_rate,
            protect=protect
        )
        
        if success:
            logger.info(f"转换完成: {output_filename}")
            return jsonify({
                'success': True,
                'message': '转换完成',
                'output_file': output_filename,
                'download_url': f'/api/download/{output_filename}'
            })
        else:
            return jsonify({
                'success': False,
                'error': '转换失败'
            }), 500
        
    except Exception as e:
        logger.error(f"转换失败: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/download/<filename>')
def download_file(filename):
    """下载转换后的音频"""
    try:
        # 防止路径遍历攻击
        if '..' in filename or '/' in filename or '\\' in filename:
            return jsonify({
                'success': False,
                'error': '无效的文件名'
            }), 400
        
        # 验证文件名格式（只允许字母数字、下划线、连字符和点）
        if not re.match(r'^[\w\-\.]+$', filename):
            return jsonify({
                'success': False,
                'error': '无效的文件名'
            }), 400
        
        filepath = os.path.join(app.config['OUTPUT_FOLDER'], filename)
        # 确保文件在输出目录内
        if not os.path.abspath(filepath).startswith(os.path.abspath(app.config['OUTPUT_FOLDER'])):
            return jsonify({
                'success': False,
                'error': '无效的文件路径'
            }), 400
        
        if not os.path.exists(filepath):
            return jsonify({
                'success': False,
                'error': '文件不存在'
            }), 404
        
        return send_file(
            filepath,
            as_attachment=True,
            download_name=filename
        )
        
    except Exception as e:
        logger.error(f"下载失败: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/status')
def get_status():
    """获取服务器状态"""
    return jsonify({
        'success': True,
        'status': 'running',
        'device': inference.device,
        'model_loaded': inference.net_g is not None,
        'models_count': len(inference.list_models())
    })


@app.errorhandler(413)
def too_large(e):
    """文件太大错误"""
    return jsonify({
        'success': False,
        'error': '文件太大，最大支持50MB'
    }), 413


@app.errorhandler(404)
def not_found(e):
    """404错误"""
    return jsonify({
        'success': False,
        'error': '资源不存在'
    }), 404


@app.errorhandler(500)
def internal_error(e):
    """500错误"""
    return jsonify({
        'success': False,
        'error': '服务器内部错误'
    }), 500


if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description="RVC Web服务器")
    parser.add_argument('--host', default='0.0.0.0', help='监听地址')
    parser.add_argument('--port', type=int, default=8080, help='监听端口')
    parser.add_argument('--debug', action='store_true', help='调试模式')
    
    args = parser.parse_args()
    
    logger.info(f"启动RVC Web服务器: http://{args.host}:{args.port}")
    # 启动时清理过期文件
    cleanup_old_files(app.config['UPLOAD_FOLDER'])
    cleanup_old_files(app.config['OUTPUT_FOLDER'])
    app.run(host=args.host, port=args.port, debug=args.debug)