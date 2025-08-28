#!/bin/bash

# LuCI Time Control Build Script
# 用于构建 luci-app-timecontrol IPK 包

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
PKG_NAME="luci-app-timecontrol"
PKG_VERSION="1.2.0"
PKG_ARCH="all"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

warn() {
    echo "[WARNING] $1"
}

error() {
    echo "[ERROR] $1"
    exit 1
}

# 检查依赖
check_dependencies() {
    log "检查构建依赖..."
    
    local deps=("tar" "gzip")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "$dep 未安装，请手动安装"
        fi
    done
    
    log "依赖检查完成"
}

# 创建构建目录
create_build_dir() {
    log "创建构建目录..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
}

# 构建 IPK 包
build_ipk() {
    local pkg_dir="$1"
    log "构建 IPK 包..."
    
    cd "$pkg_dir" || error "无法进入包目录: $pkg_dir"
    
    # 创建 control.tar.gz
    tar -czf control.tar.gz -C DEBIAN .
    
    # 创建 data.tar.gz
    tar -czf data.tar.gz --exclude=DEBIAN .
    
    # 创建 debian-binary
    echo "2.0" > debian-binary
    
    # 创建最终的 IPK 文件
    local ipk_name="${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.ipk"
    tar -czf "../$ipk_name" debian-binary control.tar.gz data.tar.gz
    
    cd "$SCRIPT_DIR"
    
    log "IPK 包构建完成: build/$ipk_name"
}

# 验证包内容
verify_package() {
    local ipk_file="$1"
    log "验证包内容..."
    
    if [ ! -f "$ipk_file" ]; then
        error "IPK 文件不存在: $ipk_file"
    fi
    
    local size=$(du -h "$ipk_file" | cut -f1)
    log "包大小: $size"
    
    # 显示包内容
    log "包内容预览:"
    tar -tzf "$ipk_file" | head -20
    
    if [ "$(tar -tzf "$ipk_file" | wc -l)" -gt 20 ]; then
        echo "... (总共 $(tar -tzf "$ipk_file" | wc -l) 个文件)"
    fi
}

# 主函数
main() {
    log "开始构建 $PKG_NAME v$PKG_VERSION"
    
    check_dependencies
    create_build_dir
    
    # 创建包目录结构
    log "创建包目录结构..."
    local pkg_dir="$BUILD_DIR/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}"
    
    # 创建 DEBIAN 目录和控制文件
    mkdir -p "$pkg_dir/DEBIAN"
    
    # 创建 control 文件
    cat > "$pkg_dir/DEBIAN/control" << EOF
Package: $PKG_NAME
Version: $PKG_VERSION
Architecture: $PKG_ARCH
Maintainer: OpenWrt Community
Section: luci
Priority: optional
Depends: nftables, kmod-nft-core, luci-base
Description: LuCI support for Time Control
 Time-based network access control for devices.
 Ideal for parental control to manage children's screen time.
EOF

    # 创建 postinst 脚本
    cat > "$pkg_dir/DEBIAN/postinst" << 'EOF'
#!/bin/sh
set -e
if [ -f /etc/init.d/timecontrol ]; then
    /etc/init.d/timecontrol enable
    /etc/init.d/timecontrol start
fi
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
if pidof uhttpd >/dev/null 2>&1; then
    /etc/init.d/uhttpd restart
fi
exit 0
EOF

    # 创建 prerm 脚本
    cat > "$pkg_dir/DEBIAN/prerm" << 'EOF'
#!/bin/sh
set -e
if [ -f /etc/init.d/timecontrol ]; then
    /etc/init.d/timecontrol stop
    /etc/init.d/timecontrol disable
fi
exit 0
EOF

    chmod 755 "$pkg_dir/DEBIAN/postinst" "$pkg_dir/DEBIAN/prerm"
    
    # 复制文件到包目录
    cp -r "$SCRIPT_DIR/root"/* "$pkg_dir/"
    
    # 设置正确的权限
    find "$pkg_dir" -type d -exec chmod 755 {} \;
    find "$pkg_dir" -type f -name "*.lua" -exec chmod 644 {} \;
    find "$pkg_dir" -type f -name "*.htm" -exec chmod 644 {} \;
    find "$pkg_dir" -type f -name "*.json" -exec chmod 644 {} \;
    find "$pkg_dir" -type f -path "*/init.d/*" -exec chmod 755 {} \;
    
    build_ipk "$pkg_dir"
    
    local ipk_file="$BUILD_DIR/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.ipk"
    verify_package "$ipk_file"
    
    log "构建完成!"
    echo
    echo "安装方法:"
    echo "1. 将 IPK 文件上传到 OpenWrt 路由器"
    echo "2. 运行: opkg install ${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.ipk"
    echo
    echo "或者使用 SCP 直接安装:"
    echo "scp $ipk_file root@<router_ip>:/tmp/"
    echo "ssh root@<router_ip> 'opkg install /tmp/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.ipk'"
}

# 运行主函数
main "$@"