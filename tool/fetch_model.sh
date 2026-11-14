#!/usr/bin/env bash
# 下载拾声依赖的离线语音模型（Kokoro-82M-v1.1-zh int8）到 app/assets/tts/。
#
# 模型体积约 177MB，超过 GitHub 单文件限制，所以不进仓库。
# 默认走 huggingface.co；国内网络可设 HF_ENDPOINT=https://hf-mirror.com 走镜像。
#
#   bash tool/fetch_model.sh
#   HF_ENDPOINT=https://hf-mirror.com bash tool/fetch_model.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/app/assets/tts"
HF="${HF_ENDPOINT:-https://huggingface.co}"
REPO="csukuangfj/kokoro-int8-multi-lang-v1_1"

mkdir -p "$DEST"

# 文件名  字节数  sha256
FILES='
model.int8.onnx 114203914 05d793700b0b507f760c183c0e39bdd6a97b43d32fdc7bf7b54a5179f1b11222
voices.bin 53790720 e64a5a581d8c2a350d848f51c3121657cd83aa07ed6109172177345874a7244c
tokens.txt 1111 931ab2df2400cd65d580a22402024c2347ced8ae9ea300e545144b1aacc48e14
lexicon-zh.txt 2120131 fea060803db3e59193987f1a3436f56917bda09f3b3595b6588e46ae60cebf93
lexicon-us-en.txt 5956885 7daaab53a181be9885b853a8582bf1838186317e5dadacbcef9c426d6fa0da14
lexicon-gb-en.txt 6366635 c4cbb37316f62210dff52718a7afcaae24f50c032cc75ab47ae67b831d1049e7
date-zh.fst 59154 eb8aa079ae3cb81d8f4404992f39d61a0cb990947512b5b8d1e54d1f6980e718
number-zh.fst 64482 743f402181fcfebf76cc2f0546b71fa26476e626fbe4e460fb7b4c3a7a8bd5bd
phone-zh.fst 88630 1ac2b6fa56b1442320c4de7db08353bab8963a2b57f365eebcdd3a2d3562f8d7
'

sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

echo "$FILES" | while read -r name size sum; do
  [ -z "$name" ] && continue
  out="$DEST/$name"
  if [ -f "$out" ] && [ "$(sha "$out")" = "$sum" ]; then
    echo "跳过 $name（已存在且校验通过）"
    continue
  fi
  url="$HF/$REPO/resolve/main/$name"
  echo "下载 $name（$((size / 1024 / 1024))MB）…"
  curl -fL --retry 3 --progress-bar -o "$out.part" "$url"
  got="$(sha "$out.part")"
  if [ "$got" != "$sum" ]; then
    rm -f "$out.part"
    echo "校验失败：$name 期望 $sum 实际 $got" >&2
    exit 1
  fi
  mv "$out.part" "$out"
done

echo "完成，模型在 $DEST"
