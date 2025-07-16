# SenseVox ASR Flutter Server App

一个基于 [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) [SenseVoice](https://github.com/FunAudioLLM/SenseVoice) 的本地语音识别 Flutter 服务端应用。

<img src="./image.jpg" alt="项目示意图" width="200" />

## 🧠 项目简介

本项目提供了一个 Flutter 实现的本地语音识别服务，适用于 Android 和 Windows。首次加载模型时将申请麦克风、存储等权限，请全部允许。加载过程会短暂阻塞，请耐心等待。

### ✅ 优点

- 基于 SenseVoice，识别精度高，响应速度快
- 支持多语言
- 本地部署

### ⚠️ 缺点

- AI开发，无法维护
- Bug和功耗未知

---

## ⏱️ 性能表现

### 模型加载时间（int8 模型）

| 设备           | 耗时       |
|----------------|------------|
| ZUK Z2         | 17.5 秒    |
| 红米 Note10 Pro| 5.2 秒     |

### 一句话识别耗时（本地）

| 设备           | 耗时       |
|----------------|------------|
| 骁龙 820       | 0.6 秒     |
| 天玑 1100      | 0.3 秒     |
| i7-12700H      | 小于0.1 秒     |

---

## 📦 模型下载与使用

- 下载地址：[点击下载模型](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2)
- 解压到任意位置

> 默认加载 `model.int8.onnx`，如需使用大模型，请重命名为相同名称。

### 模型内存占用

- int8 模型：约 650MB
- 大模型：未测试，预估约 2GB

---

## 📱 使用建议

- 移动设备麦克风录音效果更好，识别更准确
- 支持编译为 Windows 可执行程序
- IPv6 或公网访问暂未测试，如有需求请自行验证

---

## 📲 配套安卓语音输入法（可选）

- 
- 长按录音、松开识别

---

## 📡 接口示例

```bash
curl -X POST http://192.168.1.110:8000/asr \
  --header "Content-Type: audio/wav" \
  --data-binary "@zh.wav"
```

### 返回示例：

```json
{
  "status": "success",
  "result": "开放时间早上9点至下午5点。",
  "processing_time_ms": 2502,
  "recognition_time_ms": 2221
}
```

---

## 🙏 致谢

- [FunASR SenseVoice](https://github.com/FunAudioLLM/SenseVoice)
- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)
- AI 员工：
  - Claude 4 Sonnet（贡献最大）
  - OpenAI o3、Gemini 2.5 Pro
