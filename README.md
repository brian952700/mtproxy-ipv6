# IPv6-only MTProxy 一键安装

Debian 12 及以上，amd64 / arm64，原生 [mtg](https://github.com/9seconds/mtg) v2.3.0 + systemd，无 Docker 或面板。

## 一键安装

使用 root 登录后运行（需要预装 curl）：

```bash
curl -fLsS https://raw.githubusercontent.com/brian952700/mtproxy-ipv6/main/install.sh -o /tmp/mtproxy-ipv6-install.sh && bash /tmp/mtproxy-ipv6-install.sh
```

默认端口 **10443**，只绑定本机具体公网 IPv6，Telegram 出口只走 IPv6。云安全组和本机防火墙需放行 **IPv6 TCP 10443**；脚本不会改动防火墙规则。

自定义端口（仅允许 **10001–65535**）、IPv6 和 FakeTLS 域名：

```bash
PORT=20000 IPV6='你的公网IPv6' TLS_DOMAIN='www.cloudflare.com' bash /tmp/mtproxy-ipv6-install.sh
```

多个 IPv6 时建议明确设置 `IPV6`；否则自动选取首个已配置的公网 IPv6。地址变更后需修改配置并重启服务。默认域名只是可用的示例，不保证与 VPS 地址相符或能够规避识别，可换成适合自己网络的 TLS 域名。

## 网络要求

- 客户端必须能访问公网 IPv6；VPS 必须能经 IPv6 连接 Telegram 和所选 FakeTLS 域名。
- **运行走 IPv6，不等于下载源支持 IPv6。** 安装时 Debian 软件源、GitHub API 和发布附件必须可达。没有 IPv4 的 VPS 需要可用 NAT64/DNS64、HTTP(S) 下载代理等联网条件。脚本不会自动使用第三方镜像或更改 DNS。
- 如需通过已有代理下载 GitHub，运行前设置 `https_proxy`（例如 `export https_proxy=http://[代理IPv6]:3128`）。APT 代理须按系统设置另行配置。脚本的 IPv6 出口检测会主动绕过下载代理。
- DNS 使用系统解析器；DNS、APT 和安装下载的地址族取决于系统配置。`only-ipv6` 限制的是 mtg 连接 Telegram 的出口。
- 高端口满足此脚本需求，但 FakeTLS 使用高端口不等于普通 HTTPS 的 443，不能承诺长期可用。

## 安装行为

安装最少依赖，下载固定版本的官方发行包，核对该版本官方 SHA256 清单，生成随机 FakeTLS secret，执行 `mtg doctor` 后安装。诊断未通过会显示提示并继续（例如外部伪装域名与 VPS 地址不匹配）；请检查输出中的网络错误。SHA256 用于验证下载一致性，不能替代独立签名验证。配置不会上传 GitHub。

服务以 systemd 动态用户运行，通过 `LoadCredential` 读取 root 专属配置，启用自动重启。重复安装会退出，防止覆盖密钥。安装后检测本机监听；**未进行外部 Telegram 客户端连接测试**。

## 管理

```bash
systemctl status mtproxy-ipv6
systemctl restart mtproxy-ipv6
journalctl -u mtproxy-ipv6 -n 50 --no-pager
sudo cat /opt/mtproxy-ipv6/access.txt
sudo /opt/mtproxy-ipv6/mtg doctor /opt/mtproxy-ipv6/config.toml
```

安装完成会显示连接地址、端口、密钥和导入链接。部分客户端不支持链接中的 IPv6 字面量，可手动填写地址，或使用只配置 AAAA 记录的域名。不要把密钥、配置和连接信息提交到公开仓库。

卸载（会删除此服务的配置和密钥）：

```bash
systemctl disable --now mtproxy-ipv6.service
rm -f /etc/systemd/system/mtproxy-ipv6.service
rm -rf /opt/mtproxy-ipv6
systemctl daemon-reload
```

## 验证范围

仓库提供 Bash 语法检查和 ShellCheck CI。安装需要真实 Debian、systemd 和可达 Telegram 的 IPv6 网络；CI 不声称替代真实服务器及 Telegram 客户端验收。
