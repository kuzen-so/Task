#!/bin/zsh
set -e

APP_NAME="Task"
EXEC_NAME="Task"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
CERT_NAME="Task Dev"

# 营销版本号：发版时手动改这里
APP_VERSION="1.3.0"
# 构建号：自动生成（git commit 数，工作区有未提交改动时追加时间戳），保证每次构建单调递增
GIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 0)
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    BUILD_NUMBER="${GIT_COUNT}.$(date +%m%d%H%M)"
else
    BUILD_NUMBER="${GIT_COUNT}"
fi
echo "📌 Version: ${APP_VERSION} (${BUILD_NUMBER})"

echo "🎨 Generating icons..."
swift Assets/generate_icons.swift

echo "🔨 Building release binary..."
swift build -c release

echo "📦 Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${EXEC_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.kuzen.task</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCalendarsUsageDescription</key>
    <string>Task 需要访问日历，以便在灵动岛显示日程和重复事件。拒绝时仍可本地使用任务功能。</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Task 需要控制「提醒事项」App，以便将本地任务同步到系统提醒事项。拒绝时仍可本地使用任务功能。</string>
</dict>
</plist>
EOF

echo "🖼 Copying icons..."
cp "Assets/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
cp "Assets/statusbar_icon.png" "${APP_BUNDLE}/Contents/Resources/statusbar_icon.png"

echo "🔏 Code signing app bundle..."
ensure_signing_cert() {
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "${CERT_NAME}"; then
        return 0
    fi
    echo "🔐 未找到「${CERT_NAME}」证书，正在自动创建固定的自签名证书..."
    local tmp; tmp=$(mktemp -d)
    cat > "${tmp}/openssl.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no
[ dn ]
CN = ${CERT_NAME}
[ ext ]
basicConstraints   = critical,CA:false
keyUsage           = critical,digitalSignature
extendedKeyUsage   = critical,codeSigning
CNF
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "${tmp}/key.pem" -out "${tmp}/cert.pem" \
        -config "${tmp}/openssl.cnf" >/dev/null 2>&1
    local p12pass="taskdev"
    openssl pkcs12 -export -legacy -macalg sha1 \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
        -name "${CERT_NAME}" \
        -inkey "${tmp}/key.pem" -in "${tmp}/cert.pem" \
        -out "${tmp}/identity.p12" -passout pass:"${p12pass}" >/dev/null 2>&1

    local kc="${HOME}/Library/Keychains/login.keychain-db"
    security import "${tmp}/identity.p12" -k "${kc}" -P "${p12pass}" -A \
        -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1
    security add-trusted-cert -r trustRoot -p codeSign -k "${kc}" "${tmp}/cert.pem" >/dev/null 2>&1 \
        || echo "   ⚠️ 自动信任失败：请在「钥匙串访问」里把「${CERT_NAME}」设为 代码签名→始终信任"
    rm -rf "${tmp}"

    if security find-identity -v -p codesigning 2>/dev/null | grep -q "${CERT_NAME}"; then
        echo "   ✅ 证书「${CERT_NAME}」已创建（有效期 10 年）"
    else
        echo "   ⚠️ 证书创建后仍不可用，本次将退回 ad-hoc 签名"
    fi
}

ensure_signing_cert
if security find-identity -v -p codesigning 2>/dev/null | grep -q "${CERT_NAME}"; then
    echo "   Using certificate: ${CERT_NAME}"
    # 启用 hardened runtime，SMAppService 开机自启在分发场景下需要有效签名。
    codesign --force --deep --options runtime --sign "${CERT_NAME}" "${APP_BUNDLE}"
else
    echo "   ⚠️ 退回 ad-hoc 签名"
    echo "      注意：ad-hoc 签名下 SMAppService 开机自启功能无法工作"
    codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || true
fi

# 验证签名与 Gatekeeper 评估
echo "🔍 Verifying code signature..."
if codesign --verify --verbose "${APP_BUNDLE}" 2>/dev/null; then
    echo "   ✅ 签名验证通过"
else
    echo "   ⚠️ 签名验证失败：SMAppService 开机自启可能因 Gatekeeper 阻止而无法启动"
    echo "      请运行：xattr -dr com.apple.quarantine '/Applications/${APP_NAME}.app'"
fi

echo "💿 Creating DMG installer..."
DMG_NAME="Task.dmg"
rm -f "${DMG_NAME}"

