
# nezha-agent-nic_allowlist

自动检测当前机器的主网卡，并为 [哪吒探针 Agent](https://nezha.wiki) 的配置文件添加/更新 `nic_allowlist` 配置。  
通过此脚本可避免手动修改配置，确保探针监控正确的网卡。

项目地址: [https://github.com/ClaraCora/nezha-agent-nic_allowlist](https://github.com/ClaraCora/nezha-agent-nic_allowlist)

---

## 功能特性

- 自动识别默认路由主网卡（优先 IPv4，失败再尝试 IPv6）。
- 排除 `lo`、`docker*`、`veth`、`br-*` 等虚拟或无效网卡。
- 清理旧的 `nic_allowlist` 配置块，避免重复或冲突。
- 在配置文件末尾写入新的 `nic_allowlist`，仅启用检测到的主网卡。
- 自动备份原始配置文件。
- 美观的日志输出（带颜色和图标）。
- 自动重启 `nezha-agent` 服务，确保配置生效。

---

## 使用方法

### 一键运行

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ClaraCora/nezha-agent-nic_allowlist/main/set-nezha-nic.sh)"
````


### 手动版 1. 克隆项目
```bash
git clone https://github.com/ClaraCora/nezha-agent-nic_allowlist.git
cd nezha-agent-nic_allowlist
````

### 2. 赋予脚本执行权限

```bash
chmod +x set-nezha-nic.sh
```

### 3. 运行脚本

```bash
sudo ./set-nezha-nic.sh
```

脚本会：

1. 备份 `/opt/nezha/agent/config.yml`。
2. 自动检测主网卡并写入 `nic_allowlist`。
3. 重启 `nezha-agent` 服务。

---

## 日志示例

```text
[2025-08-17 10:20:00] ✔ 前置检查通过
[2025-08-17 10:20:00] ℹ 已创建备份: /opt/nezha/agent/config.yml.20250817-102000.bak
[2025-08-17 10:20:00] ✔ 通过 IPv4 默认路由检测主网卡: eth0
[2025-08-17 10:20:00] ✔ 已清理旧的 nic_allowlist 块（如存在）
[2025-08-17 10:20:00] ℹ 即将写入内容预览：
---
nic_allowlist:
  eth0: true
---
[2025-08-17 10:20:00] ✔ 写入完成: /opt/nezha/agent/config.yml
[2025-08-17 10:20:00] ✔ 服务已重启: nezha-agent
```

---

## 注意事项

* 默认配置文件路径为 `/opt/nezha/agent/config.yml`。
* 必须以 **root** 用户执行。
* 如果系统中不存在 `nezha-agent` 服务，请手动调整脚本中的 `SERVICE` 名称。

---

## 许可证

MIT License


