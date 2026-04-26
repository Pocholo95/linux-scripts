#!/bin/bash
# ============================================================
#  sunshine-ports.sh
#  Abre todos los puertos necesarios para Sunshine (streaming)
#  Compatible con ufw y firewalld
# ============================================================

set -euo pipefail

# --- Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # Sin color

# --- Puertos de Sunshine ---
TCP_PORTS=(47984 47989 47990 48010)
UDP_PORTS=(47998 47999 48000 48002 48010)

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║     Sunshine — Apertura de puertos       ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# --- Verificar permisos ---
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[ERROR]${NC} Este script debe ejecutarse como root o con sudo."
  exit 1
fi

# ─── UFW ────────────────────────────────────────────────────
open_ports_ufw() {
  echo -e "${YELLOW}[UFW]${NC} Detectado. Abriendo puertos...\n"

  for port in "${TCP_PORTS[@]}"; do
    ufw allow "${port}/tcp" > /dev/null
    echo -e "  ${GREEN}✔${NC} TCP ${port}"
  done

  for port in "${UDP_PORTS[@]}"; do
    ufw allow "${port}/udp" > /dev/null
    echo -e "  ${GREEN}✔${NC} UDP ${port}"
  done

  ufw reload > /dev/null
  echo -e "\n${GREEN}[UFW]${NC} Puertos aplicados y firewall recargado."
}

# ─── FIREWALLD ──────────────────────────────────────────────
open_ports_firewalld() {
  echo -e "${YELLOW}[firewalld]${NC} Detectado. Abriendo puertos...\n"

  for port in "${TCP_PORTS[@]}"; do
    firewall-cmd --permanent --add-port="${port}/tcp" > /dev/null
    echo -e "  ${GREEN}✔${NC} TCP ${port}"
  done

  for port in "${UDP_PORTS[@]}"; do
    firewall-cmd --permanent --add-port="${port}/udp" > /dev/null
    echo -e "  ${GREEN}✔${NC} UDP ${port}"
  done

  firewall-cmd --reload > /dev/null
  echo -e "\n${GREEN}[firewalld]${NC} Puertos aplicados y firewall recargado."
}

# ─── IPTABLES (fallback) ────────────────────────────────────
open_ports_iptables() {
  echo -e "${YELLOW}[iptables]${NC} Usando iptables como fallback...\n"

  for port in "${TCP_PORTS[@]}"; do
    iptables -C INPUT -p tcp --dport "${port}" -j ACCEPT 2>/dev/null || \
      iptables -A INPUT -p tcp --dport "${port}" -j ACCEPT
    echo -e "  ${GREEN}✔${NC} TCP ${port}"
  done

  for port in "${UDP_PORTS[@]}"; do
    iptables -C INPUT -p udp --dport "${port}" -j ACCEPT 2>/dev/null || \
      iptables -A INPUT -p udp --dport "${port}" -j ACCEPT
    echo -e "  ${GREEN}✔${NC} UDP ${port}"
  done

  # Intentar persistir reglas si iptables-save está disponible
  if command -v iptables-save &>/dev/null; then
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
  fi

  echo -e "\n${GREEN}[iptables]${NC} Puertos aplicados."
  echo -e "${YELLOW}[AVISO]${NC} Las reglas de iptables pueden no persistir al reiniciar."
  echo -e "         Instala 'iptables-persistent' para guardarlas automáticamente."
}

# ─── Detección automática del firewall ──────────────────────
if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
  open_ports_ufw
elif command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
  open_ports_firewalld
elif command -v iptables &>/dev/null; then
  open_ports_iptables
else
  echo -e "${RED}[ERROR]${NC} No se encontró ufw, firewalld ni iptables."
  echo "        Instala alguno de estos gestores de firewall e intenta de nuevo."
  exit 1
fi

# ─── Resumen ────────────────────────────────────────────────
echo ""
echo -e "${CYAN}─── Resumen de puertos abiertos ───────────────${NC}"
echo -e "  TCP: ${TCP_PORTS[*]}"
echo -e "  UDP: ${UDP_PORTS[*]}"
echo -e "${CYAN}───────────────────────────────────────────────${NC}"
echo ""
echo -e "${GREEN}✔ Sunshine debería poder conectarse correctamente.${NC}"
echo ""
