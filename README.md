# Telegram 官方 MTProxy：仅 IPv4 接入

Debian 12+（systemd）和 Alpine 3.22+ 3.x（OpenRC），仅 x86_64。使用 Telegram 官方源码，不传入双栈参数，只输出 IPv4 链接。默认 TCP 38503，可通过 PORT 设置 10001–65535 内的端口。

root 一键安装：

```bash
curl -fLsS https://raw.githubusercontent.com/brian952700/mtproxy-ipv6/main/install.sh -o /tmp/telegram-mtproxy-install.sh && bash /tmp/telegram-mtproxy-install.sh
```

可用 IPV4=公网入口地址 显式指定地址，避免自动检测到 NAT 出口地址。用 --non-interactive 跳过提问；--preview 只预览。

复用现有官方程序和密钥，备份配置后重启 telegram-mtproxy.service。新链接保存在 /opt/telegram-mtproxy/access-ipv4.txt。云安全组和本机防火墙须放行 IPv4 TCP 38503 或自选端口。旧 IPv6 链接将不再有效。

### Alpine

先执行 `apk add --no-cache bash curl ca-certificates`，再运行上面的一键安装命令。服务使用 `rc-service telegram-mtproxy status` 查看，日志位于 `/var/log/telegram-mtproxy.log`。

Alpine 使用 musl。编译时移除官方程序依赖 glibc 的堆栈回溯代码，保留代理功能。