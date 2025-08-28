include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-timecontrol
PKG_VERSION:=1.2.0
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0
PKG_MAINTAINER:=OpenWrt Community

LUCI_TITLE:=LuCI support for Time Control
LUCI_DESCRIPTION:=Time-based network access control for devices (ideal for parental control)
LUCI_DEPENDS:=+nftables +kmod-nft-core +luci-base
LUCI_PKGARCH:=all

PKG_BUILD_PARALLEL:=1

include $(TOPDIR)/feeds/luci/luci.mk

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/timecontrol $(1)/etc/init.d/timecontrol
	
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/timecontrol $(1)/etc/config/timecontrol
	
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/controller/timecontrol.lua $(1)/usr/lib/lua/luci/controller/timecontrol.lua
	
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/timecontrol
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/view/timecontrol/main.htm $(1)/usr/lib/lua/luci/view/timecontrol/main.htm
	
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-timecontrol.json $(1)/usr/share/luci/menu.d/luci-app-timecontrol.json
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	# Enable and start timecontrol service on first install
	/etc/init.d/timecontrol enable
	/etc/init.d/timecontrol start
	
	# Clear LuCI cache
	rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
	
	# Restart LuCI if running
	/etc/init.d/uhttpd restart 2>/dev/null
}
exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	# Stop and disable timecontrol service
	/etc/init.d/timecontrol stop
	/etc/init.d/timecontrol disable
}
exit 0
endef

# call BuildPackage - OpenWrt buildroot signature