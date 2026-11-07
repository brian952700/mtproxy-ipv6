# Telegram 官方 MTProxy 双栈一键安装

Debian 12 及以上、AMD64，使用 [Telegram 官方 C 版 MTProxy](https://github.com/TelegramMessenger/MTProxy)，IPv4 + IPv6 双栈监听，分别生成两个 `dd` 随机填充模式链接。默认端口 **10443**，允许 **10001–65535**。

仓库名沿用 `mtproxy-ipv6`，`install.sh` 已替换为官方实现。旧 mtg 脚本可在 Git 历史中找到。

## 一键安装

root 用户执行（需要 curl）：

```bash
curl -fLsS https://raw.githubusercontent.com/brian952700/mtproxy-ipv6/main/install.sh -o /tmp/telegram-mtproxy-install.sh && bash /tmp/telegram-mtproxy-install.sh
```

自动识别公网 IPv4 和本机公网 IPv6。交互终端中可修改端口、IPv4；有多个 IPv6 时编号选择。两个链接使用相同端口和密钥。IPv6 地址对应当前服务器，不会使用之前其他 VPS 的地址。

指定参数并跳过交互：

```bash
IPV4='66.187.4.8' PORT=10443 bash /tmp/telegram-mtproxy-install.sh --non-interactive
```

也可设置 `IPV6='本机公网IPv6'`。公网 IPv4 自动检测使用 ifconfig.co；共享出口或 NAT 环境请填入实际入口地址，并确保外部端口映射正确。没有本机公网 IPv6 会退出，不会把原服务改成不完整的双栈配置。

## 安装与迁移

- 首次安装下载官方仓库，固定源码提交 `69f2f083b57bbd94932cb9f4f32155f33e719ff1`，使用 `gcc -fcommon` 编译以兼容现代 GCC；不修改官方源码。
- 仅支持 AMD64：官方 Makefile 包含 x86 专用指令选项。
- 已存在 `/opt/telegram-mtproxy/objs/bin/mtproto-proxy` 时复用，不自动升级现有程序。已有 `client-secret` 保留，格式异常则退出。
- 运行参数采用官方的 `-6 -u nobody -p 8888 -H 端口 -S 密钥 --aes-pwd … -M 1`。`-6` 开启能接收 IPv4 的 IPv6 双栈套接字；Telegram 上游连接仍依官方配置，不强制 IPv6 出口。
- 使用官方 `getProxySecret` 和 `getProxyConfig`，不调用 GitHub API。每次运行重新获取这两份服务配置。官方建议数据中心配置定期更新，可每天重新获取；本脚本未安装定时更新任务。
- 写入配置前备份到 `/opt/telegram-mtproxy/backup.*`；启动失败尝试恢复旧配置及原先运行的服务。
- 会重写 `telegram-mtproxy.service`，迁移并备份此前聊天提供的 `dual-stack.conf`。成功切换后禁用运行中的旧 `mtproxy-ipv6.service` / `tg-python.service`。其他自定义 systemd drop-in 不改动，若存在可能影响最终服务配置。
- 中文分步进度，命令详细输出保存到 root 专属的 `/var/log/telegram-mtproxy-install.*.log`；支持 `NO_COLOR=1` 和 `--preview`（预览不安装、不联网）。

## 连接和防火墙

**放行 IPv4、IPv6 TCP 10443**（或你选择的端口），同时检查云安全组和系统防火墙。脚本不会修改任何防火墙规则。统计端口 8888 不是客户端连接端口，不需要公开。

```bash
sudo cat /opt/telegram-mtproxy/access-dual-stack.txt
systemctl status telegram-mtproxy.service
journalctl -u telegram-mtproxy.service -n 50 --no-pager
```

IPv4 和 IPv6 链接分开显示。部分 Telegram 客户端不能正确导入 IPv6 字面量链接时，可手动填入 IPv6 地址、端口及 `dd` 开头的完整密钥。IPv6 连接需要客户端具备公网 IPv6 网络。

配置和链接文件包含密钥，请勿上传仓库。安装输出的监听检查仅证明服务在本机运行，外网连通性以 Telegram 实际连接为准。

## 验证

CI 检查 Bash 语法、ShellCheck、终端预览/颜色开关、两个链接的地址及密钥格式，并在 Debian 12 和 Debian 13 容器中编译固定提交的官方源码。CI 不替代真实 VPS 的路由、防火墙及 Telegram 客户端测试。
