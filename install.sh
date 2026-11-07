#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
MTG_VERSION=v2.3.0
INTERACTIVE=0
[[ -t 0 && -t 1 && ${NONINTERACTIVE:-0} != 1 && ! ${PORT+x} && ! ${IPV6+x} && ! ${TLS_DOMAIN+x} ]] && INTERACTIVE=1
PORT=${PORT:-10443}
TLS_DOMAIN=${TLS_DOMAIN:-www.cloudflare.com}
IPV6=${IPV6:-}
BASE=/opt/mtproxy-ipv6
UNIT=mtproxy-ipv6.service
LOG_FILE=
RESET='' BLUE='' GREEN='' YELLOW='' RED='' BOLD=''
if [[ -t 1 && ${TERM:-dumb} != dumb && ! ${NO_COLOR+x} ]]; then
  RESET=$'\033[0m'; BLUE=$'\033[36m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; RED=$'\033[31m'; BOLD=$'\033[1m'
fi
line() { printf '  ──────────────────────────────────────────────\n'; }
step() { printf '\n%s  [%s/5] %s%s\n\n' "$BLUE" "$1" "$2" "$RESET"; }
ok() { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\n  %s! 注意%s  %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die() { printf '\n  %s✗ 失败%s  %s\n\n' "$RED" "$RESET" "$*" >&2; exit 1; }
show_log() {
  if [[ -n $LOG_FILE && -f $LOG_FILE ]]; then
    printf '\n  最近的详细输出：\n\n' >&2
    tail -n 12 "$LOG_FILE" >&2
    printf '\n  完整日志：%s\n\n' "$LOG_FILE" >&2
  fi
}
on_error() { local status=$1 lineno=$2; trap - ERR; show_log; die "安装在第 $lineno 行中断（退出码 $status）。"; }
trap 'on_error "$?" "$LINENO"' ERR
run() {
  local label=$1 status
  shift
  info "$label…"
  if "$@" >>"$LOG_FILE" 2>&1; then
    ok "$label"
  else
    status=$?
    show_log
    die "$label 未完成（退出码 $status）。"
  fi
}
header() {
  printf '\n%s  Telegram IPv6 代理安装%s\n' "$BOLD" "$RESET"
  printf '  Debian 12+ · mtg %s · systemd\n' "$MTG_VERSION"
  line
}
result() {
  step 5 '安装完成'
  ok '服务已启动'
  ok '本机 IPv6 端口已监听'
  info '外网连接：待 Telegram 客户端验证'
  printf '\n'; line
  printf '\n  服务器   %s\n  端口     %s\n  密钥     %s\n' "$IPV6" "$PORT" "$SECRET"
  printf '\n%s  Telegram 导入链接%s\n\n  https://t.me/proxy?server=%s&port=%s&secret=%s\n' "$BLUE" "$RESET" "${IPV6//:/%3A}" "$PORT" "$SECRET"
  warn "请在云安全组和本机防火墙放行 IPv6 TCP $PORT。"
  printf '\n'; line
  printf '\n  查看状态   systemctl status %s\n  查看日志   journalctl -u %s -n 50 --no-pager\n' "$UNIT" "$UNIT"
  printf '  连接信息   %s/access.txt\n' "$BASE"
  [[ -z $LOG_FILE ]] || printf '  安装日志   %s\n' "$LOG_FILE"
  printf '\n'
}
(( $# <= 1 )) || die '一次只能指定一个选项，请使用 --help 查看用法。'
case ${1:-} in
  --non-interactive) INTERACTIVE=0;;
  --preview)
    header
    step 1 '检查运行环境'; ok 'Debian 12 / AMD64'; ok '已检测到公网 IPv6'
    step 2 '设置连接参数'; info '监听端口：10443'; info 'IPv6 地址：2001:db8::1234（演示地址）'
    step 3 '下载并校验'; ok 'mtg 下载完成（演示）'; ok 'SHA256 校验通过（演示）'
    step 4 '配置系统服务'; ok '已设置开机启动（演示）'
    IPV6=2001:db8::1234; PORT=10443; SECRET='ee…（演示密钥）'
    warn '以下为界面预览，未执行安装或网络检查。'; result; exit 0;;
  --help|-h)
    printf '用法：bash install.sh [--non-interactive|--preview|--help]\n变量：PORT、IPV6、TLS_DOMAIN、NONINTERACTIVE=1、NO_COLOR=1\n'; exit 0;;
  '') ;;
  *) die "未知参数：$1";;
