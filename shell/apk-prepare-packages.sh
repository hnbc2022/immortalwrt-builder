#!/bin/sh

BASE_DIR="extra-packages"
TEMP_DIR="$BASE_DIR/temp-unpack"
TARGET_DIR="packages"

# 清理旧的目录并初始化
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"
mkdir -p "$TARGET_DIR"

# 解压 .run 文件
for run_file in "$BASE_DIR"/*.run; do
    [ -e "$run_file" ] || continue
    echo "🧩 解压 $run_file -> $TEMP_DIR"
    sh "$run_file" --target "$TEMP_DIR" --noexec
done

# 1. 收集 run 解压出的 .apk 文件
find "$TEMP_DIR" -type f -name "*.apk" -exec cp -v {} "$TARGET_DIR"/ \;

# 2. 收集 extra-packages 下直接存放或一级子目录下的 .apk 文件
find "$BASE_DIR" -mindepth 1 -maxdepth 2 -type f -name "*.apk" ! -path "$TEMP_DIR/*" \
  -exec echo "👉 发现离线 APK 包:" {} \; \
  -exec cp -v {} "$TARGET_DIR"/ \;

rm -rf "$TEMP_DIR"
echo "✅ 所有第三方离线 .apk 文件已整理至 $TARGET_DIR/"
