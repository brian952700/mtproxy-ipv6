#!/usr/bin/env bash
# Exercise the public preview/help interfaces without root or system mutations.
set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
NO_COLOR=1 bash install.sh --preview >"$tmp/preview" 2>&1
for marker in '[1/5]' '[2/5]' '[3/5]' '[4/5]' '[5/5]' '10443' '待 Telegram 客户端验证' '未执行安装或网络检查'; do
  grep -Fq "$marker" "$tmp/preview"
done
if grep -q $'\033' "$tmp/preview"; then
  echo 'Redirected preview unexpectedly contains ANSI escapes' >&2
  exit 1
fi
bash install.sh --help >"$tmp/help"
grep -Fq -- '--non-interactive' "$tmp/help"
if bash install.sh --unknown >"$tmp/error" 2>&1; then
  echo 'Unknown option unexpectedly succeeded' >&2
  exit 1
fi
grep -Fq '未知参数' "$tmp/error"
# Verify real terminal coloring and the explicit NO_COLOR override.
env -u NO_COLOR TERM=xterm script -q -c 'bash install.sh --preview' "$tmp/color" >/dev/null
grep -q $'\033\[36m' "$tmp/color"
NO_COLOR=1 TERM=xterm script -q -c 'bash install.sh --preview' "$tmp/plain" >/dev/null
if grep -q $'\033' "$tmp/plain"; then
  echo 'NO_COLOR was ignored on a terminal' >&2
  exit 1
fi
# Exercise the actual link formatter without installation or privileges.
awk 'index($0,"[[ $EUID") == 1 {exit} {print}' install.sh >"$tmp/links.sh"
cat >>"$tmp/links.sh" <<'EOF'
IPV6=2602:f506:81::1
PORT=20000
SECRET=0123456789abcdef0123456789abcdef
links
EOF
bash "$tmp/links.sh" >"$tmp/links"
grep -Fxq '  https://t.me/proxy?server=2602%3Af506%3A81%3A%3A1&port=20000&secret=dd0123456789abcdef0123456789abcdef' "$tmp/links"
if grep -Fq 'IPv4 链接' "$tmp/links"; then exit 1; fi
printf 'Preview, help, terminal colors and IPv6-only link passed.\n'
