#!/bin/bash
# ============================================================
#  install-docker.sh
#  Instala Docker y configura permisos de usuario.
#  Compatible con Ubuntu/Debian, Fedora/RHEL/CentOS y Arch
# ============================================================

set -euo pipefail

# --- Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# --- Helpers ---
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()    { echo -e "\n${BOLD}${BLUE}▶ $*${NC}"; }

# ─── Banner ─────────────────────────────────────────────────
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║       Instalador de Docker para Linux    ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ─── Verificar root ──────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "Ejecuta el script con sudo:\n       sudo bash install-docker.sh"
fi

# ─── Detectar usuario real ───────────────────────────────────
REAL_USER="${SUDO_USER:-$USER}"
if [[ "$REAL_USER" == "root" ]]; then
  warn "Ejecutando como root puro. No se configurará grupo docker para otro usuario."
fi

# ─── Detectar distro ─────────────────────────────────────────
[[ -f /etc/os-release ]] || error "No se puede detectar la distribución Linux."
source /etc/os-release
DISTRO_ID="${ID,,}"
DISTRO_LIKE="${ID_LIKE:-}"

is_debian_based() { [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "debian" || "$DISTRO_LIKE" == *"debian"* ]]; }
is_fedora_based() { [[ "$DISTRO_ID" == "fedora" || "$DISTRO_ID" == "rhel"   || "$DISTRO_ID" == "centos" ||
                        "$DISTRO_ID" == "rocky"  || "$DISTRO_ID" == "almalinux" || "$DISTRO_LIKE" == *"fedora"* ]]; }
is_arch_based()   { [[ "$DISTRO_ID" == "arch"   || "$DISTRO_ID" == "manjaro" || "$DISTRO_ID" == "cachyos" ||
                        "$DISTRO_ID" == "endeavouros" || "$DISTRO_ID" == "garuda" || "$DISTRO_LIKE" == *"arch"* ]]; }

info "Distribución detectada: ${PRETTY_NAME:-$DISTRO_ID}"

# ══════════════════════════════════════════════════════════════
#  1. INSTALAR DOCKER
# ══════════════════════════════════════════════════════════════
step "Instalando Docker"

install_docker_debian() {
  info "Eliminando versiones antiguas..."
  apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

  apt-get update -qq
  apt-get install -y ca-certificates curl gnupg lsb-release

  info "Añadiendo repositorio oficial de Docker..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${DISTRO_ID} $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_fedora() {
  info "Eliminando versiones antiguas..."
  dnf remove -y docker docker-client docker-client-latest docker-common \
    docker-latest docker-latest-logrotate docker-logrotate docker-engine \
    podman runc 2>/dev/null || true

  dnf -y install dnf-plugins-core
  dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null || \
  dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

  dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_arch() {
  info "Actualizando sistema..."
  pacman -Syu --noconfirm

  info "Instalando Docker..."
  pacman -S --noconfirm --needed docker docker-compose
  pacman -S --noconfirm --needed docker-buildx 2>/dev/null || true
}

if is_debian_based; then
  install_docker_debian
elif is_fedora_based; then
  install_docker_fedora
elif is_arch_based; then
  install_docker_arch
else
  error "Distribución no soportada: $DISTRO_ID\n       Soportadas: Ubuntu, Debian, Fedora, RHEL, CentOS, Rocky, AlmaLinux, Arch, Manjaro, CachyOS, EndeavourOS"
fi

# ══════════════════════════════════════════════════════════════
#  2. HABILITAR SERVICIO
# ══════════════════════════════════════════════════════════════
step "Habilitando servicio de Docker"
systemctl enable docker
systemctl start docker
success "Docker iniciado y habilitado al arranque."

DOCKER_VERSION=$(docker --version)
success "Docker instalado: ${DOCKER_VERSION}"

# ══════════════════════════════════════════════════════════════
#  3. CONFIGURAR PERMISOS DE USUARIO
# ══════════════════════════════════════════════════════════════
step "Configurando permisos de usuario"

if [[ "$REAL_USER" != "root" ]]; then
  if ! getent group docker > /dev/null; then
    groupadd docker
    info "Grupo 'docker' creado."
  fi
  usermod -aG docker "$REAL_USER"
  success "Usuario '${REAL_USER}' añadido al grupo 'docker'."
else
  warn "Ejecutando como root — sin configuración adicional de grupo."
fi

chmod 666 /var/run/docker.sock 2>/dev/null || true

# ══════════════════════════════════════════════════════════════
#  RESUMEN FINAL
# ══════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           Resumen final                  ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}✔${NC} Docker   → $(docker --version)"
echo -e "  ${GREEN}✔${NC} Compose  → $(docker compose version 2>/dev/null || echo 'incluido en Docker')"
[[ "$REAL_USER" != "root" ]] && echo -e "  ${GREEN}✔${NC} Usuario  → '${REAL_USER}' en grupo docker"
echo ""

if [[ "$REAL_USER" != "root" ]]; then
  echo -e "${YELLOW}⚠  IMPORTANTE:${NC} Para aplicar el grupo sin reiniciar sesión, ejecuta:"
  echo -e "   ${CYAN}newgrp docker${NC}"
  echo ""
fi

echo -e "${GREEN}✔ Docker listo. Para GPU NVIDIA ejecuta: install-nvidia-docker.sh${NC}"
echo ""
