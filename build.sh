#!/bin/bash
# WristNav 编译脚本
# 在有 macOS + Xcode 的机器上执行，产出可用 TrollStore 安装的 IPA
# 用法: chmod +x build.sh && ./build.sh

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
IPA_NAME="WristNav.ipa"
BUNDLE_ID="com.wristnav.app"

echo "==> 清理旧构建"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/Payload/WristNav.app"

echo "==> 检查依赖工具"
command -v swiftc >/dev/null || { echo "错误: 需要 Xcode 命令行工具 (swiftc)"; exit 1; }
if ! command -v ldid >/dev/null; then
    echo "提示: 未找到 ldid，尝试通过 Homebrew 安装..."
    brew install ldid 2>/dev/null || { echo "错误: 请手动安装 ldid (brew install ldid)"; exit 1; }
fi

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
SWIFT_LIB=$(dirname "$(dirname "$(xcrun --find swiftc)")")/lib/swift/iphoneos

echo "==> 编译 Swift 源码 (arm64, iOS 16.0+)"
# SwiftUI 使用 @main 入口，必须用 -parse-as-library 避免入口点冲突
swiftc -O \
    -parse-as-library \
    -target arm64-apple-ios16.0 \
    -sdk "$SDK_PATH" \
    -emit-executable \
    -o "$BUILD_DIR/Payload/WristNav.app/WristNav" \
    "$PROJECT_DIR"/Sources/*.swift

echo "==> 复制资源文件"
cp "$PROJECT_DIR/Info.plist" "$BUILD_DIR/Payload/WristNav.app/Info.plist"

echo "==> 用 ldid 伪签名 (TrollStore 依赖 CoreTrust 漏洞，无需真实开发者证书)"
ldid -S"$PROJECT_DIR/entitlements.plist" "$BUILD_DIR/Payload/WristNav.app/WristNav"

echo "==> 打包 IPA"
cd "$BUILD_DIR"
zip -q -r "$IPA_NAME" Payload

echo ""
echo "============================================"
echo "构建完成: $BUILD_DIR/$IPA_NAME"
echo "============================================"
echo "安装方式:"
echo "  1. 把 IPA 传到 iPhone（AirDrop / 文件 App / 本地服务器）"
echo "  2. 在 TrollStore 中打开 IPA → Install"
echo "  3. 首次启动后按提示开启定位(始终)与通知权限"
echo ""
