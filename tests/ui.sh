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
# Reproduce Debian's VERSION assignment and execute the real release-download
# command with a harmless run stub. No downloads, root or system writes needed.
printf 'ID=debian\nVERSION_ID=12\nVERSION="12 (bookworm)"\n' >"$tmp/os-release"
awk 'index($0,"[[ $EUID") == 1 {exit} {print}' install.sh >"$tmp/version-check.sh"
cat >>"$tmp/version-check.sh" <<'EOF'
tmp=$1
. "$tmp/os-release"
run() { printf '%s\n' "$@"; }
EOF
awk 'index($0,"run ")==1 && index($0,"api.github.com/repos/9seconds/mtg/releases/tags/") {print}' install.sh >>"$tmp/version-check.sh"
bash "$tmp/version-check.sh" "$tmp" >"$tmp/release-request"
grep -Fxq 'https://api.github.com/repos/9seconds/mtg/releases/tags/v2.3.0' "$tmp/release-request"
printf 'Preview, help, invalid options, terminal colors, NO_COLOR and Debian release URL regression passed.\n'
