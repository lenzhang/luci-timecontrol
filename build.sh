#!/bin/bash

# LuCI Time Control 打包脚本

PKG_NAME="luci-app-timecontrol"
VERSION="1.3.0"
ARCH="all"

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Building $PKG_NAME version $VERSION..."

# 创建临时目录
TEMP_DIR=$(mktemp -d)
PKG_DIR="$TEMP_DIR/$PKG_NAME"
mkdir -p "$PKG_DIR"

# 创建CONTROL目录
mkdir -p "$PKG_DIR/CONTROL"

# 创建control文件
cat > "$PKG_DIR/CONTROL/control" << EOC
Package: $PKG_NAME
Version: $VERSION
Depends: libc, nftables, luci-compat
Architecture: $ARCH
Section: luci
Priority: optional
Description: LuCI support for Time-based network access control
 Allows you to control network access for devices based on time schedules.
 Features MAC vendor detection and multiple time rules per device.
EOC

# 创建postinst脚本
cat > "$PKG_DIR/CONTROL/postinst" << 'EOP'
#!/bin/sh
# 启用服务开机自启动
/etc/init.d/timecontrol enable 2>/dev/null

# 创建默认配置文件（如果不存在）
[ ! -f /etc/config/timecontrol ] && touch /etc/config/timecontrol

# 启动服务
/etc/init.d/timecontrol start 2>/dev/null

# 清理LuCI缓存
rm -rf /tmp/luci-* 2>/dev/null

exit 0
EOP
chmod 755 "$PKG_DIR/CONTROL/postinst"

# 创建prerm脚本
cat > "$PKG_DIR/CONTROL/prerm" << 'EOR'
#!/bin/sh
# 停止服务
/etc/init.d/timecontrol stop 2>/dev/null

# 禁用开机自启动  
/etc/init.d/timecontrol disable 2>/dev/null

exit 0
EOR
chmod 755 "$PKG_DIR/CONTROL/prerm"

# 复制文件到包目录
echo "Copying files..."

# init.d脚本
mkdir -p "$PKG_DIR/etc/init.d"
cp root/etc/init.d/timecontrol "$PKG_DIR/etc/init.d/"
chmod 755 "$PKG_DIR/etc/init.d/timecontrol"

# 默认配置
mkdir -p "$PKG_DIR/etc/config"
touch "$PKG_DIR/etc/config/timecontrol"

# LuCI控制器
mkdir -p "$PKG_DIR/usr/lib/lua/luci/controller"
cp root/usr/lib/lua/luci/controller/timecontrol.lua "$PKG_DIR/usr/lib/lua/luci/controller/"

# LuCI视图
mkdir -p "$PKG_DIR/usr/lib/lua/luci/view/timecontrol"
cp root/usr/lib/lua/luci/view/timecontrol/main.htm "$PKG_DIR/usr/lib/lua/luci/view/timecontrol/"

# ACL权限
mkdir -p "$PKG_DIR/usr/share/rpcd/acl.d"
cat > "$PKG_DIR/usr/share/rpcd/acl.d/luci-app-timecontrol.json" << 'EOA'
{
    "luci-app-timecontrol": {
        "description": "Grant access to Time Control",
        "read": {
            "uci": [ "timecontrol" ]
        },
        "write": {
            "uci": [ "timecontrol" ]
        }
    }
}
EOA

# 菜单配置（LuCI2）
mkdir -p "$PKG_DIR/usr/share/luci/menu.d"
cp root/usr/share/luci/menu.d/luci-app-timecontrol.json "$PKG_DIR/usr/share/luci/menu.d/" 2>/dev/null || true

# 构建IPK包
echo "Building IPK package..."
cd "$TEMP_DIR"

# 使用GNU tar确保兼容性
tar -czf "$PKG_NAME/data.tar.gz" -C "$PKG_NAME" --exclude=CONTROL --numeric-owner .
tar -czf "$PKG_NAME/control.tar.gz" -C "$PKG_NAME/CONTROL" --numeric-owner .
echo "2.0" > "$PKG_NAME/debian-binary"

# 创建IPK
cd "$TEMP_DIR"
ar -r "$PKG_NAME-${VERSION}_${ARCH}.ipk" "$PKG_NAME/debian-binary" "$PKG_NAME/control.tar.gz" "$PKG_NAME/data.tar.gz" 2>/dev/null

# 移动到脚本目录
mv "$PKG_NAME-${VERSION}_${ARCH}.ipk" "$SCRIPT_DIR/"

# 清理
cd "$SCRIPT_DIR"
rm -rf "$TEMP_DIR"

echo "Package built: $PKG_NAME-${VERSION}_${ARCH}.ipk"
ls -lh "$PKG_NAME-${VERSION}_${ARCH}.ipk"
