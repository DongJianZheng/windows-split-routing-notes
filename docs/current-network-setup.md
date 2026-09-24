# 当前 Windows 网络分流配置复盘

更新时间：2026-09-24

## 一、目标

```text
ChatGPT / Codex / OpenAI / GitHub → VPS
Google 等其他境外网站             → 悠兔
国内网站、微信、ToDesk、OpenVPN   → DIRECT
公司内网                          → OpenVPN
```

这样设计是因为 VPS 出口稳定，适合 OpenAI、Codex 和 GitHub；悠兔节点多，适合普通境外网站；国内网站不需要代理；OpenVPN 必须保持直连，避免代理套 VPN。

## 二、当前客户端和端口

主客户端是 Clash Verge（Mihomo），v2rayN 不再作为系统代理。

```text
Clash HTTP/Mixed：127.0.0.1:7897
Clash SOCKS：    127.0.0.1:7896
旧 v2rayN：      127.0.0.1:7898
```

推荐状态：系统代理开启、规则模式、TUN 关闭、IPv6 关闭。v2rayN 可以退出。

## 三、配置文件位置

安装目录：

```text
D:\Program Files\Clash Verge
```

用户配置目录：

```text
C:\Users\11756\AppData\Roaming\io.github.clash-verge-rev.clash-verge-rev
```

关键文件：

```text
profiles.yaml             # 订阅与覆写模板关联
profiles\Rf4SxaWArEv3.yaml # 悠兔远程订阅，更新时会重写
profiles\pbfpRUSgwVjH.yaml # VPS 代理覆写
profiles\gccbkMr7KodN.yaml # VPS 代理组覆写
profiles\rkWdhCQ9Svzf.yaml # 分流规则覆写
verge.yaml                # 界面设置
config.yaml               # 运行端口等基础设置
```

不要直接把 VPS 写进悠兔远程文件。正确结构是：

```text
悠兔远程订阅 + VPS 代理覆写 + 代理组覆写 + 规则覆写
```

Clash Verge 会自动合并。一个代理名或代理组名只能出现一次；之前的 `duplicate name` 就是因为 VPS 同时写了两份。

## 四、分流逻辑

### VPS 组 `VPS-OpenAI-Git`

```text
openai.com、chatgpt.com、auth.openai.com、api.openai.com
oaistatic.com、oaiusercontent.com、oaistatsig.com、statsigapi.net
github.com、githubusercontent.com、githubassets.com、github.io
git.exe、gh.exe、GitHubDesktop.exe
```

### 悠兔组

Google、YouTube、TikTok、Telegram、X、Reddit 等其他境外网站。可以选择“自动选择”或固定节点。

### DIRECT

```text
中国域名和中国 IP
公司业务域名（示例：`<COMPANY_DOMAIN>`）
微信、Weixin、ToDesk、OpenVPNConnect、openvpn.exe
局域网和私有地址
```

## 五、网卡分工

```text
有线：国内直连、VPS 外层连接、公司网络
手机 Wi-Fi：悠兔节点外层连接
```

悠兔节点的公网 IP 通过 `/32` 持久路由固定到手机 Wi-Fi 网关 `192.168.43.1`。脚本位置：

```text
scripts\set-youtu-wifi-route.ps1
```

管理员 PowerShell 执行：

```powershell
cd 'D:\工作工具\windows-split-routing-notes'
powershell -ExecutionPolicy Bypass -File .\scripts\set-youtu-wifi-route.ps1
```

脚本同时支持 YouTuCore 和 Clash Verge 的 `verge-mihomo.exe`，切换悠兔节点后应重新运行。只预览不修改：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\set-youtu-wifi-route.ps1 -NoApply
```

## 六、不同网络环境

### 有线 + 手机 Wi-Fi

连接两种网络，启动 Clash，选择 `VPS → VPS-OpenAI-Git`、`悠兔 → 自动选择`，再运行 Wi-Fi 路由脚本。

### 只有有线

VPS 和国内直连可以使用，悠兔会因没有手机 Wi-Fi 而超时。临时把“悠兔”组选择 `VPS-OpenAI-Git`，即可让原本走悠兔的境外流量也走 VPS；不需要改规则。

### 只有手机 Wi-Fi

所有物理出口都会是 Wi-Fi，VPS 仍可用，但没有有线作为优先外层网络。

## 七、OpenVPN

OpenVPN 程序保持 `DIRECT`，公司内网路由和公司 DNS 由 OpenVPN 自己管理。不要让 OpenVPN 经过 Clash 或悠兔。

## 八、验证命令

```powershell
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' |
  Select-Object ProxyEnable,ProxyServer,AutoConfigURL

Test-NetConnection 127.0.0.1 -Port 7897

$pid = (Get-Process verge-mihomo).Id
Get-NetTCPConnection -State Established -OwningProcess $pid |
  Select-Object LocalAddress,RemoteAddress,RemotePort
```

悠兔连接使用 `192.168.43.x` 表示走手机 Wi-Fi；OpenAI/GitHub 应在 Clash 日志中显示 `VPS-OpenAI-Git`。

## 九、排错原则

1. 只运行一个主代理客户端。
2. 确认 `7897` 正在监听，系统代理指向 `127.0.0.1:7897`。
3. 保持规则模式，TUN 关闭。
4. 确认悠兔节点 IP 的 `/32` 路由指向 WLAN。
5. 订阅更新后不要手改远程订阅，改覆写模板。
6. 出现 `duplicate name` 时，检查是否重复定义了 VPS 节点或代理组。
7. Codex 切换客户端后完全退出并重新打开，避免继续使用旧的 `7898` 环境变量。
