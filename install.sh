#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
UPSTREAM_COMMIT=69f2f083b57bbd94932cb9f4f32155f33e719ff1
BASE=/opt/telegram-mtproxy
BINARY=$BASE/objs/bin/mtproto-proxy-ipv6-only
UNIT=telegram-mtproxy.service
UNIT_FILE=/etc/systemd/system/telegram-mtproxy.service
DROPIN=/etc/systemd/system/telegram-mtproxy.service.d/dual-stack.conf
PORT=${PORT:-10443}
IPV6=${IPV6:-}
INTERACTIVE=0
[[ -t 0 && -t 1 && ${NONINTERACTIVE:-0} != 1 ]] && INTERACTIVE=1
RESET='' BLUE='' GREEN='' YELLOW='' RED=''
if [[ -t 1 && ${TERM:-dumb} != dumb && ! ${NO_COLOR+x} ]]; then
  RESET=$'\033[0m'; BLUE=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'
fi
LOG_FILE='' tmp='' backup='' changed=0 was_active=0
stopped=()
step() { printf '\n%s  [%s/5] %s%s\n\n' "$BLUE" "$1" "$2" "$RESET"; }
ok() { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '\n  %s! 注意%s  %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die() { printf '\n  %s✗ 失败%s  %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }
run() {
  local label=$1; shift
  printf '    %s…\n' "$label"
  if "$@" >>"$LOG_FILE" 2>&1; then ok "$label"; else
    tail -n 15 "$LOG_FILE" >&2; die "$label 未完成。日志：$LOG_FILE"
  fi
}
finish() {
  local status=$?
  trap - EXIT ERR
  if (( status != 0 && changed )); then
    warn '安装未完成，正在恢复原服务配置。'
    systemctl stop "$UNIT" >>"$LOG_FILE" 2>&1 || true
    for entry in "$UNIT_FILE:unit" "$DROPIN:dropin" "$BASE/proxy-secret:proxy-secret" "$BASE/proxy-multi.conf:proxy-multi.conf"; do
      target=${entry%:*}; name=${entry##*:}
      if [[ -f $backup/$name ]]; then cp -a "$backup/$name" "$target"; else rm -f -- "$target"; fi
    done
    systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
    if (( was_active )); then systemctl start "$UNIT" >>"$LOG_FILE" 2>&1 || true; fi
    for service in "${stopped[@]}"; do systemctl start "$service" >>"$LOG_FILE" 2>&1 || true; done
    warn "配置备份：$backup；日志：$LOG_FILE"
  fi
  [[ -z $tmp ]] || rm -rf -- "$tmp"
  exit "$status"
}
trap finish EXIT
trap 'die "第 $LINENO 行失败。日志：${LOG_FILE:-尚未创建}"' ERR
header() { printf '\n  Telegram MTProxy · 仅 IPv6 接入\n  Debian 12+ · AMD64 · systemd\n  ──────────────────────────────────────────────\n'; }
patch_ipv6_listener() {
  python3 - "$1/mtproto/mtproto-proxy.c" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1])
s=p.read_text()
old='http_sfd[i] = server_socket (http_port[i], engine_state->settings_addr, engine_get_backlog (), enable_ipv6);'
new=old.replace('enable_ipv6);','enable_ipv6 | SM_IPV6_ONLY);')
if s.count(old)!=1: raise SystemExit('官方源码监听位置不匹配，停止构建。')
p.write_text(s.replace(old,new))
PY
}
links() {
  printf '\n  IPv6 链接：\n  https://t.me/proxy?server=%s&port=%s&secret=dd%s\n' "${IPV6//:/%3A}" "$PORT" "$SECRET"
}
(( $# <= 1 )) || die '一次只能指定一个选项。'
case ${1:-} in
  --help|-h) printf '用法：bash install.sh [--non-interactive|--preview|--help]\n变量：PORT=10443 IPV6=公网IPv6 NONINTERACTIVE=1 NO_COLOR=1\n'; exit 0;;
  --non-interactive) INTERACTIVE=0;;
  --preview)
    header
    step 1 '检查运行环境'; ok 'Debian 12 / AMD64（演示）'
    step 2 '设置 IPv6 入口'; ok '端口：10443（演示）'
    step 3 '准备官方程序'; ok '官方源码编译完成（演示）'
    step 4 '启动 IPv6 服务'; ok '服务已启动（演示）'
    step 5 '连接信息'; IPV6=2001:db8::1; PORT=10443; SECRET='演示密钥'
    links; warn '未执行安装或网络检查；外网连接待 Telegram 客户端验证。'; exit 0;;
  '') ;;
  *) die "未知参数：$1";;
