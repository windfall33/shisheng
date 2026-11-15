# 第三方组件与许可

拾声本身以 GNU General Public License v3.0 发布，全文见 [LICENSE](LICENSE)。
下面这些组件随本仓库或随 APK 一起分发，各自保留原许可。

## 运行时依赖

| 组件 | 版本 | 许可 | 用途 | 位置 |
|---|---|---|---|---|
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | 2.0.1 | Apache-2.0 | 端侧语音合成运行时（FFI） | `app/pubspec.yaml` |
| [Kokoro-82M-v1.1-zh](https://huggingface.co/csukuangfj/kokoro-int8-multi-lang-v1_1) int8 | v1.1 | Apache-2.0 | 中文多音色 TTS 模型（102 个音色，24kHz） | 下载到 `app/assets/tts/`，不入库 |
| [just_audio](https://pub.dev/packages/just_audio) | 0.10.6 | MIT | 播放器 | `app/pubspec.yaml` |
| [audio_service](https://pub.dev/packages/audio_service) | 0.18.19 | MIT | 锁屏/通知栏媒体控制 | `app/pubspec.yaml` |
| [file_picker](https://pub.dev/packages/file_picker) | 13.x | MIT | 选择 TXT 文件 | `app/pubspec.yaml` |
| [archive](https://pub.dev/packages/archive) | 4.x | MIT | 切章/打包工具链 | `app/pubspec.yaml` |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | 2.3.x | BSD-3-Clause | 设置持久化 | `app/pubspec.yaml` |
| [path_provider](https://pub.dev/packages/path_provider) | 2.1.x | BSD-3-Clause | 应用私有目录 | `app/pubspec.yaml` |
| [fast_gbk](https://pub.dev/packages/fast_gbk) | 1.0.0 | BSD-3-Clause | GBK 编码 TXT 解码 | `app/pubspec.yaml` |
| [crypto](https://pub.dev/packages/crypto) / [http](https://pub.dev/packages/http) | 3.0.x / 1.x | BSD-3-Clause | 摘要与网络请求 | `app/pubspec.yaml` |
| [share_plus](https://pub.dev/packages/share_plus) | 13.x | BSD-3-Clause | 导出性能日志走系统分享 | `app/pubspec.yaml` |
| [device_info_plus](https://pub.dev/packages/device_info_plus) | 13.x | BSD-3-Clause | 导出日志附机型信息 | `app/pubspec.yaml` |

## 字体

`app/assets/fonts/ShishengSerif.otf` / `ShishengSans.otf` 是
[Source Han Serif SC](https://github.com/adobe-fonts/source-han-serif) 与
[Source Han Sans SC](https://github.com/adobe-fonts/source-han-sans) 的子集，
按 SIL Open Font License 1.1 发布，已按 OFL 要求改名为 "Shisheng" 以避开保留字体名（Reserved Font Name "Source"）。
许可全文：`app/assets/fonts/OFL.txt`。

## 云端音色（默认关闭）

`app/lib/cloud/edge_tts2/` 是 [Moosphan/flutter_edge_tts](https://github.com/Moosphan/flutter_edge_tts)（MIT）的拷贝，
其中 `src/utils/edge_tts_utils.dart` 是 [rany2/edge-tts](https://github.com/rany2/edge-tts) 中
Sec-MS-GEC 令牌实现（`src/edge_tts/drm.py`）的 Dart 移植，
以 GNU Lesser General Public License v3.0 or later 授权，许可全文见
`app/lib/cloud/edge_tts2/LGPL-3.0.txt`（该目录 `NOTICE` 里有逐条说明）。

这一路走的是微软 Edge 浏览器「大声朗读」的私有接口，**不是**公开 API：
它随时可能被改协议或封禁，也不受任何服务条款保护。因此

- 设置里的「音色来源」默认是**仅本机**，联网调用需要用户自己显式切换；
- 仓库不附带任何密钥，令牌由客户端按公开算法现算；
- 因使用该通道产生的任何问题与本项目无关。

## 内容

本仓库不含任何在版权期内的书籍正文。`lib/boot.dart` 的桌面预览、`test/` 下的测试夹具
用的都是公有领域文本《聊斋志异》（清·蒲松龄）。