# 生成 DMG 背景图
cat > /tmp/gen_task_bg.swift <<'BG_EOF'
import AppKit

let width = 640
let height = 440
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSColor(white: 0.96, alpha: 1.0).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

let text = "将 Task 拖动到 Applications 文件夹进行安装" as NSString
let font = NSFont.systemFont(ofSize: 18, weight: .medium)
let textColor = NSColor.darkGray
let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: textColor,
    .paragraphStyle: paragraphStyle
]
let textSize = text.size(withAttributes: attrs)
text.draw(in: NSRect(x: 0, y: height - 60, width: width, height: Int(textSize.height)), withAttributes: attrs)

let hint = "或双击 Task 直接运行" as NSString
let hintFont = NSFont.systemFont(ofSize: 13, weight: .regular)
let hintColor = NSColor.gray
let hintAttrs: [NSAttributedString.Key: Any] = [
    .font: hintFont,
    .foregroundColor: hintColor,
    .paragraphStyle: paragraphStyle
]
let hintSize = hint.size(withAttributes: hintAttrs)
hint.draw(in: NSRect(x: 0, y: 20, width: width, height: Int(hintSize.height)), withAttributes: hintAttrs)

NSGraphicsContext.restoreGraphicsState()
if let data = rep.representation(using: .png, properties: [:]) {
    try! data.write(to: URL(fileURLWithPath: "/tmp/task_dmg_background.png"))
}
BG_EOF
swift /tmp/gen_task_bg.swift

# 创建 DMG 内容目录
TMP_DMG_DIR=$(mktemp -d)
cp -R "${APP_BUNDLE}" "${TMP_DMG_DIR}/"
ln -s /Applications "${TMP_DMG_DIR}/Applications"
mkdir -p "${TMP_DMG_DIR}/.background"
cp /tmp/task_dmg_background.png "${TMP_DMG_DIR}/.background/background.png"

# 创建可读写 DMG，设置布局后再压缩为只读 DMG
DMG_RW="Task_rw_$$.dmg"
rm -f "${DMG_RW}" "${DMG_NAME}"

echo "   Creating read-write DMG..."
hdiutil create \
    -srcfolder "${TMP_DMG_DIR}" \
    -volname "Task Installer" \
    -fs HFS+ \
    -format UDRW \
    -size 20m \
    "${DMG_RW}"

# 尝试用 AppleScript 设置窗口布局（最佳 effort，失败不影响构建）
if command -v osascript >/dev/null 2>&1; then
    echo "   Setting DMG window layout..."
    MOUNT_POINT=$(hdiutil attach "${DMG_RW}" -nobrowse 2>/dev/null | awk -F'\t' '{print $3}' | tail -1)
    if [[ -n "${MOUNT_POINT}" ]]; then
        BG_PATH="${MOUNT_POINT}/.background/background.png"
        osascript >/dev/null 2>&1 <<OSA || true
tell application "Finder"
    try
        set finderWindow to window "Task Installer"
        set current view of finderWindow to icon view
        set bounds of finderWindow to {200, 120, 840, 560}
        tell icon view options of finderWindow
            set icon size to 96
            set text size to 12
            set arrangement to not arranged
            set background picture to POSIX file "${BG_PATH}"
        end tell
        set position of item "Task.app" of finderWindow to {160, 240}
        set position of item "Applications" of finderWindow to {480, 240}
        close finderWindow
    end try
end tell
OSA
        hdiutil detach "${MOUNT_POINT}" >/dev/null 2>&1 || true
        sleep 1
    fi
fi

# 压缩为只读 DMG
echo "   Compressing DMG..."
for i in {1..5}; do
    if hdiutil convert "${DMG_RW}" -format UDZO -o "${DMG_NAME}"; then
        break
    fi
    echo "   Retry $i/5 in 2s..."
    sleep 2
done
rm -f "${DMG_RW}"

rm -rf "${TMP_DMG_DIR}" /tmp/gen_task_bg.swift /tmp/task_dmg_background.png

# 清理不再保留的 PKG 产物
rm -f "Task.pkg"

echo ""
echo "✅ Build complete!"
echo ""
echo "Outputs:"
echo "  ${APP_BUNDLE}"
echo "  ${DMG_NAME}"
echo ""
echo "Install:"
echo "  cp -R '${APP_BUNDLE}' /Applications/"
echo "  # or open ${DMG_NAME} and drag Task.app to Applications"
echo "Run:"
echo "  open '/Applications/${APP_NAME}.app'"