esac
header
step 1 '检查运行环境'
[[ $EUID == 0 ]] || die '请使用 root 或 sudo bash 运行。'
. /etc/os-release
[[ ${ID:-} == debian && ${VERSION_ID%%.*} =~ ^[0-9]+$ ]] || die '仅支持 Debian 12 及以上。'
(( ${VERSION_ID%%.*} >= 12 )) || die '需要 Debian 12 及以上。'
[[ $(dpkg --print-architecture) == amd64 ]] || die '官方 Makefile 使用 x86 指令，本脚本仅支持 AMD64。'
[[ -d /run/systemd/system ]] || die '需要 systemd。'
[[ ! -L $BASE ]] || die '安装目录不能是符号链接。'
LOG_FILE=$(mktemp /var/log/telegram-mtproxy-install.XXXXXX.log)
tmp=$(mktemp -d)
ok "Debian $VERSION_ID / AMD64"
export DEBIAN_FRONTEND=noninteractive
run '更新软件源' apt-get update
run '准备编译依赖' apt-get install -y --no-install-recommends git curl build-essential libssl-dev zlib1g-dev openssl ca-certificates python3 iproute2
step 2 '设置 IPv6 入口'
mapfile -t candidates < <(ip -6 -o address show scope global | awk '$4 ~ /^[23]/ && !/ tentative| dadfailed| deprecated/ {split($4,a,"/"); print a[1]}' | sort -u)
(( ${#candidates[@]} )) || die '当前 VPS 未配置公网 IPv6；尚未修改任何服务。'
if (( INTERACTIVE )); then
  printf '  监听端口 [%s]：' "$PORT"; read -r answer || die '输入已中断。'; PORT=${answer:-$PORT}
  if [[ -z $IPV6 ]] && (( ${#candidates[@]} > 1 )); then
    printf '\n  可用 IPv6：\n'
    for i in "${!candidates[@]}"; do printf '    %s) %s\n' "$((i+1))" "${candidates[$i]}"; done
    printf '  选择编号 [1]：'; read -r answer || die '输入已中断。'; answer=${answer:-1}
    [[ $answer =~ ^[1-9][0-9]{0,3}$ ]] || die '地址编号不合法。'
    (( answer <= ${#candidates[@]} )) || die '地址编号超出范围。'
    IPV6=${candidates[$((answer-1))]}
  fi
fi
IPV6=${IPV6:-${candidates[0]}}
[[ $PORT =~ ^[0-9]{5}$ ]] || die '端口须为 10001–65535。'
PORT=$((10#$PORT))
(( PORT > 10000 && PORT <= 65535 )) || die '端口须为 10001–65535。'
export IPV6
python3 - <<'PY'
import ipaddress,json,os,subprocess
v6=ipaddress.IPv6Address(os.environ['IPV6'])
if not v6.is_global: raise SystemExit('必须使用公网 IPv6。')
interfaces=json.loads(subprocess.check_output(['ip','-j','-6','addr','show','scope','global']))
local=[ipaddress.IPv6Address(a['local']) for i in interfaces for a in i.get('addr_info',[]) if a.get('local')]
if v6 not in local: raise SystemExit('指定的 IPv6 未配置在本机。')
PY
ok "IPv6：$IPV6；端口：$PORT"
step 3 '准备官方程序'
if [[ -x $BINARY && -f $BASE/ipv6-only-build && $(cat "$BASE/ipv6-only-build") == "$UPSTREAM_COMMIT:listener-v1" ]]; then
  ok '复用已验证标记的 IPv6 专用程序'
else
  run '下载 Telegram 官方源码' git clone --no-checkout https://github.com/TelegramMessenger/MTProxy.git "$tmp/source"
  run '固定上游版本' git -C "$tmp/source" checkout --detach "$UPSTREAM_COMMIT"
  run '将客户端套接字限制为 IPv6' patch_ipv6_listener "$tmp/source"
  run '编译官方程序' make -C "$tmp/source" -j2 CC='gcc -fcommon'
fi
run '下载 Telegram 服务密钥' curl -fLsS --retry 3 --connect-timeout 15 --max-time 90 https://core.telegram.org/getProxySecret -o "$tmp/proxy-secret"
run '下载 Telegram 数据中心配置' curl -fLsS --retry 3 --connect-timeout 15 --max-time 90 https://core.telegram.org/getProxyConfig -o "$tmp/proxy-multi.conf"
[[ -s $tmp/proxy-secret && -s $tmp/proxy-multi.conf ]] || die '下载配置为空。'
install -d -m 755 "$BASE"
if [[ -x $tmp/source/objs/bin/mtproto-proxy ]]; then
  install -d -m 755 "$BASE/objs/bin"
  install -m 755 "$tmp/source/objs/bin/mtproto-proxy" "$BINARY"
  printf '%s\n' "$UPSTREAM_COMMIT:listener-v1" > "$BASE/ipv6-only-build"
fi
if [[ -f $BASE/client-secret ]]; then SECRET=$(cat "$BASE/client-secret"); else SECRET=$(openssl rand -hex 16); fi
[[ $SECRET =~ ^[0-9a-fA-F]{32}$ ]] || die '现有 client-secret 格式错误，不会覆盖。'
printf '%s\n' "$SECRET" > "$BASE/client-secret"
chmod 600 "$BASE/client-secret"
step 4 '启动 IPv6 服务'
backup=$(mktemp -d "$BASE/backup.XXXXXX")
for entry in "$UNIT_FILE:unit" "$DROPIN:dropin" "$BASE/proxy-secret:proxy-secret" "$BASE/proxy-multi.conf:proxy-multi.conf"; do
  target=${entry%:*}; name=${entry##*:}; [[ ! -f $target ]] || cp -a "$target" "$backup/$name"
done
if systemctl is-active --quiet "$UNIT"; then was_active=1; fi
changed=1
install -m 644 "$tmp/proxy-secret" "$BASE/proxy-secret"
install -m 644 "$tmp/proxy-multi.conf" "$BASE/proxy-multi.conf"
# Migrate the exact dual-stack override previously supplied in chat.
rm -f -- "$DROPIN"
cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Telegram MTProxy (IPv6-only listener)
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$BASE
ExecStart=$BINARY -6 -u nobody -p 8888 -H $PORT -S $SECRET --aes-pwd $BASE/proxy-secret $BASE/proxy-multi.conf -M 1
Restart=on-failure
RestartSec=5
LimitNOFILE=131072

[Install]
WantedBy=multi-user.target
EOF
chmod 600 "$UNIT_FILE"
for service in mtproxy-ipv6.service tg-python.service; do
  if systemctl is-active --quiet "$service"; then stopped+=("$service"); run "停止旧服务 $service" systemctl stop "$service"; fi
done
run '加载服务配置' systemctl daemon-reload
run '启动 IPv6 代理' systemctl restart "$UNIT"
ready=0
for ((i=0;i<15;i++)); do
  if systemctl is-active --quiet "$UNIT" && [[ -n $(ss -H -6 -ltn "sport = :$PORT") ]]; then ready=1; break; fi
  sleep 1
done
if (( ! ready )); then journalctl -u "$UNIT" -n 40 --no-pager >>"$LOG_FILE" 2>&1; tail -n 20 "$LOG_FILE" >&2; die '服务未就绪，将尝试恢复原服务。'; fi
run '设置开机启动' systemctl enable "$UNIT"
for service in "${stopped[@]}"; do run "禁用旧服务 $service 的开机启动" systemctl disable "$service"; done
python3 - "$PORT" <<'PY'
import socket,sys
try:
    with socket.create_connection(('127.0.0.1',int(sys.argv[1])),timeout=2): pass
except ConnectionRefusedError: pass
else: raise SystemExit('IPv4 本机连接仍能成功，停止切换并恢复原配置。')
PY
links > "$BASE/access-ipv6.txt"
chmod 600 "$BASE/access-ipv6.txt"
changed=0
step 5 '连接信息'
ok 'IPv6 已监听，IPv4 回环连接已拒绝'
links
warn "请放行 IPv6 TCP $PORT；原 IPv4 入口已关闭，外网连接待 Telegram 客户端验证。"
printf '\n  连接信息：%s/access-ipv6.txt\n  安装日志：%s\n  配置备份：%s\n' "$BASE" "$LOG_FILE" "$backup"
printf '\n  查看状态：systemctl status %s\n  查看日志：journalctl -u %s -n 50 --no-pager\n\n' "$UNIT" "$UNIT"
