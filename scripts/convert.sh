#!/bin/bash

set -e

# 设置工作目录
WORKDIR=$(pwd)
TEMP_DIR="$WORKDIR/temp"
MIHOMO_BIN="$TEMP_DIR/mihomo"
OUTPUT_ROOT="$WORKDIR/.output"
SRC_ROOT="$TEMP_DIR/ruleset.skk.moe/Clash"

# 定义需要转换的文件夹及其对应的规则类型
# domainset -> domain, ip -> ipcidr
TARGET_FOLDERS=("domainset" "ip")
RULE_TYPES=("domain" "ipcidr")

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

for i in "${!TARGET_FOLDERS[@]}"; do
    folder="${TARGET_FOLDERS[$i]}"
    RULE_TYPE="${RULE_TYPES[$i]}"
    src_dir="$SRC_ROOT/$folder"
    out_dir="$OUTPUT_ROOT/$folder"

    if [ ! -d "$src_dir" ]; then
        echo "Source directory $src_dir does not exist, skipping..."
        continue
    fi

    echo "Processing directory: $folder (Type: $RULE_TYPE)"

    # 转换规则文件
    shopt -s nullglob
    for file in "$src_dir"/*.txt; do
        filename=$(basename "$file")
        name="${filename%.*}"

        clean_file="${file}.clean"

        # 基础清理：去除注释、空行、尾部空格，以及包含 ruleset.skk.moe 的标记行
        cleaned=$(grep -v "ruleset.skk.moe" "$file" | grep -v "^\s*#" | sed '/^\s*$/d' | sed 's/[[:space:]]*$//')

        # 根据规则类型进行额外处理
        if [ "$RULE_TYPE" = "ipcidr" ]; then
            # 对于 IP 规则，需要去除 IP-CIDR, / IP-CIDR6, / IP-ASN, 前缀和 ,no-resolve 等后缀
            # 只保留纯 IP/CIDR 段，同时过滤掉纯数字的 ASN 行和非 CIDR 格式的行
            cleaned=$(echo "$cleaned" | sed 's/^IP-\(CIDR6\?\|ASN\)\s*,\s*//g' | sed 's/\s*,no-resolve$//g' | grep -v '^[0-9]\+$' || true)
            # 只保留有效的 CIDR 格式行（IPv4/IPv6）
            cleaned=$(echo "$cleaned" | grep -E '^[0-9a-fA-F:.]+/[0-9]+$' || true)
        elif [ "$RULE_TYPE" = "domain" ]; then
            # 过滤掉不含点的非域名行（如分隔符 ##################），域名规则一定包含点
            cleaned=$(echo "$cleaned" | grep '\.' || true)
        fi

        # 为 domainset/download.txt 追加额外规则
        if [ "$filename" = "download.txt" ] && [ "$RULE_TYPE" = "domain" ]; then
            echo "Appending extra rules to $filename"
            cleaned=$(echo "$cleaned" && echo "+.download.amd.com" && echo "+.drivers.amd.com" && echo "+.now61.com" && echo "+.now61.cn" && echo "api-proxy.de" && echo "+.infini-cloud.net")
        fi

        # 将清理后的内容写回输出的 .txt（对 download.txt 会包含追加的规则）
        printf '%s\n' "$cleaned" > "$out_dir/$filename"

        # 只有非空才生成 .mrs；echo 空变量会产生换行符导致 [ -s ] 误判，所以直接检查变量
        if [ -n "$cleaned" ]; then
            echo "Converting $filename to $name.mrs"

            # mihomo convert-ruleset <behavior> <format> <source file> <target file>
            if "$MIHOMO_BIN" convert-ruleset "$RULE_TYPE" "text" "$out_dir/$filename" "$out_dir/$name.mrs"; then
                echo "Successfully converted $filename"
            else
                echo "Failed to convert $filename"
            fi
        else
            echo "Cleaned file $filename is empty, skipping conversion."
        fi
    done
    shopt -u nullglob
done

# 清理
rm -rf "$TEMP_DIR"

echo "Done. Rulesets are in $OUTPUT_ROOT"
