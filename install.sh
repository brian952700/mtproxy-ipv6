#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
VERSION=v2.3.0
PORT=${PORT:-10443}
TLS_DOMAIN=${TLS_DOMAIN:-www.cloudflare.com}
IPV6=${IPV6:-}
BASE=/opt/mtproxy-ipv6
UNIT=mtproxy-ipv6.service
die() { printf '错误：%s\n' "$*" >&2; exit 1; }
trap 'printf "安装失败（第 %s 行），请检查上方错误。\n" "$LINENO" >&2' ERR
[[ $EUID == 0 ]] || die '请使用 root 或 sudo bash 运行。'
[[ -f /etc/os-release ]] || die '无法检测操作系统。'
. /etc/os-release
[[ ${ID:-} == debian && ${VERSION_ID%%.*} =~ ^[0-9]+$ ]] || die '仅支持 Debian 12 及以上。'
(( ${VERSION_ID%%.*} >= 12 )) || die '需要 Debian 12 及以上。'
[[ -d /run/systemd/system ]] || die '需要使用 systemd 的系统。'
[[ $PORT =~ ^[0-9]{5}$ ]] || die 'PORT 必须为 10001–65535。'
PORT=$((10#$PORT))
(( PORT > 10000 && PORT <= 65535 )) || die 'PORT 必须为 10001–65535。'
[[ $TLS_DOMAIN =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ && $TLS_DOMAIN == *.* ]] || die 'TLS_DOMAIN 必须是有效域名。'
[[ ! -e $BASE && ! -e /etc/systemd/system/$UNIT ]] || die '已安装或路径已存在；不会覆盖现有配置。'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl python3 iproute2 tar
command -v ss >/dev/null || die '缺少 ss。'
[[ -z $(ss -H -ltn "sport = :$PORT") ]] || die "TCP $PORT 已被占用。"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
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
curl -6 --noproxy '*' -fsS --connect-timeout 10 --max-time 25 "https://$TLS_DOMAIN/" -o /dev/null || die 'IPv6 HTTPS 出口或伪装域名不可用；可设置 TLS_DOMAIN。'
case $(dpkg --print-architecture) in
  amd64) arch=amd64;;
  arm64) arch=arm64;;
  *) die '仅支持 amd64 / arm64。';;
esac
printf '下载 mtg %s (%s)…\n' "$VERSION" "$arch"
curl -fLsS --retry 3 --connect-timeout 15 --max-time 90 "https://api.github.com/repos/9seconds/mtg/releases/tags/$VERSION" -o "$tmp/release.json"
python3 - "$tmp/release.json" "$arch" "$tmp" <<'PY'
import json,pathlib,sys
release=json.load(open(sys.argv[1]))
arch=sys.argv[2]; root=pathlib.Path(sys.argv[3])
assets=release['assets']
def choose(predicate):
    found=[a for a in assets if predicate(a['name'].lower())]
    if len(found)!=1: sys.exit('无法唯一匹配官方发布附件，请检查发布格式。')
    return found[0]
binary=choose(lambda n: n.endswith('-linux-'+arch+'.tar.gz'))
checks=choose(lambda n: 'checksum' in n and n.endswith('.txt'))
for key,value in [('archive-url',binary['browser_download_url']),('archive-name',binary['name']),('checks-url',checks['browser_download_url'])]:
    (root/key).write_text(value)
PY
curl -fLsS --retry 3 --connect-timeout 15 --max-time 300 "$(cat "$tmp/archive-url")" -o "$tmp/archive.tar.gz"
curl -fLsS --retry 3 --connect-timeout 15 --max-time 90 "$(cat "$tmp/checks-url")" -o "$tmp/checksums.txt"
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
"$tmp/mtg" --version
SECRET=$("$tmp/mtg" generate-secret --hex "$TLS_DOMAIN")
[[ $SECRET =~ ^ee[0-9a-fA-F]+$ ]] || die '生成密钥失败。'
cat > "$tmp/config.toml" <<EOF
secret = "$SECRET"
bind-to = "[$IPV6]:$PORT"
prefer-ip = "only-ipv6"
public-ipv6 = "$IPV6"
concurrency = 512
[network]
dns = ""
EOF
# Validate connectivity before touching the service installation.
"$tmp/mtg" doctor "$tmp/config.toml" || die 'mtg 网络诊断未通过，尚未安装服务。'
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
systemctl daemon-reload
systemctl enable --now "$UNIT"
ready=0
for ((i=0;i<30;i++)); do
  if systemctl is-active --quiet "$UNIT" && [[ -n $(ss -H -6 -ltn "sport = :$PORT") ]]; then ready=1; break; fi
  sleep 1
done
(( ready == 1 )) || { journalctl -u "$UNIT" -n 30 --no-pager; die '服务未就绪，请检查日志。'; }
cat > "$BASE/access.txt" <<EOF
服务器：$IPV6
端口：$PORT
密钥：$SECRET
https://t.me/proxy?server=${IPV6//:/%3A}&port=$PORT&secret=$SECRET
EOF
chmod 600 "$BASE/access.txt"
printf '\n安装完成。请在云安全组和本机防火墙放行 IPv6 TCP %s。\n' "$PORT"
printf '脚本不修改防火墙；服务监听成功不代表外网可达。\n'
cat "$BASE/access.txt"
printf '\n状态：systemctl status %s\n日志：journalctl -u %s -n 50 --no-pager\n' "$UNIT" "$UNIT"