esac
header
step 1 '检查运行环境'
[[ $EUID == 0 ]] || die '请使用 root 或 sudo bash 运行。'
[[ -f /etc/os-release ]] || die '无法检测操作系统。'
. /etc/os-release
[[ ${ID:-} == debian && ${VERSION_ID%%.*} =~ ^[0-9]+$ ]] || die '仅支持 Debian 12 及以上。'
(( ${VERSION_ID%%.*} >= 12 )) || die '需要 Debian 12 及以上。'
[[ -d /run/systemd/system ]] || die '需要使用 systemd 的系统。'
ok "Debian $VERSION_ID / $(dpkg --print-architecture)"
[[ ! -e $BASE && ! -e /etc/systemd/system/$UNIT ]] || die '已安装或路径已存在；不会覆盖现有配置。'
LOG_FILE=$(mktemp /var/log/mtproxy-ipv6-install.XXXXXX.log)
chmod 600 "$LOG_FILE"
info "详细输出保存到：$LOG_FILE"
export DEBIAN_FRONTEND=noninteractive
run '更新软件源' apt-get update
run '准备安装依赖' apt-get install -y --no-install-recommends ca-certificates curl python3 iproute2 tar
command -v ss >/dev/null || die '缺少 ss。'
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
step 2 '设置连接参数'
if (( INTERACTIVE )); then
  printf '  监听端口 [%s]：' "$PORT"
  read -r answer || die '输入已中断。'
  PORT=${answer:-$PORT}
  printf '  FakeTLS 域名 [%s]：' "$TLS_DOMAIN"
  read -r answer || die '输入已中断。'
  TLS_DOMAIN=${answer:-$TLS_DOMAIN}
