#!/bin/bash
# 剪贴板助手 一键安装（Mac 通用，arm64/Intel 都行）
# 用法：双击本文件；如果提示"无法验证开发者"，右键 → 打开 → 再点"打开"
set -e
cd "$(dirname "$0")"

echo "=============================="
echo "  剪贴板助手 v3.3 一键安装"
echo "=============================="

# 检查编译器（没有会自动触发系统安装命令行工具的引导）
if ! command -v swiftc >/dev/null 2>&1; then
  echo "第一次需要装 Apple 命令行工具，弹窗后点『安装』，装完再双击本文件一次"
  xcode-select --install 2>/dev/null || true
  read -p "装好后按回车继续..."
fi

APP="$HOME/Applications/剪贴板助手.app"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>剪贴板助手</string>
    <key>CFBundleDisplayName</key><string>剪贴板助手</string>
    <key>CFBundleIdentifier</key><string>com.yingying.clipboard-helper</string>
    <key>CFBundleExecutable</key><string>剪贴板助手</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>3.3</string>
    <key>CFBundleVersion</key><string>33</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "[1/3] 正在编译..."
swiftc -O main.swift -o "$APP/Contents/MacOS/剪贴板助手" -framework AppKit -framework ServiceManagement -framework Carbon
# 用固定本地证书签名：权限系统认签名不辘认名字，签名固定后授权一次永久有效
if security find-identity -p codesigning | grep -q "YingYing Local Dev"; then
  codesign --force --sign "YingYing Local Dev" "$APP"
fi

echo "[2/3] 启动..."
open "$APP"
sleep 1

echo "[3/3] 完成！"
echo ""
echo "接下来还有两处系统设置（每台新电脑都要做一次）："
echo "① 菜单栏找不到 📋 → 系统设置 → 菜单栏 → 允许在菜单栏中显示 → 打开『剪贴板助手』"
echo "② 要用『点卡片自动粘贴』→ 系统设置 → 隐私与安全性 → 辅助功能 → 添加并打开『剪贴板助手』"
echo ""
echo "快捷键：⌥V 呼出/收起；点卡片=复制并自动粘贴"
read -p "按回车关闭窗口..."
