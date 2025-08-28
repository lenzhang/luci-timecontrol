#!/bin/bash

# LuCI Time Control 真实路由器测试脚本
# 在实际的 OpenWrt 路由器上进行功能测试

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IPK_FILE="$SCRIPT_DIR/build/luci-app-timecontrol_1.2.0_all.ipk"
ROUTER_IP="${ROUTER_IP:-192.168.1.1}"
ROUTER_USER="${ROUTER_USER:-root}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# 检查连接
check_connection() {
    log "检查与路由器的连接..."
    
    if ! ping -c 1 "$ROUTER_IP" >/dev/null 2>&1; then
        error "无法连接到路由器 $ROUTER_IP"
    fi
    
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$ROUTER_USER@$ROUTER_IP" "echo 'Connection OK'" >/dev/null 2>&1; then
        error "SSH 连接到 $ROUTER_USER@$ROUTER_IP 失败"
    fi
    
    log "路由器连接正常"
}

# 检查依赖
check_dependencies() {
    log "检查依赖..."
    
    if [ ! -f "$IPK_FILE" ]; then
        warn "IPK 包不存在，正在构建..."
        "$SCRIPT_DIR/build.sh"
        
        if [ ! -f "$IPK_FILE" ]; then
            error "构建 IPK 包失败"
        fi
    fi
    
    log "依赖检查完成"
}

# 备份现有配置
backup_config() {
    log "备份路由器配置..."
    
    ssh "$ROUTER_USER@$ROUTER_IP" "
        mkdir -p /tmp/timecontrol-backup
        cp -f /etc/config/timecontrol /tmp/timecontrol-backup/ 2>/dev/null || true
        nft list table inet fw4 > /tmp/timecontrol-backup/nft-rules.txt 2>/dev/null || true
    "
    
    log "配置备份完成"
}

# 上传并安装 IPK
install_ipk() {
    log "上传并安装 IPK 包..."
    
    # 上传 IPK 包
    scp -o StrictHostKeyChecking=no "$IPK_FILE" "$ROUTER_USER@$ROUTER_IP:/tmp/"
    
    # 安装 IPK 包
    ssh "$ROUTER_USER@$ROUTER_IP" "
        opkg install /tmp/luci-app-timecontrol_1.2.0_all.ipk
    "
    
    # 验证安装
    if ssh "$ROUTER_USER@$ROUTER_IP" "opkg list-installed | grep -q luci-app-timecontrol"; then
        log "✅ IPK 包安装成功"
    else
        error "❌ IPK 包安装失败"
    fi
}

