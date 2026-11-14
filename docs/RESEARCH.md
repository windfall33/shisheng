# 拾声 v2 · 开源方案调研汇总（2026-11-09）

> 用户需求：实现前先调研可能用到的开源项目。本文 = 结论层；详细对比见两份底稿：
> - `D:\Zcode project\novel-audiobook\research\开源调研.md`（上一 session 全量对比：自托管 TTS 十家横评 / 端侧 sherpa-onnx / 同类管线 / 播放器 / 云 API 价格）
> - `RESEARCH-VERIFY.md`（本 session 一手核实：api_v2 源码、just_audio、许可勘误、同类项目活跃度）

## 1. 选型结论（本项目实际采用的）

| 环节 | 选型 | 许可 | 为什么 |
|---|---|---|---|
| TTS 引擎 | **GPT-SoVITS v2ProPlus**（api_v2 HTTP :9880） | MIT | 本机 RTF 实测 0.33 三家最快；参考音频 3-10s（强制校验）；零样本克隆 = 音色来源；Windows 整合包自带 Python+ffmpeg，本机 Python 3.15 太新的问题绕开 |
| 音色库 | **AISHELL-3**（OpenSLR **SLR93**，非 SLR33） | Apache-2.0 | 218 人、性别/年龄/口音标注，按角色挑说话人；本机已有 4 人×8 条 |
| 文本前端 | 自研 `textfront.py`（继承旧项目，126 万字真语料验证） | — | 章节正则三级切分/水印/脏字词表/引号分段/动词归因，规则被 1042 章实测校准 |
| 安卓播放 | **just_audio 0.10.6 + just_audio_background 0.0.1-beta.17**（ExoPlayer 底座） | MIT/Apache | 后台播放/锁屏/通知栏 MediaSession 一体解决；变速不变调 setSpeed；HTTP Range seek 依赖服务端 Range（已实现） |
| 音频容器 | **章 = 单一 CBR 64k mp3（无 Xing，虚拟拼接）** | — | mp3 帧自包含可无缝字节拼接；ExoPlayer 对 CBR 无 Xing 按码率估算时长 + Range seek 可用；避免了 MSE/分块播放两条复杂路 |
| 服务 | FastAPI + uvicorn（自研渲染队列） | — | 段级缓存/优先级队列/虚拟 Range 文件是本项目的定制核心，没有现成品 |

## 2. 明确不采用的与原因

- **ebook2audiobook / VoxNovel / huashuo**：借鉴流程（LLM 归属、人工校对、Whisper 对齐），不直接用——英文向、或引擎绑死 Qwen3-TTS/Kokoro；ebook2audiobook（Apache-2.0，20.5k star，仍活跃）是唯一可放心抄代码的，后续做 EPUB 时可回头借它的解析层。
- **Legado**：原仓库已无 LICENSE 文件且半年未推 → **代码一行不碰**，只借鉴章节正则思路（textfront 已独立实现并超额：去重/伪章/跳号处理）。
- **Fish/F5/ChatTTS/Spark/MegaTTS3**：权重禁商用或许可不清，不进主链路。
- **CosyVoice3 / IndexTTS-2.5**：本机可用、已装，作为对照引擎（CosyVoice 双 Apache 可换主；IndexTTS-2.5 权重是 bilibili 协议仅限个人使用）。
- **edge-tts / 云 API**：违反 ToS / 付费，全链路零付费目标下只做纸面备案（Azure F0 50 万字符/月）。

## 3. 核实修正（相对旧调研的勘误，全部一手来源）

1. api_v2 CLI 仅 `-a -p -c`（无 -g 设备参数）；`media_type` 只有 wav/raw/ogg/aac **没有 mp3** → 本项目 mp3 由管线自编（bundled ffmpeg libmp3lame）。
2. `speed_factor` 参数存在但 v2ProPlus 下不稳（旧实测注销）→ 语速一律放播放器 setSpeed，不进缓存键。
3. AISHELL-3 = **SLR93**；IndexTTS-2.5 权重 = **bilibili-model-license**（仅代码 Apache）；Fun-CosyVoice3 双 Apache-2.0；GPT-SoVITS MIT 确认。
4. just_audio_background 2025-05 后未更仍 beta——但 just_audio 0.10.6 本体活跃，beta 层极薄（MediaSession 封装），风险可控；Android cleartext 需 `usesCleartextTraffic`（已加）。

## 4. 本项目独有的闭环（调研中四家同类均未覆盖）

TXT 导入 → 引号/规则三级分声 → 自托管零样本克隆多音色 → 段级缓存 + 优先级队列边播边渲 → 章 = 虚拟 Range 流（边渲边播+任意跳转）→ 安卓断点续听。同类项目最多做到"LLM 标注 + 逐句合成"，没有渲染队列/续播/缓存闭环。
