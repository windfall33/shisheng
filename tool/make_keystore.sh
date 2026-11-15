#!/usr/bin/env bash
# 生成一个属于你自己的 release 签名，并写好 app/android/key.properties。
# 已经存在 keys/release.jks 时不会覆盖——那个文件丢了，已发布的包就再也升不了级。
set -euo pipefail
cd "$(dirname "$0")/.."

KS="keys/release.jks"
PROPS="app/android/key.properties"

if [ -f "$KS" ]; then
  echo "已存在 $KS，跳过生成。"
  exit 0
fi

if ! command -v keytool >/dev/null 2>&1; then
  echo "找不到 keytool。装一个 JDK 17，或者把 \$JAVA_HOME/bin 加进 PATH。" >&2
  exit 1
fi

mkdir -p keys
PW="${KEYSTORE_PASSWORD:-$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)}"

keytool -genkeypair -v \
  -keystore "$KS" -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias shisheng -storepass "$PW" -keypass "$PW" \
  -dname "CN=Shisheng, OU=Shisheng, O=Shisheng, L=Beijing, ST=Beijing, C=CN"

cat > "$PROPS" <<EOF
storePassword=$PW
keyPassword=$PW
keyAlias=shisheng
storeFile=../../keys/release.jks
EOF

echo
echo "已生成 $KS 与 $PROPS。"
echo "把这两个文件单独备份：丢了它，同一包名的 APK 就再也发不了升级。"