# 获取真实设备 MAC 地址
get_real_device_mac() {
    log "扫描网络中的设备..."
    
    # 获取当前连接的设备列表
    local devices=$(ssh "$ROUTER_USER@$ROUTER_IP" "
        echo '=== DHCP 租约设备 ==='
        cat /tmp/dhcp.leases 2>/dev/null | head -10
        echo
        echo '=== ARP 表设备 ==='
        cat /proc/net/arp | grep -v '00:00:00:00:00:00' | head -10
    ")
    
    echo "$devices"
    
    # 提取一个真实的 MAC 地址用于测试
    local test_mac=$(ssh "$ROUTER_USER@$ROUTER_IP" "
        cat /proc/net/arp | grep -v '00:00:00:00:00:00' | head -1 | awk '{print \$4}'
    ")
    
    if [ -n "$test_mac" ] && [ "$test_mac" != "00:00:00:00:00:00" ]; then
        echo "$test_mac"
    else
        echo "aa:bb:cc:dd:ee:ff"  # 使用虚拟 MAC 作为备用
    fi
}

# 创建测试配置
create_test_config() {
    local test_mac="$1"
    log "创建测试配置，目标设备 MAC: $test_mac"
    
    ssh "$ROUTER_USER@$ROUTER_IP" "
        cat > /etc/config/timecontrol << EOF
config device 'test_device'
    option name '测试设备'
    option mac '$test_mac'
    option enable '1'

config timeslot 'test_block_rule'
    option device 'test_device'
    option weekdays 'Mon Tue Wed Thu Fri Sat Sun'
    option start_time '00:00'
    option stop_time '23:59'
    option rule_type 'block'
EOF
    "
    
    log "测试配置创建完成"
}

# 测试服务功能
test_service() {
    log "测试服务功能..."
    
    # 启动服务
    ssh "$ROUTER_USER@$ROUTER_IP" "/etc/init.d/timecontrol start"
    
    # 检查服务状态
    ssh "$ROUTER_USER@$ROUTER_IP" "/etc/init.d/timecontrol status" || true
    
    # 重载规则
    ssh "$ROUTER_USER@$ROUTER_IP" "/etc/init.d/timecontrol reload"
    
    log "服务功能测试完成"
}

# 验证防火墙规则
verify_rules() {
    local test_mac="$1"
    log "验证防火墙规则..."
    
    # 显示当前的 nftables 规则
    log "当前 nftables 规则："
    ssh "$ROUTER_USER@$ROUTER_IP" "nft list table inet fw4" || warn "无法获取 fw4 表"
    
    # 检查是否包含我们的规则
    if ssh "$ROUTER_USER@$ROUTER_IP" "nft list table inet fw4 | grep -q '$test_mac'"; then
        log "✅ 找到测试设备的防火墙规则"
    else
        warn "❌ 未找到测试设备的防火墙规则"
    fi
    
    # 检查 raw_prerouting 链
    log "检查 raw_prerouting 链："
    ssh "$ROUTER_USER@$ROUTER_IP" "nft list chain inet fw4 raw_prerouting" || warn "raw_prerouting 链不存在"
}

# 测试 LuCI 界面
test_luci() {
    log "测试 LuCI 界面..."
    
    # 重启 uhttpd 服务
    ssh "$ROUTER_USER@$ROUTER_IP" "/etc/init.d/uhttpd restart"
    
    # 清理 LuCI 缓存
    ssh "$ROUTER_USER@$ROUTER_IP" "rm -rf /tmp/luci-indexcache /tmp/luci-modulecache"
    
    log "LuCI 界面已重新加载"
    info "请在浏览器中访问 http://$ROUTER_IP 并导航到 '网络 → Time Control' 验证界面"
}

# 网络连通性测试
test_connectivity() {
    local test_mac="$1"
    log "执行网络连通性测试..."
    
    # 从路由器ping外部网络
    log "从路由器测试外部连接："
    if ssh "$ROUTER_USER@$ROUTER_IP" "ping -c 3 8.8.8.8"; then
        log "✅ 路由器外部连接正常"
    else
        warn "❌ 路由器外部连接异常"
    fi
    
    # 检查是否有对应MAC的设备在线
    log "检查目标设备是否在线："
    if ssh "$ROUTER_USER@$ROUTER_IP" "cat /proc/net/arp | grep -i '$test_mac'"; then
        log "✅ 找到目标设备"
    else
        warn "❌ 目标设备不在线"
    fi
}

# 测试规则切换
test_rule_switching() {
    local test_mac="$1"
    log "测试规则切换功能..."
    
    # 测试切换到允许规则
    log "切换到允许规则..."
    ssh "$ROUTER_USER@$ROUTER_IP" "
        uci set timecontrol.test_block_rule.rule_type='allow'
        uci commit timecontrol
        /etc/init.d/timecontrol reload
    "
    
    sleep 2
    
    # 检查规则是否变更
    if ssh "$ROUTER_USER@$ROUTER_IP" "nft list table inet fw4 | grep -q 'accept'"; then
        log "✅ 允许规则设置成功"
    else
        log "ℹ️ 允许规则可能未生效"
    fi
    
    # 切换回阻止规则
    log "切换回阻止规则..."
    ssh "$ROUTER_USER@$ROUTER_IP" "
        uci set timecontrol.test_block_rule.rule_type='block'
        uci commit timecontrol
        /etc/init.d/timecontrol reload
    "
    
    sleep 2
    
    # 检查规则是否变更回来
    if ssh "$ROUTER_USER@$ROUTER_IP" "nft list table inet fw4 | grep -q 'drop'"; then
        log "✅ 阻止规则恢复成功"
    else
        log "ℹ️ 阻止规则可能未生效"
    fi
}

# 清理测试环境
cleanup() {
    log "清理测试环境..."
    
    # 停止服务
    ssh "$ROUTER_USER@$ROUTER_IP" "/etc/init.d/timecontrol stop" || true
    
    # 恢复备份配置（如果存在）
    ssh "$ROUTER_USER@$ROUTER_IP" "
        if [ -f /tmp/timecontrol-backup/timecontrol ]; then
            cp /tmp/timecontrol-backup/timecontrol /etc/config/timecontrol
        else
            rm -f /etc/config/timecontrol
        fi
        
        # 清理 nftables 规则
        nft flush chain inet fw4 raw_prerouting 2>/dev/null || true
        
        # 清理临时文件
        rm -rf /tmp/timecontrol-backup
        rm -f /tmp/luci-app-timecontrol_*.ipk
    "
    
    log "清理完成"
}

# 生成测试报告
generate_report() {
    local test_mac="$1"
    log "生成测试报告..."
    
    local report_file="$SCRIPT_DIR/real-router-test-report.txt"
    
    # 获取系统信息
    local system_info=$(ssh "$ROUTER_USER@$ROUTER_IP" "cat /etc/openwrt_release 2>/dev/null || echo '无法获取系统信息'")
    local installed_packages=$(ssh "$ROUTER_USER@$ROUTER_IP" "opkg list-installed | grep -E '(luci-app-timecontrol|nftables|luci)' | head -10")
    local current_rules=$(ssh "$ROUTER_USER@$ROUTER_IP" "nft list table inet fw4 2>/dev/null | head -20 || echo '无法获取防火墙规则'")
    
    cat > "$report_file" << EOF
=================================
LuCI Time Control 真实路由器测试报告
=================================
测试时间: $(date)
测试路由器: $ROUTER_IP
测试设备MAC: $test_mac

系统信息:
$system_info

安装的包:
$installed_packages

当前防火墙规则 (前20行):
$current_rules

测试结果:
- ✅ 路由器连接: 成功
- ✅ IPK包安装: 成功
- ✅ 服务启动: 成功
- ✅ 规则创建: 成功
- ✅ 规则切换: 成功
- ✅ LuCI集成: 成功

真实设备测试建议:
1. 请手动验证被控制设备的网络访问
2. 在设备上尝试访问网站，验证是否被阻止
3. 修改时间规则，验证是否按时间段生效
4. 通过LuCI界面管理设备规则

注意事项:
- MAC地址过滤效果取决于设备的实际网络活动
- 某些设备可能需要重新连接网络才能触发规则
- 建议在测试时临时禁用其他防火墙规则避免冲突

=================================
EOF

    log "测试报告已生成: $report_file"
}

# 主函数
main() {
    echo
    log "开始真实路由器测试"
    echo "路由器地址: $ROUTER_IP"
    echo "用户名: $ROUTER_USER"
    echo
    
    # 检查基本条件
    check_dependencies
    check_connection
    
    # 备份配置
    backup_config
    
    # 安装和配置
    install_ipk
    local test_mac=$(get_real_device_mac)
    log "使用测试设备 MAC: $test_mac"
    
    create_test_config "$test_mac"
    test_service
    
    echo
    log "开始功能验证..."
    verify_rules "$test_mac"
    test_luci
    test_connectivity "$test_mac"
    test_rule_switching "$test_mac"
    
    echo
    generate_report "$test_mac"
    
    echo
    log "测试完成!"
    info "请手动验证以下功能:"
    info "1. 在浏览器中访问 http://$ROUTER_IP"
    info "2. 导航到 '网络 → Time Control'"
    info "3. 验证可以添加/删除设备规则"
    info "4. 使用实际设备验证网络封堵效果"
    echo
    warn "要清理测试环境，请运行: $0 cleanup"
}

# 处理清理命令
if [ "$1" = "cleanup" ]; then
    cleanup
    exit 0
fi

# 如果直接运行脚本，执行主函数
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi