/**
 * RVC翻唱工具 - 前端JavaScript
 */

// API基础URL
const API_BASE = '';

// DOM元素
const elements = {
    // 状态
    statusDot: document.querySelector('.status-dot'),
    statusText: document.querySelector('.status-text'),
    
    // 模型
    modelSelect: document.getElementById('modelSelect'),
    refreshModels: document.getElementById('refreshModels'),
    modelInfo: document.getElementById('modelInfo'),
    modelVersion: document.getElementById('modelVersion'),
    modelSampleRate: document.getElementById('modelSampleRate'),
    
    // 模型上传
    uploadArea: document.getElementById('uploadArea'),
    modelFile: document.getElementById('modelFile'),
    uploadProgress: document.getElementById('uploadProgress'),
    progressFill: document.getElementById('progressFill'),
    progressText: document.getElementById('progressText'),
    
    // 音频
    audioUpload: document.getElementById('audioUpload'),
    audioFile: document.getElementById('audioFile'),
    audioPreview: document.getElementById('audioPreview'),
    audioName: document.getElementById('audioName'),
    audioSize: document.getElementById('audioSize'),
    audioPlayer: document.getElementById('audioPlayer'),
    clearAudio: document.getElementById('clearAudio'),
    
    // 参数
    f0UpKey: document.getElementById('f0UpKey'),
    f0UpKeyValue: document.getElementById('f0UpKeyValue'),
    f0Method: document.getElementById('f0Method'),
    indexRate: document.getElementById('indexRate'),
    indexRateValue: document.getElementById('indexRateValue'),
    filterRadius: document.getElementById('filterRadius'),
    filterRadiusValue: document.getElementById('filterRadiusValue'),
    rmsMixRate: document.getElementById('rmsMixRate'),
    rmsMixRateValue: document.getElementById('rmsMixRateValue'),
    protect: document.getElementById('protect'),
    protectValue: document.getElementById('protectValue'),
    
    // 操作
    convertBtn: document.getElementById('convertBtn'),
    
    // 结果
    resultSection: document.getElementById('resultSection'),
    resultStatus: document.getElementById('resultStatus'),
    resultTime: document.getElementById('resultTime'),
    resultPlayer: document.getElementById('resultPlayer'),
    downloadBtn: document.getElementById('downloadBtn'),
    convertAgain: document.getElementById('convertAgain'),
    
    // 加载
    loadingOverlay: document.getElementById('loadingOverlay'),
    loadingText: document.getElementById('loadingText'),
    
    // 消息
    toastContainer: document.getElementById('toastContainer')
};

// 状态
let state = {
    selectedModel: '',
    selectedAudio: null,
    currentOutputFile: '',
    isConverting: false
};

/**
 * 初始化应用
 */
function init() {
    setupEventListeners();
    checkServerStatus();
    loadModels();
}

/**
 * 设置事件监听器
 */
function setupEventListeners() {
    // 模型选择
    elements.modelSelect.addEventListener('change', handleModelSelect);
    elements.refreshModels.addEventListener('click', loadModels);
    
    // 模型上传
    elements.uploadArea.addEventListener('click', () => elements.modelFile.click());
    elements.uploadArea.addEventListener('dragover', handleDragOver);
    elements.uploadArea.addEventListener('dragleave', handleDragLeave);
    elements.uploadArea.addEventListener('drop', handleModelDrop);
    elements.modelFile.addEventListener('change', handleModelUpload);
    
    // 音频上传
    elements.audioUpload.addEventListener('click', () => elements.audioFile.click());
    elements.audioUpload.addEventListener('dragover', handleDragOver);
    elements.audioUpload.addEventListener('dragleave', handleDragLeave);
    elements.audioUpload.addEventListener('drop', handleAudioDrop);
    elements.audioFile.addEventListener('change', handleAudioUpload);
    elements.clearAudio.addEventListener('click', clearAudio);
    
    // 参数滑块
    elements.f0UpKey.addEventListener('input', (e) => {
        elements.f0UpKeyValue.textContent = e.target.value;
    });
    elements.indexRate.addEventListener('input', (e) => {
        elements.indexRateValue.textContent = e.target.value;
    });
    elements.filterRadius.addEventListener('input', (e) => {
        elements.filterRadiusValue.textContent = e.target.value;
    });
    elements.rmsMixRate.addEventListener('input', (e) => {
        elements.rmsMixRateValue.textContent = e.target.value;
    });
    elements.protect.addEventListener('input', (e) => {
        elements.protectValue.textContent = e.target.value;
    });
    
    // 转换按钮
    elements.convertBtn.addEventListener('click', startConvert);
    
    // 结果操作
    elements.downloadBtn.addEventListener('click', downloadResult);
    elements.convertAgain.addEventListener('click', resetForm);
}

