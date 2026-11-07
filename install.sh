#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
UPSTREAM_COMMIT=69f2f083b57bbd94932cb9f4f32155f33e719ff1
BASE=/opt/telegram-mtproxy
BINARY=$BASE/objs/bin/mtproto-proxy
UNIT=telegram-mtproxy.service
UNIT_FILE=/etc/systemd/system/telegram-mtproxy.service
DROPIN=/etc/systemd/system/telegram-mtproxy.service.d/dual-stack.conf
PORT=${PORT:-38503}
IPV4=${IPV4:-}
INTERACTIVE=0
[[ -t 0 && -t 1 && ${NONINTERACTIVE:-0} != 1 ]] && INTERACTIVE=1
RESET='' BLUE='' GREEN='' YELLOW='' RED=''
if [[ -t 1 && ${TERM:-dumb} != dumb && ! ${NO_COLOR+x} ]]; then
  RESET=$'\033[0m'; BLUE=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'
fi
LOG_FILE='' tmp='' backup='' changed=0 was_active=0
stopped=()
init=systemd
service_action() {
  local action=$1 service=${2%.service}
  if [[ $init == openrc ]]; then
    rc-service "$service" "$action"
  elif [[ $action == status ]]; then
    systemctl is-active --quiet "$service.service"
  else
    systemctl "$action" "$service.service"
  fi
}
reload_services() {
  if [[ $init == systemd ]]; then systemctl daemon-reload; fi
}
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
    service_action stop "$UNIT" >>"$LOG_FILE" 2>&1 || true
    for entry in "$UNIT_FILE:unit" "$DROPIN:dropin" "$BASE/proxy-secret:proxy-secret" "$BASE/proxy-multi.conf:proxy-multi.conf"; do
      target=${entry%:*}; name=${entry##*:}
      if [[ -f $backup/$name ]]; then cp -a "$backup/$name" "$target"; else rm -f -- "$target"; fi
    done
    reload_services >>"$LOG_FILE" 2>&1 || true
    if (( was_active )); then service_action start "$UNIT" >>"$LOG_FILE" 2>&1 || true; fi
    for service in "${stopped[@]}"; do service_action start "$service" >>"$LOG_FILE" 2>&1 || true; done
    warn "配置备份：$backup；日志：$LOG_FILE"
  fi
  [[ -z $tmp ]] || rm -rf -- "$tmp"
  exit "$status"
}
trap finish EXIT
trap 'die "第 $LINENO 行失败。日志：${LOG_FILE:-尚未创建}"' ERR
header() { printf '\n  Telegram MTProxy · 仅 IPv4 接入\n  Debian 12+ / Alpine 3.22+ · x86_64\n  ──────────────────────────────────────────────\n'; }
prepare_musl_source() {
  sed -i '/^#include <execinfo.h>/d; /  void \*buffer\[64\];/,/  kwrite (2, "-------------------------------/d' "$1/common/server-functions.c"
  sed -i 's/struct drand48_data rand_data;/unsigned short rand_data[3];/' "$1/jobs/jobs.h"
  sed -i \
    -e 's/lrand48_r (\&this_job_thread->rand_data, \&t);/t = nrand48 (this_job_thread->rand_data);/' \
    -e 's/mrand48_r (\&this_job_thread->rand_data, \&t);/t = jrand48 (this_job_thread->rand_data);/' \
    -e 's/drand48_r (\&this_job_thread->rand_data, \&t);/t = erand48 (this_job_thread->rand_data);/' \
    -e 's/srand48_r (rdtsc () \^ lrand48 (), \&JT->rand_data);/unsigned long long seed = rdtsc () ^ lrand48 ();\n  JT->rand_data[0] = 0x330e;\n  JT->rand_data[1] = seed;\n  JT->rand_data[2] = seed >> 16;/' \
    "$1/jobs/jobs.c"
}
links() {
  printf '\n  IPv4 链接：\n  https://t.me/proxy?server=%s&port=%s&secret=dd%s\n' "$IPV4" "$PORT" "$SECRET"
}
(( $# <= 1 )) || die '一次只能指定一个选项。'
case ${1:-} in
  --help|-h) printf '用法：bash install.sh [--non-interactive|--preview|--help]\n变量：PORT=38503 IPV4=公网IPv4 NONINTERACTIVE=1 NO_COLOR=1\n'; exit 0;;
  --non-interactive) INTERACTIVE=0;;
  --preview)
    header
    step 1 '检查运行环境'; ok 'Debian 12 / AMD64（演示）'
    step 2 '设置 IPv4 入口'; ok '端口：38503（演示）'
    step 3 '准备官方程序'; ok '官方源码编译完成（演示）'
    step 4 '启动 IPv4 服务'; ok '服务已启动（演示）'
    step 5 '连接信息'; IPV4=192.0.2.1; PORT=38503; SECRET='演示密钥'
    links; warn '未执行安装或网络检查；外网连接待 Telegram 客户端验证。'; exit 0;;
  '') ;;
  *) die "未知参数：$1";;
