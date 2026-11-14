# 落地前开源方案核实（RESEARCH-VERIFY）

> 核实日期：2026-11-09。方法：gh-proxy 拉取源码/LICENSE 原文逐一核对；GitHub API（经 gh-proxy 代理）取仓库统计；pub.dev API、OpenSLR 官方页、hf-mirror 模型页。上游调研：`D:\Zcode project\novel-audiobook\research\开源调研.md`，凡与原调研不符处已标出。

## 1. GPT-SoVITS api_v2.py API 契约 —— 已按 main 分支源码实测

**结论**：
- 启动仅 3 个参数：`-a` 绑定地址(默认 127.0.0.1)、`-p` 端口(默认 9880)、`-c` 配置路径；**没有 -g 设备参数**，设备由 tts_infer.yaml 的 `device`/`is_half` 字段控制（原调研的"-g"说法需修正）。
- GET/POST /tts 参数一致：必填 `text`/`text_lang`/`ref_audio_path`/`prompt_lang`；可选 `prompt_text`、`aux_ref_audio_paths`、`top_k=15`、`top_p=1`、`temperature=1`、`text_split_method=cut5`(cut0~cut5)、`batch_size=1`、`batch_threshold=0.75`、`split_bucket`、**`speed_factor=1.0`（可用）**、`fragment_interval`、`seed`、`parallel_infer`、`repetition_penalty=1.35`、`streaming_mode`(0/1/2/3 或 bool)、`sample_steps`(V3+) 等。
- `media_type` 仅 **wav / raw / ogg / aac**，无 mp3；ogg 有 libsndfile 大音频栈溢出坑(#1199)，aac 走 ffmpeg。
- 返回：成功 200 直接音频流（流式 wav 先发一个 44 字节头，其后为裸 PCM）；失败 400 JSON `{"message":"tts failed","Exception":...}`。
- 参考音频 **3~10 秒为强制校验**（TTS.py L918，超限直接报错拒绝合成）。
- v2ProPlus 在 tts_infer.yaml 是独立段 `v2ProPlus:`，字段 `t2s_weights_path: .../s1v3.ckpt`、`vits_weights_path: .../v2Pro/s2Gv2ProPlus.pth`、`version: v2ProPlus` + bert/cnhuhbert/device/is_half；但 **实际加载的是 `custom:` 段**（TTS.py L403 `configs_.get("custom", configs_["v2"])`），用 v2ProPlus 须把 custom 段的 version 与两条权重路径改成上述值。
- 其它端点：/control(restart/exit)、/set_gpt_weights、/set_sovits_weights。

**出处**：[api_v2.py](https://github.com/RVC-Boss/GPT-SoVITS/blob/main/api_v2.py)、[TTS.py](https://github.com/RVC-Boss/GPT-SoVITS/blob/main/GPT_SoVITS/TTS_infer_pack/TTS.py)、[tts_infer.yaml](https://github.com/RVC-Boss/GPT-SoVITS/blob/main/GPT_SoVITS/configs/tts_infer.yaml)（raw 原文，main@2026-11-09）

**对本项目影响**：合成队列按句 POST JSON、media_type=wav 落盘最稳；参考音频入库前必须预裁剪到 3-10s；切 v2ProPlus 靠改 yaml 而非命令行。

## 2. just_audio 0.10.x + just_audio_background —— 已按 pub.dev API 与 README 核实

**结论**：
- 最新版：just_audio **0.10.6**（2026-06-29 发布）；just_audio_background **0.0.1-beta.17**（2025-05-13，仍 beta，依赖 just_audio_platform_interface ^4.5.0，与 0.10.x 同代）。
- 最小接入：`main()` 里 `JustAudioBackground.init(androidNotificationChannelId:..., androidNotificationOngoing: true)`；每个 `AudioSource.uri(..., tag: MediaItem(...))`。AndroidManifest：加 WAKE_LOCK、FOREGROUND_SERVICE、FOREGROUND_SERVICE_MEDIA_PLAYBACK(targetSdk 34+)；MainActivity 改继承 `com.ryanheise.audioservice.AudioServiceActivity`；声明 AudioService（`foregroundServiceType="mediaPlayback"`）+ MediaButtonReceiver；iOS 加 UIBackgroundModes=audio。
- 明文 HTTP：README 明确两处要求——播放 http URL 需 `android:usesCleartextTraffic="true"`；且 just_audio 的本地代理（headers/缓存/流源实现）跑在 localhost HTTP 上，同样需要 cleartext。可用 network_security_config.xml 只放行 127.0.0.1（更安全）。
- 变速：`player.setSpeed(2.0)` 与 `setPitch`（仅 Android）是独立控制，即**变速不变调**（ExoPlayer 以 Sonic 时域拉伸改速度，音高不动）。
- MP3 CBR 网络流 + Range seek：media3 Mp3Extractor 按 Xing/Info/VBRI 头 seek，无头时回退恒定码率估算（CBR 可用）；DefaultHttpDataSource 在 seek 时构造 `Range` 请求头 → **服务端支持 Range 即可流内 seek**；LockCachingAudioSource（边播边缓存）为实验特性，走同一 localhost 代理。

**出处**：[just_audio](https://pub.dev/packages/just_audio)（pub.dev API 实测版本/日期）、[just_audio README](https://github.com/ryanheise/just_audio/blob/master/just_audio/README.md)（cleartext 段落）、[Mp3Extractor.java](https://github.com/androidx/media/blob/release/libraries/extractor/src/main/java/androidx/media3/extractor/mp3/Mp3Extractor.java)、[DefaultHttpDataSource.java](https://github.com/androidx/media/blob/release/libraries/datasource/src/main/java/androidx/media3/datasource/DefaultHttpDataSource.java)

**对本项目影响**：cleartext 用 network_security_config 放行 127.0.0.1 + PC 局域网 IP；章节音频落盘后本地 seek 最稳，HTTP 流只做试听；后台播放先用 just_audio_background，复杂通知需求再升级 audio_service。

## 3. 许可速核 —— 均已核对原文/官方页

**结论**：
- **GPT-SoVITS：MIT**（LICENSE 原文 "MIT License, Copyright (c) 2024 RVC-Boss"，已读原文）。
- **AISHELL-3：Apache-2.0**，OpenSLR 编号是 **SLR93**（原调研写 SLR33 有误，SLR33 是 AISHELL-1）；218 人约 85 小时。
- **IndexTTS-2.5**：代码 Apache-2.0；**权重是 bilibili-model-license（B 站自定义许可，非标准开源）**——"代码+权重均 Apache-2.0"仅对 1/1.5 成立，2.5 权重自用无碍、商用须单独读条款。
- **Fun-CosyVoice3**：代码（FunAudioLLM/CosyVoice）Apache-2.0；权重（HF Fun-CosyVoice3-0.5B-2512）**Apache-2.0**，双开放。

**出处**：[GPT-SoVITS LICENSE](https://github.com/RVC-Boss/GPT-SoVITS/blob/main/LICENSE)、[OpenSLR SLR93](https://www.openslr.org/93/)、[IndexTeam/IndexTTS-2.5](https://huggingface.co/IndexTeam/IndexTTS-2.5)、[Fun-CosyVoice3-0.5B-2512](https://huggingface.co/FunAudioLLM/Fun-CosyVoice3-0.5B-2512)、[FunAudioLLM/CosyVoice LICENSE](https://github.com/FunAudioLLM/CosyVoice/blob/main/LICENSE)

**对本项目影响**：GPT-SoVITS 主线 + AISHELL-3 参考音频零许可风险；IndexTTS-2.5 降为"仅自用备选"；若未来产品化，CosyVoice3 系是双 Apache 的合规兜底。

## 4. 同类成熟项目 —— GitHub API 实测（2026-11-09）

**结论**：
- **huashuo（wixette）**：10 star，**Apache-2.0**（原调研写 MIT，误），最近推送 2026-10-25。Mac+Qwen3-TTS 的小型个人项目；借鉴其"LLM 整句归属 + 按角色配音色"的流程同构。
- **VoxNovel（DrewThomasson）**：378 star，**MIT**（原调研写 GPL-3.0 系，误），最近推送 2025-06-08（约 17 个月未动，实质停更）；借鉴其合成后人工校对 GUI 思路。
- **ebook2audiobook（DrewThomasson）**：20,518 star，**Apache-2.0**（原调研写 GPL/AGPL，误），推送至 2026-11-09（非常活跃）；借鉴其章节抽取+句切+引擎抽象的工程化，是唯一可放心抄代码的。
- **Legado（gedoor）**：47,229 star，**仓库当前无 LICENSE 文件（API license=null）**——原调研"GPL-3.0"只是历史/社区共识，现仓库代码不可合法复用，只能参考思路与正则；最近推送 2026-05-27，原仓库近半年停滞（社区传闻作者 2026 年初出事，未证实），活跃延续在 fork：LegadoTeam/legado（GPL-3.0，1,870 star，推送至 2026-11-09）。
- **它们都没解决的独有点**：本项目做的是"本地 TXT→旁白/对白归属→自托管多角色 TTS→按章音频缓存→安卓后台断点续听"的**全链路中文离线闭环**——huashuo 绑 Mac+云 TTS，VoxNovel 停更且英文向，ebook2audiobook 只做单声文件转换，Legado 系无自托管多音色合成。

**出处**：[huashuo](https://github.com/wixette/huashuo)、[VoxNovel](https://github.com/DrewThomasson/VoxNovel)、[ebook2audiobook](https://github.com/DrewThomasson/ebook2audiobook)、[gedoor/legado](https://github.com/gedoor/legado)、[LegadoTeam/legado](https://github.com/LegadoTeam/legado)（各 repo GitHub API 字段 stargazers_count/pushed_at/license，2026-11-09 实测）

## 对本项目架构的最终确认/修正建议

1. api_v2 主线成立：POST /tts(JSON) + media_type=wav；v2ProPlus 靠改 tts_infer.yaml `custom:` 段（version/t2s_weights_path/vits_weights_path），无 -g 参数。
2. 参考音频硬约束 3-10s，音色库入库时统一预裁剪。
3. 变速交给播放器 setSpeed（不变调），speed_factor 仅作合成期微调备选。
4. cleartext：network_security_config.xml 放行 127.0.0.1 + PC 局网 IP，不全局开明文。
5. 章节音频落盘后再 seek；HTTP 流仅边合成边试听。mp3 输出走 CBR 或直接 wav/ogg 落盘。
6. just_audio 0.10.6 + just_audio_background beta.17 可用；beta 久未更新，卡壳降级 audio_service。
7. 许可修正：huashuo=Apache-2.0、VoxNovel=MIT、ebook2audiobook=Apache-2.0（唯一可抄代码）、Legado 无 LICENSE（只借鉴思路）；IndexTTS-2.5 权重非 Apache，仅自用。
8. 待办修正：AISHELL-3 用 SLR93；"逐一核对 LICENSE"已由本文完成，剩余待办为实机验证 sherpa-onnx RTF 与本机显卡定档。