/**
 * 检查服务器状态
 */
async function checkServerStatus() {
    try {
        const response = await fetch(`${API_BASE}/api/status`);
        const data = await response.json();
        
        if (data.success) {
            updateStatus('connected', `已连接 (${data.device})`);
        } else {
            updateStatus('error', '连接失败');
        }
    } catch (error) {
        updateStatus('error', '无法连接服务器');
        console.error('检查服务器状态失败:', error);
    }
}

/**
 * 更新连接状态
 */
function updateStatus(status, text) {
    elements.statusDot.className = 'status-dot';
    if (status === 'connected') {
        elements.statusDot.classList.add('connected');
    } else if (status === 'error') {
        elements.statusDot.classList.add('error');
    }
    elements.statusText.textContent = text;
}

/**
 * 加载模型列表
 */
async function loadModels() {
    try {
        const response = await fetch(`${API_BASE}/api/models`);
        const data = await response.json();
        
        if (data.success) {
            renderModels(data.models);
        } else {
            showToast('加载模型失败: ' + data.error, 'error');
        }
    } catch (error) {
        showToast('加载模型列表失败', 'error');
        console.error('加载模型列表失败:', error);
    }
}

/**
 * 渲染模型列表
 */
function renderModels(models) {
    elements.modelSelect.innerHTML = '<option value="">-- 请选择模型 --</option>';
    
    models.forEach(model => {
        const option = document.createElement('option');
        option.value = model.name;
        option.textContent = `${model.name} (${formatFileSize(model.size)})`;
        elements.modelSelect.appendChild(option);
    });
}

/**
 * 处理模型选择
 */
async function handleModelSelect(e) {
    state.selectedModel = e.target.value;
    updateConvertButton();
    
    if (state.selectedModel) {
        // 加载模型详细信息
        elements.modelInfo.style.display = 'block';
        elements.modelVersion.textContent = '加载中...';
        elements.modelSampleRate.textContent = '加载中...';
        
        try {
            const response = await fetch(`${API_BASE}/api/models/${encodeURIComponent(state.selectedModel)}/info`);
            const data = await response.json();
            
            if (data.success && data.model.info) {
                const info = data.model.info;
                elements.modelVersion.textContent = info.version || '未知';
                elements.modelSampleRate.textContent = info.sample_rate ? `${info.sample_rate} Hz` : '未知';
            } else {
                elements.modelVersion.textContent = '未知';
                elements.modelSampleRate.textContent = '未知';
            }
        } catch (error) {
            console.error('加载模型信息失败:', error);
            elements.modelVersion.textContent = '未知';
            elements.modelSampleRate.textContent = '未知';
        }
    } else {
        elements.modelInfo.style.display = 'none';
    }
}

/**
 * 处理拖拽悬停
 */
function handleDragOver(e) {
    e.preventDefault();
    e.currentTarget.classList.add('dragover');
}

/**
 * 处理拖拽离开
 */
function handleDragLeave(e) {
    e.currentTarget.classList.remove('dragover');
}

/**
 * 处理模型拖放
 */
