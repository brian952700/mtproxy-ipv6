# Telegram MTProxy：仅 IPv6 接入

Debian 12+、AMD64；默认端口 10443，可选 10001–65535。基于 Telegram 官方 C 版源码，只生成一个 IPv6 代理链接。

## 一键安装

root 执行：

```bash
curl -fLsS https://raw.githubusercontent.com/brian952700/mtproxy-ipv6/main/install.sh -o /tmp/telegram-mtproxy-install.sh && bash /tmp/telegram-mtproxy-install.sh
```

当前服务器使用 38503 时：

```bash
PORT=38503 bash /tmp/telegram-mtproxy-install.sh --non-interactive
```

自动检测本机公网 IPv6；多个地址时可在交互终端中编号选择，也可通过 `IPV6='地址'` 指定。本机没有公网 IPv6 时退出，不停止原服务。请放行云安全组和本机防火墙的 IPv6 TCP 对应端口。

## IPv6 限制的范围

官方 `-6` 原本是双栈。脚本固定官方提交 `69f2f083b57bbd94932cb9f4f32155f33e719ff1`，在客户端监听的 `server_socket` 调用中增加 `SM_IPV6_ONLY` 标志，令该套接字使用 `IPV6_V6ONLY=1`。**这是基于官方源码的一处补丁，并非完全未修改的原版。**安装时验证替换位置唯一，否则退出。

限制的是 Telegram 客户端入口；下载、DNS、统计端口和代理连接 Telegram 的上游保持原方式，可能使用 IPv4。本方案不要求服务器删除 IPv4，也不修改全局网络参数和防火墙。

## 已安装服务器的切换

- 原 `/opt/telegram-mtproxy/objs/bin/mtproto-proxy` 保留，另行编译 `mtproto-proxy-ipv6-only`。
- 保留现有 `client-secret`，服务名称仍为 `telegram-mtproxy.service`。原 IPv4 代理在切换后无法再连接。
- 备份原服务、已知 `dual-stack.conf` 及 Telegram 配置到 `/opt/telegram-mtproxy/backup.*`，启动失败尝试恢复原配置。
- 已有匹配构建标记的 IPv6 程序可复用。其他自定义 systemd drop-in 不修改。
- 每次安装获取官方 `getProxySecret` 和 `getProxyConfig`；不调用 GitHub API。官方建议定期更新数据中心配置，此脚本未安装更新定时任务。
- 生成 `dd` 随机填充模式链接；客户端密钥与服务原始密钥相比多出 `dd` 前缀。

```bash
systemctl status telegram-mtproxy.service
journalctl -u telegram-mtproxy.service -n 50 --no-pager
sudo cat /opt/telegram-mtproxy/access-ipv6.txt
```

旧的双栈链接文件可能仍在磁盘上，请使用新生成的 `access-ipv6.txt`。不要将密钥和连接文件提交 GitHub。

中文彩色进度、root 专属安装日志、`NO_COLOR=1`、`--preview`、`--non-interactive` / `NONINTERACTIVE=1` 均保留。第一次会安装编译依赖，需要能访问 Debian 软件源、GitHub 和 core.telegram.org。IPv6 入口模式不能解决客户端到服务器的 IPv6 路由或阻断问题。

## 验证范围

CI 包含 ShellCheck、界面预览与链接测试、Debian 12 / 13 编译及真实套接字测试：IPv6 回环连接成功、IPv4 回环连接被拒绝。安装后也验证 IPv6 监听和 IPv4 回环拒绝。外网路由、防火墙和 Telegram 握手仍以客户端实测为准。
