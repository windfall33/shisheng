语音模型不入库（约 177MB，超过 GitHub 单文件限制）。

克隆后先在本目录的上级（也就是 `app/` 或仓库根）运行下载脚本，文件会落到这里：

```bash
bash ../../tool/fetch_model.sh                                   # macOS / Linux
powershell -ExecutionPolicy Bypass -File ..\..\tool\fetch_model.ps1   # Windows
```

需要 9 个文件：`model.int8.onnx`、`voices.bin`、`tokens.txt`、`lexicon-zh.txt`、
`lexicon-us-en.txt`、`lexicon-gb-en.txt`、`date-zh.fst`、`number-zh.fst`、`phone-zh.fst`，
来自 <https://huggingface.co/csukuangfj/kokoro-int8-multi-lang-v1_1>（Apache-2.0）。
脚本会逐个校验 sha256。
