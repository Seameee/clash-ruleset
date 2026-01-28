#!/bin/bash

set -e

# 设置工作目录
WORKDIR=$(pwd)
TEMP_DIR="$WORKDIR/temp"
MIHOMO_BIN="$TEMP_DIR/mihomo"
OUTPUT_ROOT="$WORKDIR/.output"
SRC_ROOT="$TEMP_DIR/ruleset.skk.moe/Clash"
TARGET_FOLDERS=("domainset")

# 创建临时目录
mkdir -p "$TEMP_DIR"
# 创建输出目录
mkdir -p "$OUTPUT_ROOT"

# 1. 下载 mihomo
echo "Downloading mihomo..."
# 获取最新版本 release tag
LATEST_TAG=$(curl -s "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')
if [ -z "$LATEST_TAG" ]; then
    echo "Failed to get latest mihomo version, fallback to v1.19.19"
    LATEST_TAG="v1.19.19"
fi

echo "Latest mihomo version: $LATEST_TAG"

# 构建下载链接 (Linux amd64)
# 格式通常是: mihomo-linux-amd64-{version}.gz
DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/$LATEST_TAG/mihomo-linux-amd64-$LATEST_TAG.gz"

echo "Downloading from $DOWNLOAD_URL"
curl -L -o "$TEMP_DIR/mihomo.gz" "$DOWNLOAD_URL"
gzip -d "$TEMP_DIR/mihomo.gz"
chmod +x "$MIHOMO_BIN"

echo "Mihomo installed at $MIHOMO_BIN"
$MIHOMO_BIN -v

# 2. 克隆源仓库
echo "Cloning source repository..."
git clone --depth 1 https://github.com/SukkaLab/ruleset.skk.moe.git "$TEMP_DIR/ruleset.skk.moe"

if [ ! -d "$SRC_ROOT" ]; then
    echo "Directory $SRC_ROOT does not exist!"
    exit 1
fi

# 复制原始文件到输出目录
cp -r "$SRC_ROOT/." "$OUTPUT_ROOT"

# 3. 转换规则
echo "Converting rules..."

for folder in "${TARGET_FOLDERS[@]}"; do
    src_dir="$SRC_ROOT/$folder"
    out_dir="$OUTPUT_ROOT/$folder"

    if [ ! -d "$src_dir" ]; then
        echo "Source directory $src_dir does not exist, skipping..."
        continue
    fi

    # 确定规则类型
    RULE_TYPE="domain"

    echo "Processing directory: $folder (Type: $RULE_TYPE)"

    # 转换规则文件
    shopt -s nullglob
    for file in "$src_dir"/*.txt; do
        filename=$(basename "$file")
        name="${filename%.*}"

        clean_file="${file}.clean"

        grep -v "ruleset.skk.moe" "$file" | grep -v "^\s*#" | sed '/^\s*$/d' | sed 's/[[:space:]]*$//' >"$clean_file"

        if [ -s "$clean_file" ]; then
            echo "Converting $filename to $name.mrs"

            # mihomo convert-ruleset <behavior> <format> <source file> <target file>
            if "$MIHOMO_BIN" convert-ruleset "$RULE_TYPE" "text" "$clean_file" "$out_dir/$name.mrs"; then
                echo "Successfully converted $filename"
            else
                echo "Failed to convert $filename"
            fi
        else
            echo "Cleaned file $clean_file is empty, skipping conversion."
        fi
    done
    shopt -u nullglob
done

# 清理
rm -rf "$TEMP_DIR"

echo "Done. Rulesets are in $OUTPUT_ROOT"