function handleModelDrop(e) {
    e.preventDefault();
    e.currentTarget.classList.remove('dragover');
    
    const files = e.dataTransfer.files;
    if (files.length > 0 && files[0].name.endsWith('.pth')) {
        uploadModel(files[0]);
    } else {
        showToast('请上传 .pth 格式的模型文件', 'error');
    }
}

/**
 * 处理模型上传
 */
function handleModelUpload(e) {
    const file = e.target.files[0];
    if (file) {
        uploadModel(file);
    }
}

/**
 * 上传模型
 */
async function uploadModel(file) {
    const formData = new FormData();
    formData.append('model', file);
    
    elements.uploadProgress.style.display = 'flex';
    elements.progressFill.style.width = '0%';
    elements.progressText.textContent = '0%';
    
    try {
        const xhr = new XMLHttpRequest();
        
        xhr.upload.addEventListener('progress', (e) => {
            if (e.lengthComputable) {
                const percent = Math.round((e.loaded / e.total) * 100);
                elements.progressFill.style.width = `${percent}%`;
                elements.progressText.textContent = `${percent}%`;
            }
        });
        
        xhr.addEventListener('load', () => {
            if (xhr.status === 200) {
                const data = JSON.parse(xhr.responseText);
                if (data.success) {
                    showToast('模型上传成功', 'success');
                    loadModels();
                } else {
                    showToast('模型上传失败: ' + data.error, 'error');
                }
            } else {
                let msg = '模型上传失败';
                if (xhr.status === 413) {
                    msg = '模型文件太大，超过上传限制';
                } else if (xhr.responseText) {
                    try {
                        const d = JSON.parse(xhr.responseText);
                        if (d && d.error) msg += ': ' + d.error;
                    } catch (e) {}
                }
                showToast(msg, 'error');
            }
            elements.uploadProgress.style.display = 'none';
        });
        
        xhr.addEventListener('error', () => {
            showToast('模型上传失败', 'error');
            elements.uploadProgress.style.display = 'none';
        });
        
        xhr.open('POST', `${API_BASE}/api/models/upload`);
        xhr.send(formData);
        
    } catch (error) {
        showToast('模型上传失败', 'error');
        elements.uploadProgress.style.display = 'none';
        console.error('模型上传失败:', error);
    }
}

/**
 * 处理音频拖放
 */
function handleAudioDrop(e) {
    e.preventDefault();
    e.currentTarget.classList.remove('dragover');
    
    const files = e.dataTransfer.files;
    if (files.length > 0) {
        handleAudioFile(files[0]);
    }
}

/**
 * 处理音频上传
 */
function handleAudioUpload(e) {
    const file = e.target.files[0];
    if (file) {
        handleAudioFile(file);
    }
}

/**
 * 处理音频文件
 */
function handleAudioFile(file) {
    const allowedExtensions = ['wav', 'mp3', 'flac', 'ogg', 'm4a', 'aac'];
    const extension = file.name.split('.').pop().toLowerCase();
    
    if (!allowedExtensions.includes(extension)) {
        showToast('不支持的音频格式', 'error');
        return;
    }
    
    state.selectedAudio = file;
    
    // 显示预览
    elements.audioUpload.style.display = 'none';
    elements.audioPreview.style.display = 'block';
    elements.audioName.textContent = file.name;
    elements.audioSize.textContent = formatFileSize(file.size);
    
    // 创建音频预览
    const audioUrl = URL.createObjectURL(file);
    elements.audioPlayer.src = audioUrl;
    
    updateConvertButton();
}

/**
 * 清除音频
 */
function clearAudio() {
    state.selectedAudio = null;
    elements.audioUpload.style.display = 'block';
    elements.audioPreview.style.display = 'none';
    elements.audioFile.value = '';
    updateConvertButton();
}

/**
 * 更新转换按钮状态
 */
function updateConvertButton() {
    elements.convertBtn.disabled = !state.selectedModel || !state.selectedAudio || state.isConverting;
}

/**
 * 开始转换
 */
