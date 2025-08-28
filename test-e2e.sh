#!/bin/bash

# LuCI Time Control 端到端功能测试
# 启动完整的OpenWrt环境，通过Web界面测试实际封堵效果

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="openwrt-e2e-test"
CLIENT_CONTAINER="test-client"
NETWORK_NAME="test-network"
ROUTER_IP="172.20.0.1"
CLIENT_IP="172.20.0.100"
WEB_PORT=18888
IPK_FILE="$SCRIPT_DIR/build/luci-app-timecontrol_1.2.0_all.ipk"

log() {
    echo "[$(date +'%H:%M:%S')] $1"
}

error() {
    echo "[ERROR] $1"
    exit 1
}

cleanup() {
    log "清理测试环境..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    docker stop "$CLIENT_CONTAINER" 2>/dev/null || true
    docker rm "$CLIENT_CONTAINER" 2>/dev/null || true
    docker network rm "$NETWORK_NAME" 2>/dev/null || true
}

# 创建测试网络
setup_network() {
    log "创建测试网络..."
    docker network create "$NETWORK_NAME" \
        --subnet=172.20.0.0/24 \
        --gateway="$ROUTER_IP" 2>/dev/null || true
}

# 启动OpenWrt路由器容器
start_router() {
    log "启动OpenWrt路由器容器..."
    
    docker run -d \
        --name "$CONTAINER_NAME" \
        --platform linux/amd64 \
        --network "$NETWORK_NAME" \
        --ip "$ROUTER_IP" \
        --cap-add NET_ADMIN \
        --cap-add NET_RAW \
        --privileged \
        -p "$WEB_PORT:80" \
        -v "$SCRIPT_DIR:/host:ro" \
        openwrt/rootfs:x86-64-23.05.4 \
        sh -c "sleep infinity"
    
    sleep 5
    
    # 初始化路由器
    docker exec "$CONTAINER_NAME" sh -c "
        # 配置网络
        ip addr add 172.20.0.1/24 dev eth0 2>/dev/null || true
        ip link set eth0 up
        echo 1 > /proc/sys/net/ipv4/ip_forward
        
        # 安装基础包
        opkg update
        opkg install uhttpd uhttpd-mod-ubus luci-base luci-mod-admin-full
        opkg install kmod-nft-core nftables
        
        # 初始化防火墙
        nft add table inet fw4 2>/dev/null || true
        nft add chain inet fw4 raw_prerouting { type filter hook prerouting priority raw \; } 2>/dev/null || true
        
        # 启动Web服务
        /etc/init.d/uhttpd start
    "
    
    log "✅ 路由器容器启动成功"
}

# 启动测试客户端容器
start_client() {
    log "启动测试客户端容器..."
    
    # 使用Alpine作为测试客户端
    docker run -d \
        --name "$CLIENT_CONTAINER" \
        --network "$NETWORK_NAME" \
        --ip "$CLIENT_IP" \
        --mac-address "aa:bb:cc:dd:ee:ff" \
        alpine:latest \
        sh -c "apk add --no-cache curl wget; sleep infinity"
    
    sleep 3
    
    log "✅ 客户端容器启动成功 (MAC: aa:bb:cc:dd:ee:ff)"
}

# 安装timecontrol
install_timecontrol() {
    log "安装timecontrol包..."
    
    docker exec "$CONTAINER_NAME" sh -c "
        cd /tmp
        tar -xzf /host/build/luci-app-timecontrol_1.2.0_all.ipk
        tar -xzf data.tar.gz
        cp -r etc/* /etc/ 2>/dev/null || true
        cp -r usr/* /usr/ 2>/dev/null || true
        chmod 755 /etc/init.d/timecontrol
        
        # 启动服务
        /etc/init.d/timecontrol start
        
        # 重启uhttpd
        /etc/init.d/uhttpd restart
    "
    
    log "✅ timecontrol安装完成"
}

# 测试网络连通性
test_connectivity() {
    local description="$1"
    local expected="$2"
    
    log "测试: $description"
    
    # 从客户端测试外网连接
    if docker exec "$CLIENT_CONTAINER" ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1; then
        local result="✅ 可以访问外网"
    else
        local result="❌ 无法访问外网"
    fi
    
    echo "  结果: $result"
    echo "  预期: $expected"
}

# 添加封堵规则
add_block_rule() {
    log "添加封堵规则..."
    
    docker exec "$CONTAINER_NAME" sh -c '
        cat > /etc/config/timecontrol << EOF
config device "test_device"
    option name "测试设备"
    option mac "aa:bb:cc:dd:ee:ff"
    option enable "1"

config timeslot "block_all"
    option device "test_device"
    option weekdays "Mon Tue Wed Thu Fri Sat Sun"
    option start_time "00:00"
    option stop_time "23:59"
    option rule_type "block"
EOF
        
        /etc/init.d/timecontrol reload
    '
    
    sleep 2
    
    # 显示防火墙规则
    docker exec "$CONTAINER_NAME" nft list chain inet fw4 raw_prerouting 2>/dev/null || true
}

# 删除封堵规则
remove_block_rule() {
    log "删除封堵规则..."
    
    docker exec "$CONTAINER_NAME" sh -c '
        > /etc/config/timecontrol
        /etc/init.d/timecontrol reload
    '
    
    sleep 2
}

# 主测试流程
run_tests() {
    log "开始功能测试..."
    
    echo
    log "=== 测试1: 初始状态（无规则）==="
    test_connectivity "无封堵规则时的连通性" "可以访问外网"
    
    echo
    log "=== 测试2: 添加封堵规则 ==="
    add_block_rule
    test_connectivity "添加封堵规则后的连通性" "无法访问外网"
    
    echo
    log "=== 测试3: 删除封堵规则 ==="
    remove_block_rule
    test_connectivity "删除封堵规则后的连通性" "可以访问外网"
    
    echo
    log "=== 测试4: Web界面验证 ==="
    echo "  访问: http://localhost:$WEB_PORT"
    echo "  导航: 网络 → Time Control"
    echo "  测试设备MAC: aa:bb:cc:dd:ee:ff"
}

# 主函数
main() {
    log "🚀 开始端到端功能测试"
    
    # 确保IPK包存在
    if [ ! -f "$IPK_FILE" ]; then
        log "构建IPK包..."
        "$SCRIPT_DIR/build.sh"
    fi
    
    # 清理旧环境
    cleanup
    
    # 搭建测试环境
    setup_network
    start_router
    start_client
    
    # 安装和配置
    install_timecontrol
    
    # 运行测试
    run_tests
    
    echo
    log "✅ 测试完成！"
    echo "   Web界面: http://localhost:$WEB_PORT"
    echo "   客户端测试: docker exec $CLIENT_CONTAINER ping 8.8.8.8"
    echo "   查看规则: docker exec $CONTAINER_NAME nft list ruleset"
    echo "   清理: ./test-e2e.sh cleanup"
}

# 处理命令行参数
if [ "$1" = "cleanup" ]; then
    cleanup
    exit 0
fi

main "$@"