fi
[[ $PORT =~ ^[0-9]{5}$ ]] || die 'PORT 必须为 10001–65535。'
PORT=$((10#$PORT))
(( PORT > 10000 && PORT <= 65535 )) || die 'PORT 必须为 10001–65535。'
[[ $TLS_DOMAIN =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ && $TLS_DOMAIN == *.* ]] || die 'TLS_DOMAIN 必须是有效域名。'
[[ -z $(ss -H -ltn "sport = :$PORT") ]] || die "TCP $PORT 已被占用。"
# Enumerate once, and offer a numbered choice only on an interactive terminal.
mapfile -t ipv6_candidates < <(ip -6 -o address show scope global | awk '!/ tentative| dadfailed| deprecated/ {split($4,a,"/"); if (a[1] ~ /^[23]/) print a[1]}' | sort -u)
if (( INTERACTIVE && ${#ipv6_candidates[@]} > 1 )); then
  printf '\n  检测到多个公网 IPv6：\n'
  for i in "${!ipv6_candidates[@]}"; do info "$((i+1))) ${ipv6_candidates[$i]}"; done
  printf '\n  请选择地址 [1]：'
  read -r answer || die '输入已中断。'
  answer=${answer:-1}
  [[ $answer =~ ^[1-9][0-9]{0,3}$ ]] || die '请输入列表中的编号。'
  (( answer <= ${#ipv6_candidates[@]} )) || die '地址编号超出范围。'
  IPV6=${ipv6_candidates[$((answer-1))]}
fi
export IPV6
IPV6=$(python3 - <<'PY'
import ipaddress,json,os,subprocess,sys
items=json.loads(subprocess.check_output(['ip','-j','-6','address','show','scope','global']))
addresses=[]
for interface in items:
    for a in interface.get('addr_info',[]):
        if a.get('tentative') or a.get('dadfailed') or a.get('deprecated'): continue
        value=a.get('local','')
        if value and ipaddress.IPv6Address(value).is_global: addresses.append(value)
requested=os.environ.get('IPV6','')
if requested:
    try: requested=str(ipaddress.IPv6Address(requested))
    except ValueError: sys.exit('IPV6 格式错误。')
    if requested not in [str(ipaddress.IPv6Address(x)) for x in addresses]:
        sys.exit('指定 IPV6 不是本机已配置的公网地址。')
    print(requested)
elif addresses: print(addresses[0])
else: sys.exit('没有检测到可用公网 IPv6。')
PY
)
ok "监听地址：[$IPV6]:$PORT"
info "FakeTLS 域名：$TLS_DOMAIN"
run '检查 IPv6 HTTPS 出口' curl -6 --noproxy '*' -fsS --connect-timeout 10 --max-time 25 "https://$TLS_DOMAIN/" -o /dev/null
case $(dpkg --print-architecture) in
  amd64) arch=amd64;;
  arm64) arch=arm64;;
  *) die '仅支持 amd64 / arm64。';;
esac
step 3 '下载并校验'
# Fixed upstream release filenames avoid unauthenticated GitHub API requests.
release_base="https://github.com/9seconds/mtg/releases/download/$MTG_VERSION"
archive_name="mtg-${MTG_VERSION#v}-linux-${arch}.tar.gz"
printf '%s' "$archive_name" > "$tmp/archive-name"
run "下载 mtg $MTG_VERSION ($arch)" curl -fLsS --retry 3 --connect-timeout 15 --max-time 300 "$release_base/$archive_name" -o "$tmp/archive.tar.gz"
run '下载 SHA256 校验清单' curl -fLsS --retry 3 --connect-timeout 15 --max-time 90 "$release_base/mtg-${MTG_VERSION#v}-checksums.txt" -o "$tmp/checksums.txt"
python3 - "$tmp" <<'PY'
import hashlib,pathlib,sys,tarfile
p=pathlib.Path(sys.argv[1]); name=(p/'archive-name').read_text()
matches=[line.split()[0] for line in (p/'checksums.txt').read_text().splitlines() if len(line.split())==2 and line.split()[1].lstrip('*')==name]
actual=hashlib.sha256((p/'archive.tar.gz').read_bytes()).hexdigest()
if matches != [actual]: sys.exit('SHA256 校验失败。')
with tarfile.open(p/'archive.tar.gz') as archive:
    members=[m for m in archive.getmembers() if pathlib.PurePosixPath(m.name).name=='mtg' and m.isfile()]
    if len(members)!=1: sys.exit('压缩包中 mtg 文件不唯一。')
    (p/'mtg').write_bytes(archive.extractfile(members[0]).read())
PY
chmod 755 "$tmp/mtg"
ok 'SHA256 校验通过'
"$tmp/mtg" --version >>"$LOG_FILE" 2>&1
SECRET=$("$tmp/mtg" generate-secret --hex "$TLS_DOMAIN")
[[ $SECRET =~ ^ee[0-9a-fA-F]+$ ]] || die '生成密钥失败。'
ok '已生成独立连接密钥'
step 4 '配置系统服务'
cat > "$tmp/config.toml" <<EOF
secret = "$SECRET"
bind-to = "[$IPV6]:$PORT"
prefer-ip = "only-ipv6"
public-ipv6 = "$IPV6"
concurrency = 512
[network]
dns = ""
EOF
# Doctor also treats an SNI/public-IP mismatch as a failure. Report it
# without blocking installations using an external fronting domain.
info '运行 mtg 网络诊断…'
if "$tmp/mtg" doctor "$tmp/config.toml" >>"$LOG_FILE" 2>&1; then
  ok 'mtg 网络诊断通过'
else
  warn "mtg 诊断存在未通过项，详见 $LOG_FILE；继续安装并检查本机监听。"
fi
install -d -m 700 "$BASE"
install -m 755 "$tmp/mtg" "$BASE/mtg"
install -m 600 "$tmp/config.toml" "$BASE/config.toml"
cat > /etc/systemd/system/mtproxy-ipv6.service <<'EOF'
[Unit]
Description=IPv6-only Telegram MTProxy (mtg)
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
DynamicUser=yes
LoadCredential=config:/opt/mtproxy-ipv6/config.toml
ExecStart=/opt/mtproxy-ipv6/mtg run %d/config
Restart=always
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
RestrictAddressFamilies=AF_INET6 AF_UNIX AF_NETLINK AF_INET
CapabilityBoundingSet=
LimitNOFILE=8192
UMask=0077

[Install]
WantedBy=multi-user.target
EOF
# Executable must be traversable by the systemd dynamic user; credentials remain root-only.
chmod 711 "$BASE"
run '加载服务配置' systemctl daemon-reload
run '设置开机启动并启动服务' systemctl enable --now "$UNIT"
info '等待服务监听（最多 30 秒）…'
ready=0
for ((i=0;i<30;i++)); do
  if systemctl is-active --quiet "$UNIT" && [[ -n $(ss -H -6 -ltn "sport = :$PORT") ]]; then ready=1; break; fi
  sleep 1
done
(( ready == 1 )) || { journalctl -u "$UNIT" -n 30 --no-pager >>"$LOG_FILE" 2>&1; show_log; die '服务未就绪，请检查日志。'; }
cat > "$BASE/access.txt" <<EOF
服务器：$IPV6
端口：$PORT
密钥：$SECRET
https://t.me/proxy?server=${IPV6//:/%3A}&port=$PORT&secret=$SECRET
EOF
chmod 600 "$BASE/access.txt"
result
