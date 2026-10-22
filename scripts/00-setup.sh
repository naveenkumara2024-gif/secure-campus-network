#!/usr/bin/env bash
# scripts/00-setup.sh - re-runnable host setup for the campus lab.
# Run inside WSL2 Ubuntu:  make setup   (or: sudo bash scripts/00-setup.sh)
#
# Installs native Docker Engine + Containerlab + host tools and loads the kernel
# modules the lab needs. Safe to run any number of times.
set -euo pipefail

SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
say()  { printf '\033[1;36m[setup]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[setup] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# User who should be able to run `docker` without sudo.
target_user="${SUDO_USER:-}"
[ -z "$target_user" ] && [ "$(id -u)" -ne 0 ] && target_user="$USER"
[ -z "$target_user" ] && target_user="$(awk -F= '/^[[:space:]]*default[[:space:]]*=/{gsub(/[[:space:]]/,"",$2);print $2}' /etc/wsl.conf 2>/dev/null || true)"

# ---------------------------------------------------------------------------
# 1. Docker Engine, native inside this WSL distro.
#    Containerlab must reach every container's network namespace. Docker
#    Desktop's WSL integration runs containers in a separate VM where those
#    namespaces are not visible, so Desktop integration must be OFF for this
#    distro (see https://containerlab.dev/windows/).
# ---------------------------------------------------------------------------
docker_bin=""
for d in /usr/bin/docker /usr/local/bin/docker; do
  [ -e "$d" ] || continue
  case "$(readlink -f "$d")" in
    /mnt/wsl/docker-desktop*|/mnt/*)
      die "Docker Desktop WSL integration is enabled for this distro. Turn it off in
       Docker Desktop > Settings > Resources > WSL integration, then re-run this script." ;;
  esac
  docker_bin="$d"; break
done
# (A docker.exe shim from the Windows PATH under /mnt/c is ignored: it cannot drive Linux netns.)
if [ -z "$docker_bin" ]; then
  say "installing native Docker Engine (docker.io) ..."
  $SUDO apt-get update -qq
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io docker-buildx
fi
if [ "$(ps -p 1 -o comm= 2>/dev/null)" = systemd ]; then
  $SUDO systemctl enable --now docker >/dev/null 2>&1 || $SUDO systemctl start docker
else
  $SUDO service docker start || true
fi
if [ -n "$target_user" ] && [ "$target_user" != root ] && id "$target_user" >/dev/null 2>&1; then
  if ! id -nG "$target_user" | tr ' ' '\n' | grep -qx docker; then
    $SUDO usermod -aG docker "$target_user"
    say "added $target_user to the docker group (open a new WSL shell for it to apply)"
  fi
fi

# ---------------------------------------------------------------------------
# 2. Host tools used by Makefile targets.
# ---------------------------------------------------------------------------
need=()
for p in iproute2 tcpdump jq make curl ca-certificates python3; do
  dpkg -s "$p" >/dev/null 2>&1 || need+=("$p")
done
if [ "${#need[@]}" -gt 0 ]; then
  say "installing host tools: ${need[*]}"
  $SUDO apt-get update -qq
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${need[@]}"
fi

# ---------------------------------------------------------------------------
# 3. Containerlab.
# ---------------------------------------------------------------------------
if ! command -v containerlab >/dev/null 2>&1; then
  say "installing containerlab ..."
  $SUDO bash -c "$(curl -sL https://get.containerlab.dev)"
fi
# clab_admins lets a normal user run containerlab; the installer only adds $USER,
# which is empty when this script itself runs as root.
if getent group clab_admins >/dev/null && [ -n "$target_user" ] && [ "$target_user" != root ]; then
  id -nG "$target_user" | grep -qw clab_admins || {
    $SUDO usermod -aG clab_admins "$target_user"
    say "added $target_user to clab_admins (open a new WSL shell for it to apply)"; }
fi

# ---------------------------------------------------------------------------
# 4. Kernel modules (stock WSL2 builds these as =m; see CLAUDE.md section 7).
#    bridge/8021q: L2 fabric. bonding: inter-core LACP. xfrm_user/esp4: IPsec.
# ---------------------------------------------------------------------------
mods="bridge 8021q bonding xfrm_user esp4"
for m in $mods; do
  $SUDO modprobe "$m" 2>/dev/null || say "WARNING: modprobe $m failed (see NOTES.md fallbacks)"
done
printf '%s\n' $mods | $SUDO tee /etc/modules-load.d/campus-lab.conf >/dev/null

# ---------------------------------------------------------------------------
# 5. Report.
# ---------------------------------------------------------------------------
containerlab version
$SUDO docker info >/dev/null && say "docker: $($SUDO docker version --format '{{.Server.Version}}') (native)"
for m in $mods; do lsmod | awk '{print $1}' | grep -qx "$m" && st=loaded || st=missing; say "module $m: $st"; done
say "setup OK"
