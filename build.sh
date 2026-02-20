#!/bin/bash

# LegadoSwift GUI 客户端编译脚本
# 支持编译 macOS 应用并正确包含图标资源

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目配置
PROJECT_NAME="LegadoSwift"
APP_NAME="LegadoSwiftApp"
BUILD_DIR=".build"
RELEASE_DIR="release"
BUNDLE_ID="com.legado.swift"

# 打印信息函数
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 清理旧构建
clean_build() {
    print_info "清理旧构建..."
    rm -rf "$BUILD_DIR"
    rm -rf "$RELEASE_DIR"
    print_success "清理完成"
}

# 解析依赖
resolve_dependencies() {
    print_info "解析依赖..."
    swift package resolve
    print_success "依赖解析完成"
}

# 编译应用
build_app() {
    print_info "开始编译 GUI 客户端..."
    
    # 使用 release 模式编译
    swift build -c release --product "$APP_NAME"
    
    print_success "编译完成"
}

# 创建应用包
create_app_bundle() {
    print_info "创建应用包..."
    
    # 创建目录结构
    mkdir -p "$RELEASE_DIR"
    
    APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
    CONTENTS_DIR="$APP_BUNDLE/Contents"
    MACOS_DIR="$CONTENTS_DIR/MacOS"
    RESOURCES_DIR="$CONTENTS_DIR/Resources"
    
    # 清理旧应用包
    rm -rf "$APP_BUNDLE"
    
    # 创建目录
    mkdir -p "$MACOS_DIR"
    mkdir -p "$RESOURCES_DIR"
    
    # 复制可执行文件
    cp "$BUILD_DIR/release/$APP_NAME" "$MACOS_DIR/"
    
    # 复制资源文件
    if [ -d "Assets.xcassets" ]; then
        cp -R "Assets.xcassets" "$RESOURCES_DIR/"
        print_info "已复制图标资源"
    fi
    
    # 创建 Info.plist
    cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>LegadoSwift</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.books</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF
    
    # 生成图标文件 (icns)
    generate_icon
    
    print_success "应用包创建完成: $APP_BUNDLE"
}

# 生成应用图标
generate_icon() {
    print_info "生成应用图标..."
    
    ICONSET_DIR="$RELEASE_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    
    # 复制各种尺寸的图标
    if [ -d "Assets.xcassets/AppIcon.appiconset" ]; then
        ICON_SOURCE="Assets.xcassets/AppIcon.appiconset"
        
        # 复制图标到 iconset
        cp "$ICON_SOURCE/16x16.png" "$ICONSET_DIR/icon_16x16.png" 2>/dev/null || true
        cp "$ICON_SOURCE/16x16@2x.png" "$ICONSET_DIR/icon_16x16@2x.png" 2>/dev/null || true
        cp "$ICON_SOURCE/32x32.png" "$ICONSET_DIR/icon_32x32.png" 2>/dev/null || true
        cp "$ICON_SOURCE/32x32@2x.png" "$ICONSET_DIR/icon_32x32@2x.png" 2>/dev/null || true
        cp "$ICON_SOURCE/128x128.png" "$ICONSET_DIR/icon_128x128.png" 2>/dev/null || true
        cp "$ICON_SOURCE/128x128@2x.png" "$ICONSET_DIR/icon_128x128@2x.png" 2>/dev/null || true
        cp "$ICON_SOURCE/256x256.png" "$ICONSET_DIR/icon_256x256.png" 2>/dev/null || true
        cp "$ICON_SOURCE/256x256@2x.png" "$ICONSET_DIR/icon_256x256@2x.png" 2>/dev/null || true
        cp "$ICON_SOURCE/512x512.png" "$ICONSET_DIR/icon_512x512.png" 2>/dev/null || true
        cp "$ICON_SOURCE/512x512@2x.png" "$ICONSET_DIR/icon_512x512@2x.png" 2>/dev/null || true
        
        # 生成 icns 文件
        if command -v iconutil &> /dev/null; then
            iconutil -c icns "$ICONSET_DIR" -o "$RELEASE_DIR/$APP_NAME.app/Contents/Resources/AppIcon.icns"
            print_success "图标生成完成"
        else
            print_warning "iconutil 不可用，跳过图标生成"
        fi
        
        # 清理临时文件
        rm -rf "$ICONSET_DIR"
    else
        print_warning "未找到图标资源"
    fi
}

# 签名应用 (可选)
sign_app() {
    print_info "签名应用..."
    
    # 使用 ad-hoc 签名
    codesign --force --deep --sign - "$RELEASE_DIR/$APP_NAME.app"
    
    print_success "签名完成"
}

# 验证应用
verify_app() {
    print_info "验证应用..."
    
    # 检查应用结构
    if [ -d "$RELEASE_DIR/$APP_NAME.app" ]; then
        print_success "应用包结构正确"
        
        # 列出应用内容
        echo ""
        echo "应用包内容:"
        find "$RELEASE_DIR/$APP_NAME.app" -type f | head -20
        echo ""
    else
        print_error "应用包创建失败"
        exit 1
    fi
}

# 打开应用
open_app() {
    print_info "启动应用..."
    open "$RELEASE_DIR/$APP_NAME.app"
}

# 显示帮助
show_help() {
    echo "LegadoSwift GUI 客户端编译脚本"
    echo ""
    echo "用法: ./build.sh [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help      显示帮助信息"
    echo "  -c, --clean     仅清理构建"
    echo "  -b, --build     编译应用 (默认)"
    echo "  -r, --run       编译并运行应用"
    echo "  --no-sign       跳过签名步骤"
    echo ""
    echo "示例:"
    echo "  ./build.sh              # 编译应用"
    echo "  ./build.sh -c           # 清理构建"
    echo "  ./build.sh -r           # 编译并运行"
}

# 主函数
main() {
    echo "========================================"
    echo "  LegadoSwift GUI 客户端编译脚本"
    echo "========================================"
    echo ""
    
    # 检查是否在项目根目录
    if [ ! -f "Package.swift" ]; then
        print_error "请在项目根目录运行此脚本"
        exit 1
    fi
    
    # 解析参数
    DO_CLEAN=false
    DO_BUILD=true
    DO_RUN=false
    DO_SIGN=true
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--clean)
                DO_CLEAN=true
                DO_BUILD=false
                shift
                ;;
            -b|--build)
                DO_BUILD=true
                shift
                ;;
            -r|--run)
                DO_BUILD=true
                DO_RUN=true
                shift
                ;;
            --no-sign)
                DO_SIGN=false
                shift
                ;;
            *)
                print_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 执行操作
    if [ "$DO_CLEAN" = true ]; then
        clean_build
    fi
    
    if [ "$DO_BUILD" = true ]; then
        clean_build
        resolve_dependencies
        build_app
        create_app_bundle
        
        if [ "$DO_SIGN" = true ]; then
            sign_app
        fi
        
        verify_app
        
        echo ""
        echo "========================================"
        print_success "构建完成!"
        echo "应用位置: $(pwd)/$RELEASE_DIR/$APP_NAME.app"
        echo "========================================"
    fi
    
    if [ "$DO_RUN" = true ]; then
        echo ""
        open_app
    fi
}

# 运行主函数
main "$@"
