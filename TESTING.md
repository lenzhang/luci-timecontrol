# LuCI Time Control 测试指南

本文档描述了如何对 LuCI Time Control 应用进行全面测试，包括 Docker 环境测试和真实路由器测试。

## 📋 测试概览

我们提供了两种测试方案：

1. **Docker 环境测试** (`test-e2e.sh`) - 快速验证基本功能
2. **真实路由器测试** (`test-real-router.sh`) - 完整的端到端功能验证

## 🐳 Docker 环境测试

### 适用场景
- 快速验证 IPK 包安装过程
- 测试服务脚本和配置文件
- 验证 LuCI 界面集成
- 开发和调试阶段的自动化测试

### 使用方法

```bash
# 确保 Docker 已安装并运行
./test-e2e.sh
```

### 测试内容
- ✅ IPK 包安装验证
- ✅ 系统依赖检查
- ✅ 服务启动和管理
- ✅ 配置文件生成和解析
- ✅ nftables 规则创建
- ✅ LuCI 文件部署
- ✅ 压力测试（多设备规则）

### 局限性
- ❌ 无法测试真实的 MAC 地址过滤
- ❌ 无法验证实际的网络封堵效果
- ❌ Docker 网络环境与真实路由器环境不同

### 预期结果
```
=============== 测试结果摘要 ===============
✅ IPK包安装: 成功
✅ 服务启动: 成功  
✅ 配置生效: 成功
✅ 规则创建: 成功
✅ LuCI集成: 成功
✅ 压力测试: 成功
==========================================
```

## 🌐 真实路由器测试

### 适用场景
- 验证完整的网络封堵功能
- 测试真实设备的 MAC 地址过滤
- 验证与现有网络环境的兼容性
- 最终产品功能确认

### 前置条件
1. 可通过 SSH 访问的 OpenWrt 路由器
2. 路由器已配置网络连接
3. 有连接到路由器的测试设备

### 使用方法

```bash
# 基本用法（默认连接 192.168.1.1）
./test-real-router.sh

# 自定义路由器地址和用户名
ROUTER_IP=192.168.4.1 ROUTER_USER=admin ./test-real-router.sh

# 清理测试环境
./test-real-router.sh cleanup
```

### 测试内容
- ✅ 路由器连接和认证
- ✅ IPK 包远程安装
- ✅ 真实设备 MAC 地址检测
- ✅ 防火墙规则验证
- ✅ 网络连通性测试
- ✅ 规则动态切换测试
- ✅ LuCI 界面集成验证

### 手动验证步骤

测试脚本完成后，请手动执行以下验证：

1. **LuCI 界面验证**
   ```
   1. 浏览器访问路由器管理界面
   2. 导航到 "网络" → "Time Control"
   3. 验证界面正常显示
   4. 测试添加/删除设备功能
   ```

2. **实际封堵效果验证**
   ```
   1. 添加当前设备的 MAC 地址到阻止规则
   2. 设置当前时间段为阻止时间
   3. 在该设备上尝试访问网络
   4. 验证是否被成功阻止
   ```

3. **时间规则验证**
   ```
   1. 设置特定的时间段规则
   2. 等待时间段变更
   3. 验证规则是否按时间自动生效
   ```

## 🧪 测试脚本详细说明

### Docker 测试脚本功能

| 功能模块 | 描述 | 验证内容 |
|---------|------|---------|
| 环境准备 | 启动 OpenWrt 容器 | Docker 网络、容器状态 |
| 依赖安装 | 安装系统依赖包 | nftables, luci-base 等 |
| IPK 安装 | 安装 timecontrol 包 | 包管理、文件部署 |
| 服务测试 | 测试服务管理 | 启动、停止、重载功能 |
| 配置验证 | 验证 UCI 配置 | 配置文件解析、规则生成 |
| 规则检查 | 检查防火墙规则 | nftables 规则创建 |
| 压力测试 | 多设备规则测试 | 性能和稳定性 |

### 真实路由器测试脚本功能

| 功能模块 | 描述 | 验证内容 |
|---------|------|---------|
| 连接检查 | 验证 SSH 连接 | 网络连通性、认证 |
| 环境备份 | 备份现有配置 | 安全性、可恢复性 |
| 设备扫描 | 发现网络设备 | ARP 表、DHCP 租约 |
| 功能测试 | 完整功能验证 | 真实环境下的所有功能 |
| 规则切换 | 动态规则测试 | 实时配置变更 |
| 清理恢复 | 环境清理 | 配置恢复、规则清理 |

## 📊 测试报告

两个测试脚本都会生成详细的测试报告：

- **Docker 测试报告**: `test-report.txt`
- **真实路由器测试报告**: `real-router-test-report.txt`

报告包含：
- 系统信息和安装的包
- 当前配置和防火墙规则
- 测试结果摘要
- 发现的问题和建议

## ⚠️ 注意事项

### Docker 测试注意事项
1. 需要 Docker 环境支持 `--privileged` 模式
2. 测试容器会保留，便于进一步调试
3. 网络封堵测试仅为模拟，不代表真实效果

### 真实路由器测试注意事项
1. **会修改路由器配置** - 测试前请备份重要配置
2. **可能影响网络连接** - 建议在测试环境进行
3. **需要管理员权限** - 确保有足够的权限操作路由器
4. **自动清理功能** - 测试完成会尝试恢复配置

### 安全建议
- 在生产环境测试前，请先在测试环境验证
- 建议使用专用的测试路由器或虚拟机
- 保留原始配置的完整备份
- 测试完成后验证网络功能正常

## 🐛 故障排除

### 常见问题

**问题**: Docker 测试失败，提示权限不足
```bash
# 解决方案：确保 Docker 有足够权限
sudo ./test-e2e.sh
```

**问题**: SSH 连接路由器失败
```bash
# 解决方案：检查网络连接和认证
ping 192.168.1.1
ssh root@192.168.1.1
```

**问题**: IPK 安装失败，提示依赖不满足
```bash
# 解决方案：手动安装依赖
opkg update
opkg install nftables kmod-nft-core luci-base
```

**问题**: 防火墙规则未生效
```bash
# 解决方案：检查 nftables 服务状态
/etc/init.d/firewall restart
nft list tables
```

### 调试技巧

1. **保留测试环境**
   ```bash
   # Docker 环境调试
   docker exec -it openwrt-test-timecontrol sh
   
   # 查看日志
   logread | grep timecontrol
   ```

2. **手动验证规则**
   ```bash
   # 检查配置
   uci show timecontrol
   
   # 检查防火墙规则
   nft list table inet fw4
   
   # 检查服务状态
   /etc/init.d/timecontrol status
   ```

3. **网络诊断**
   ```bash
   # 检查设备连接
   cat /proc/net/arp
   cat /tmp/dhcp.leases
   
   # 测试网络连通性
   ping -c 1 8.8.8.8
   ```

## 📈 持续集成

这些测试脚本可以集成到 CI/CD 流程中：

```yaml
# GitHub Actions 示例
name: Test LuCI TimeControl
on: [push, pull_request]
jobs:
  docker-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run Docker Tests
        run: ./test-e2e.sh
      - name: Upload Test Report
        uses: actions/upload-artifact@v2
        with:
          name: test-report
          path: test-report.txt
```

## 🤝 贡献测试用例

欢迎贡献更多测试用例：

1. Fork 项目仓库
2. 添加新的测试场景
3. 更新测试文档
4. 提交 Pull Request

---

**💡 提示**: 建议先运行 Docker 测试验证基本功能，然后在真实环境中进行完整验证。