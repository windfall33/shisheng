# shisheng_reader

拾声的 Flutter 工程。完整说明（功能、构建、许可、已知问题）见仓库根目录的 [README.md](../README.md)。

## 快速开始

```bash
# 1. 下载离线语音模型（约 177MB，不入库）
bash ../tool/fetch_model.sh          # Windows: powershell -ExecutionPolicy Bypass -File ..\tool\fetch_model.ps1

# 2. 依赖与运行
flutter pub get
flutter run --release                # 端侧合成只在真机上跑；Windows 桌面是"预览模式"，合成与播放都是空的

# 3. 打包
flutter build apk --release
```

## 目录

| 路径 | 内容 |
|---|---|
| `lib/textfront.dart` | TXT → 章节 → 句子 → 说话人（旁白/对白） |
| `lib/voices.dart` | 说话人 → 音色分配（同名恒定、男女/年龄/气质匹配） |
| `lib/render.dart` | 渲染队列（NOW > USER > AUTO），逐块合成，写 `index.json` 时间轴 |
| `lib/cleanup.dart` | 存储清理（容量上限 + LRU，两层记账） |
| `lib/perflog.dart` | 性能日志（环形缓冲，JSONL 导出） |
| `lib/engine.dart` | sherpa_onnx / Kokoro 的 isolate 池 |
| `lib/tserver.dart` | 本地 127.0.0.1 虚拟 WAV 流，支持 Range 跳转 |
| `lib/player.dart` | 播放页（当前句高亮、逐句跟读） |
| `lib/screens.dart` | 书架 / 目录 / 设置 |
| `lib/design.dart` | 设计 token（颜色、字号、间距、动效） |
| `DESIGN.md` | 设计说明（为什么这么排、每屏主角、五态、无障碍） |
| `PRODUCT.md` | 产品约束与边界 |
| `test/design_preview_test.dart` | 15 张 golden 截图回归 |
