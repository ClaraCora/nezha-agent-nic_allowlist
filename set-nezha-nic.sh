#!/usr/bin/env bash
set -euo pipefail

# ===== Styleful logging =====
C_RESET="\033[0m"; C_DIM="\033[2m"; C_BOLD="\033[1m"
C_BLUE="\033[34m"; C_GREEN="\033[32m"; C_YELLOW="\033[33m"; C_RED="\033[31m"
icon_info="ℹ"; icon_ok="✔"; icon_warn="⚠"; icon_err="✖"

log()  { printf "%b[%s]%b %b%s%b\n" "$C_DIM" "$(date '+%F %T')" "$C_RESET" "$1" "$2" "$C_RESET"; }
info() { log "$C_BLUE$icon_info$C_RESET" "$*"; }
ok()   { log "$C_GREEN$icon_ok$C_RESET"  "$*"; }
warn() { log "$C_YELLOW$icon_warn$C_RESET" "$*"; }
err()  { log "$C_RED$icon_err$C_RESET" "$*"; }

banner() {
  printf "\n%b%s%b\n" "$C_BOLD" "═══ 哪吒 Agent 网卡自动配置 ═══" "$C_RESET"
}

# ===== Config =====
CFG="/opt/nezha/agent/config.yml"
SERVICE="nezha-agent"

# ===== Preconditions =====
banner
if [ "$(id -u)" -ne 0 ]; then err "请用 root 运行"; exit 1; fi
if [ ! -f "$CFG" ]; then err "找不到配置文件: $CFG"; exit 1; fi
ok "前置检查通过"

backup="${CFG}.$(date +%Y%m%d-%H%M%S).bak"
cp -a "$CFG" "$backup"
info "已创建备份: $backup"

# ===== Helper: list eligible ifaces =====
eligible_ifaces() {
  ip -o link show | awk -F': ' '{print $2}' \
  | sed 's/@.*//' \
  | grep -Ev '^(lo|docker[0-9]*|veth|br-|tun|tap|tailscale|wg|zerotier|zt|virbr|vmnet|macvtap|ifb|sit|gre|bond|team|bridge|podman|cni|flannel|kube|pkt|rmnet)'
}

# ===== Detect primary interface =====
primary_iface=""

if ip -4 route get 1.1.1.1 >/dev/null 2>&1; then
  cand=$(ip -4 route get 1.1.1.1 | awk '/dev/{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')
  if [ -n "$cand" ]; then
    primary_iface="$cand"
    ok "通过 IPv4 默认路由检测主网卡: $primary_iface"
  fi
else
  warn "IPv4 路由检测失败，尝试 IPv6"
fi

if [ -z "$primary_iface" ] && ip -6 route get 2001:4860:4860::8888 >/dev/null 2>&1; then
  cand=$(ip -6 route get 2001:4860:4860::8888 | awk '/dev/{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')
  if [ -n "$cand" ]; then
    primary_iface="$cand"
    ok "通过 IPv6 默认路由检测主网卡: $primary_iface"
  fi
fi

if [ -z "$primary_iface" ]; then
  warn "未从默认路由获取主网卡，使用候选列表兜底"
  mapfile -t list < <(eligible_ifaces || true)
  if [ "${#list[@]}" -eq 0 ]; then err "未检测到可用网卡"; exit 2; fi
  info "候选网卡: ${list[*]}"
  primary_iface="${list[0]}"
  ok "选择首个可用网卡: $primary_iface"
fi

# ===== Remove existing nic_allowlist block safely =====
tmp="$(mktemp)"
awk '
  BEGIN{skip=0}
  /^nic_allowlist:[[:space:]]*$/ { skip=1; next }
  skip==1 && /^[^[:space:]]/ { skip=0 }     # hit next top-level key
  skip==0 { print }
' "$CFG" > "$tmp"

# 修正：若上面命中了“下一顶级键”，那一行未被打印。再跑一次把第一行补回。
# 做法：如果原文件含 nic_allowlist，且新文件第一行不是顶级键，则从原始文件定位顶级键并合并。
if grep -qE '^nic_allowlist:[[:space:]]*$' "$CFG"; then
  # 重新构造，确保不会丢失下一顶级键
  awk '
    BEGIN{skip=0}
    /^nic_allowlist:[[:space:]]*$/ { skip=1; next }
    skip==1 && /^[^[:space:]]/ { skip=0; print }   # 打印当前行
    skip==0 { print }
  ' "$CFG" > "$tmp"
fi

mv "$tmp" "$CFG"
ok "已清理旧的 nic_allowlist 块（如存在）"

# ===== Append new allowlist =====
{
  echo ""
  echo "nic_allowlist:"
  printf "  %s: true # 自动检测的主网卡\n" "$primary_iface"
} >> "$CFG"

info "即将写入内容预览："
printf "%b\n" "$C_DIM---\nnic_allowlist:\n  ${primary_iface}: true\n---$C_RESET"

ok "写入完成: $CFG"

# ===== Restart service =====
restart_ok=false
if command -v systemctl >/dev/null 2>&1; then
  info "使用 systemd 重启服务: ${SERVICE}"
  if systemctl daemon-reload >/dev/null 2>&1; then :; fi
  if systemctl restart "${SERVICE}" >/dev/null 2>&1; then
    restart_ok=true
  else
    warn "systemctl restart 失败，尝试 service 命令"
  fi
fi

if [ "$restart_ok" = false ]; then
  if command -v service >/dev/null 2>&1; then
    if service "${SERVICE}" restart >/dev/null 2>&1; then
      restart_ok=true
    fi
  fi
fi

if [ "$restart_ok" = true ]; then
  ok "服务已重启: ${SERVICE}"
  # 可选：检查状态但不冗长
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active --quiet "${SERVICE}" && ok "服务状态: active"
  fi
else
  err "无法自动重启服务，请手动重启: systemctl restart ${SERVICE}"
  exit 3
fi

ok "完成。备份文件: $backup  主网卡: $primary_iface"
