#!/usr/bin/env bash
# NJ Stream ERP — Release APK Build Script
# 使用前：
#   1. 建立 keystore（見下方 keytool 指令）
#   2. 填寫 android/key.properties
#   3. 設定 API_BASE_URL
#
# Keystore 初次建立：
#   mkdir -p ../../keystores
#   keytool -genkey -v \
#     -keystore ../../keystores/nj-stream-erp.jks \
#     -storetype JKS \
#     -keyalg RSA -keysize 2048 -validity 10000 \
#     -alias nj-stream-erp
#
# 用法：
#   API_BASE_URL=https://your-tunnel.trycloudflare.com bash scripts/build-release-apk.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(dirname "$SCRIPT_DIR")"
DEBUG_INFO_DIR="$FRONTEND_DIR/build/debug-info"

# 確認 key.properties 存在
KEY_PROPS="$FRONTEND_DIR/android/key.properties"
if [[ ! -f "$KEY_PROPS" ]]; then
  echo "ERROR: android/key.properties not found."
  echo "       cp android/key.properties.example android/key.properties 並填入實際值"
  exit 1
fi

# 確認 API_BASE_URL
: "${API_BASE_URL:?請設定 API_BASE_URL 環境變數，例如：export API_BASE_URL=https://example.com}"

mkdir -p "$DEBUG_INFO_DIR"

cd "$FRONTEND_DIR"

flutter build apk \
  --release \
  --obfuscate \
  --split-debug-info="$DEBUG_INFO_DIR" \
  --dart-define=API_BASE_URL="$API_BASE_URL"

APK_PATH="$FRONTEND_DIR/build/app/outputs/flutter-apk/app-release.apk"
echo ""
echo "Build complete: $APK_PATH"
echo "Debug symbols : $DEBUG_INFO_DIR  (保存供符號化 crash 使用，勿公開)"