async function startConvert() {
    if (!state.selectedModel || !state.selectedAudio || state.isConverting) {
        return;
    }
    
    state.isConverting = true;
    updateConvertButton();
    showLoading('正在转换中，请稍候...');
    
    const formData = new FormData();
    formData.append('audio', state.selectedAudio);
    formData.append('model', state.selectedModel);
    formData.append('key', elements.f0UpKey.value);
    formData.append('method', elements.f0Method.value);
    formData.append('index_rate', elements.indexRate.value);
    formData.append('filter_radius', elements.filterRadius.value);
    formData.append('rms_mix_rate', elements.rmsMixRate.value);
    formData.append('protect', elements.protect.value);
    
    try {
        const startTime = Date.now();
        
        const response = await fetch(`${API_BASE}/api/convert`, {
            method: 'POST',
            body: formData
        });
        
        const data = await response.json();
        const endTime = Date.now();
        const duration = ((endTime - startTime) / 1000).toFixed(1);
        
        hideLoading();
        
        if (data.success) {
            state.currentOutputFile = data.output_file;
            showResult(true, duration);
            showToast('转换完成！', 'success');
        } else {
            showResult(false, duration, data.error);
            showToast('转换失败: ' + data.error, 'error');
        }
    } catch (error) {
        hideLoading();
        showResult(false, 0, '请求失败');
        showToast('转换请求失败', 'error');
        console.error('转换失败:', error);
    } finally {
        state.isConverting = false;
        updateConvertButton();
    }
}

/**
 * 显示结果
 */
function showResult(success, duration, error = '') {
    elements.resultSection.style.display = 'block';
    elements.resultSection.classList.add('fade-in');
    
    if (success) {
        elements.resultStatus.textContent = '成功';
        elements.resultStatus.style.color = 'var(--success-color)';
        elements.resultTime.textContent = `${duration}秒`;
        
        // 加载音频
        elements.resultPlayer.src = `${API_BASE}/api/download/${state.currentOutputFile}`;
        elements.downloadBtn.style.display = 'flex';
    } else {
        elements.resultStatus.textContent = '失败';
        elements.resultStatus.style.color = 'var(--danger-color)';
        elements.resultTime.textContent = '-';
        elements.resultPlayer.src = '';
        elements.downloadBtn.style.display = 'none';
        
        if (error) {
            showToast(`转换失败: ${error}`, 'error');
        }
    }
    
    // 滚动到结果
    elements.resultSection.scrollIntoView({ behavior: 'smooth' });
}

/**
 * 下载结果
 */
function downloadResult() {
    if (state.currentOutputFile) {
        const link = document.createElement('a');
        link.href = `${API_BASE}/api/download/${state.currentOutputFile}`;
        link.download = state.currentOutputFile;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }
}

/**
 * 重置表单
 */
function resetForm() {
    state.selectedAudio = null;
    state.currentOutputFile = '';
    
    elements.audioUpload.style.display = 'block';
    elements.audioPreview.style.display = 'none';
    elements.audioFile.value = '';
    elements.resultSection.style.display = 'none';
    
    updateConvertButton();
    
    // 滚动到顶部
    window.scrollTo({ top: 0, behavior: 'smooth' });
}

/**
 * 显示加载提示
 */
function showLoading(text = '处理中...') {
    elements.loadingText.textContent = text;
    elements.loadingOverlay.style.display = 'flex';
}

/**
 * 隐藏加载提示
 */
function hideLoading() {
    elements.loadingOverlay.style.display = 'none';
}

/**
 * 显示消息提示
 */
function showToast(message, type = 'info') {
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.textContent = message;
    
    elements.toastContainer.appendChild(toast);
    
    // 自动移除
    setTimeout(() => {
        toast.style.animation = 'slideIn 0.3s ease reverse';
        setTimeout(() => toast.remove(), 300);
    }, 3000);
}

/**
 * 格式化文件大小
 */
function formatFileSize(bytes) {
    if (bytes === 0) return '0 B';
    
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

// 初始化应用
document.addEventListener('DOMContentLoaded', init);