esac
header
step 1 '检查运行环境'
[[ $EUID == 0 ]] || die '请使用 root 或 sudo bash 运行。'
. /etc/os-release
[[ $(uname -m) == x86_64 ]] || die '仅支持 x86_64。'
case ${ID:-} in
  debian)
    (( ${VERSION_ID%%.*} >= 12 )) || die '需要 Debian 12 及以上。'
    [[ -d /run/systemd/system ]] || die '需要 systemd。'
    ;;
  alpine)
    [[ $VERSION_ID =~ ^3\.([0-9]+)(\.|$) && ${BASH_REMATCH[1]} -ge 22 ]] || die '需要 Alpine 3.22 或更新的 3.x。'
    command -v rc-service >/dev/null && command -v rc-update >/dev/null || die '需要 OpenRC。'
    init=openrc
    UNIT=telegram-mtproxy
    UNIT_FILE=/etc/init.d/telegram-mtproxy
    ;;
  *) die '仅支持 Debian 和 Alpine。';;
esac
[[ ! -L $BASE ]] || die '安装目录不能是符号链接。'
LOG_FILE=$(mktemp /var/log/telegram-mtproxy-install.XXXXXX.log)
tmp=$(mktemp -d)
ok "$ID $VERSION_ID / x86_64"
if [[ $init == openrc ]]; then
  run '准备 Alpine 编译依赖' apk add --no-cache bash git curl build-base linux-headers openssl-dev zlib-dev openssl ca-certificates python3 iproute2
else
  export DEBIAN_FRONTEND=noninteractive
run '更新软件源' apt-get update
run '准备编译依赖' apt-get install -y --no-install-recommends git curl build-essential libssl-dev zlib1g-dev openssl ca-certificates python3 iproute2
fi
step 2 '设置 IPv4 入口'
if [[ -z $IPV4 ]]; then
  IPV4=$(curl -4 -fLsS --connect-timeout 10 --max-time 20 https://ifconfig.co/ip 2>>"$LOG_FILE") || die '请通过 IPV4 指定公网地址。'
fi
if (( INTERACTIVE )); then
  printf '  监听端口 [%s]：' "$PORT"; read -r answer || die '输入已中断。'; PORT=${answer:-$PORT}
  printf '  公网 IPv4 [%s]：' "$IPV4"; read -r answer || die '输入已中断。'; IPV4=${answer:-$IPV4}
fi
[[ $PORT =~ ^[0-9]{5}$ ]] || die '端口须为 10001–65535。'
PORT=$((10#$PORT))
(( PORT > 10000 && PORT <= 65535 )) || die '端口须为 10001–65535。'
python3 - "$IPV4" <<'PY'
import ipaddress,sys
if not ipaddress.IPv4Address(sys.argv[1]).is_global:
    raise SystemExit('请输入公网 IPv4。')
PY
ok "IPv4：$IPV4；端口：$PORT"
step 3 '准备官方程序'
if [[ -x $BINARY ]]; then
  ok '复用现有官方 MTProxy 程序'
else
  run '下载 Telegram 官方源码' git clone --no-checkout https://github.com/TelegramMessenger/MTProxy.git "$tmp/source"
  run '固定上游版本' git -C "$tmp/source" checkout --detach "$UPSTREAM_COMMIT"
  if [[ $init == openrc ]]; then
    # musl does not provide the glibc stack backtrace interface.
    prepare_musl_source "$tmp/source"
  fi
  run '编译官方程序' make -C "$tmp/source" -j2 CC='gcc -fcommon'
fi
run '下载 Telegram 服务密钥' curl -fLsS --retry 3 --connect-timeout 15 --max-time 90 https://core.telegram.org/getProxySecret -o "$tmp/proxy-secret"
run '下载 Telegram 数据中心配置' curl -fLsS --retry 3 --connect-timeout 15 --max-time 90 https://core.telegram.org/getProxyConfig -o "$tmp/proxy-multi.conf"
[[ -s $tmp/proxy-secret && -s $tmp/proxy-multi.conf ]] || die '下载配置为空。'
install -d -m 755 "$BASE"
if [[ -x $tmp/source/objs/bin/mtproto-proxy ]]; then
  install -d -m 755 "$BASE/objs/bin"
  install -m 755 "$tmp/source/objs/bin/mtproto-proxy" "$BINARY"
  printf '%s\n' "$UPSTREAM_COMMIT" > "$BASE/upstream-commit"
fi
if [[ -f $BASE/client-secret ]]; then SECRET=$(cat "$BASE/client-secret"); else SECRET=$(openssl rand -hex 16); fi
[[ $SECRET =~ ^[0-9a-fA-F]{32}$ ]] || die '现有 client-secret 格式错误，不会覆盖。'
printf '%s\n' "$SECRET" > "$BASE/client-secret"
chmod 600 "$BASE/client-secret"
step 4 '启动 IPv4 服务'
backup=$(mktemp -d "$BASE/backup.XXXXXX")
for entry in "$UNIT_FILE:unit" "$DROPIN:dropin" "$BASE/proxy-secret:proxy-secret" "$BASE/proxy-multi.conf:proxy-multi.conf"; do
  target=${entry%:*}; name=${entry##*:}; [[ ! -f $target ]] || cp -a "$target" "$backup/$name"
done
if service_action status "$UNIT"; then was_active=1; fi
changed=1
install -m 644 "$tmp/proxy-secret" "$BASE/proxy-secret"
install -m 644 "$tmp/proxy-multi.conf" "$BASE/proxy-multi.conf"
# Migrate the exact dual-stack override previously supplied in chat.
if [[ $init == systemd ]]; then rm -f -- "$DROPIN"; fi
if [[ $init == openrc ]]; then
  cat > "$UNIT_FILE" <<EOF
#!/sbin/openrc-run
description="Telegram MTProxy (IPv4-only listener)"
supervisor=supervise-daemon
command="$BINARY"
command_args="-u nobody -p 8888 -H $PORT -S $SECRET --aes-pwd $BASE/proxy-secret $BASE/proxy-multi.conf -M 1"
directory="$BASE"
rc_ulimit="-n 131072"
respawn_delay=5
output_log="/var/log/telegram-mtproxy.log"
error_log="/var/log/telegram-mtproxy.log"
depend() { need net; }
EOF
  chmod 700 "$UNIT_FILE"
else
cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Telegram MTProxy (IPv4-only listener)
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$BASE
ExecStart=$BINARY -u nobody -p 8888 -H $PORT -S $SECRET --aes-pwd $BASE/proxy-secret $BASE/proxy-multi.conf -M 1
Restart=on-failure
RestartSec=5
LimitNOFILE=131072

[Install]
WantedBy=multi-user.target
EOF
chmod 600 "$UNIT_FILE"
fi
for service in mtproxy-ipv6.service tg-python.service; do
  if service_action status "$service"; then stopped+=("$service"); run "停止旧服务 $service" service_action stop "$service"; fi
done
run '加载服务配置' reload_services
run '启动 IPv4 代理' service_action restart "$UNIT"
ready=0
for ((i=0;i<15;i++)); do
  if service_action status "$UNIT" && [[ -n $(ss -H -4 -ltn "sport = :$PORT") ]]; then ready=1; break; fi
  sleep 1
done
if (( ! ready )); then
  if [[ $init == openrc ]]; then tail -n 40 /var/log/telegram-mtproxy.log >>"$LOG_FILE" 2>&1 || true; else journalctl -u "$UNIT" -n 40 --no-pager >>"$LOG_FILE" 2>&1 || true; fi
  tail -n 20 "$LOG_FILE" >&2; die '服务未就绪，将尝试恢复原服务。'; fi
if [[ $init == openrc ]]; then
  run '设置开机启动' rc-update add "$UNIT" default
else
  run '设置开机启动' systemctl enable "$UNIT"
  for service in "${stopped[@]}"; do run "禁用旧服务 $service 的开机启动" systemctl disable "$service"; done
fi
links > "$BASE/access-ipv4.txt"
chmod 600 "$BASE/access-ipv4.txt"
changed=0
step 5 '连接信息'
ok 'IPv4 已监听'
links
warn "请放行 IPv4 TCP $PORT，外网连接待 Telegram 客户端验证。"
printf '\n  连接信息：%s/access-ipv4.txt\n  安装日志：%s\n  配置备份：%s\n' "$BASE" "$LOG_FILE" "$backup"
if [[ $init == openrc ]]; then
  printf '\n  查看状态：rc-service %s status\n  查看日志：tail -n 50 /var/log/telegram-mtproxy.log\n' "$UNIT"
else
  printf '\n  查看状态：systemctl status %s\n  查看日志：journalctl -u %s -n 50 --no-pager\n\n' "$UNIT" "$UNIT"
fi
