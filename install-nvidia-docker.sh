#!/bin/bash
# ============================================================
#  install-nvidia-docker.sh
#  Instala NVIDIA Container Toolkit para usar la GPU en Docker.
#  Compatible con Ubuntu/Debian, Fedora/RHEL/CentOS y Arch
#  Requisito: Docker ya instalado y driver NVIDIA activo.
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
echo "╔══════════════════════════════════════════════════════╗"
echo "║      NVIDIA Container Toolkit para Docker            ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ─── Verificar root ──────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "Ejecuta el script con sudo:\n       sudo bash install-nvidia-docker.sh"
fi

REAL_USER="${SUDO_USER:-$USER}"

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
#  VERIFICACIONES PREVIAS
# ══════════════════════════════════════════════════════════════
step "Verificando requisitos"

# Docker instalado?
if ! command -v docker &>/dev/null; then
  error "Docker no está instalado. Ejecuta primero install-docker.sh"
fi
success "Docker encontrado: $(docker --version)"

# Driver NVIDIA activo?
NVIDIA_DRIVER_OK=false
if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
  GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
  success "Driver NVIDIA activo — GPU: ${GPU_NAME}"
  NVIDIA_DRIVER_OK=true
elif lspci 2>/dev/null | grep -qi nvidia; then
  warn "Se detectó hardware NVIDIA pero el driver no está activo."
  warn "El toolkit se instalará, pero necesitas el driver para usar la GPU."
else
  error "No se detectó ninguna GPU NVIDIA en este sistema."
fi

# ══════════════════════════════════════════════════════════════
#  INSTALAR NVIDIA CONTAINER TOOLKIT
# ══════════════════════════════════════════════════════════════
step "Instalando NVIDIA Container Toolkit"

install_nvidia_toolkit_debian() {
  info "Añadiendo repositorio de NVIDIA..."
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

  curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    > /etc/apt/sources.list.d/nvidia-container-toolkit.list

  apt-get update -qq
  apt-get install -y nvidia-container-toolkit
}

install_nvidia_toolkit_fedora() {
  info "Añadiendo repositorio de NVIDIA..."
  curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
    > /etc/yum.repos.d/nvidia-container-toolkit.repo
  dnf install -y nvidia-container-toolkit
}

install_nvidia_toolkit_arch() {
  info "Instalando desde repositorios de Arch..."
  if pacman -Si nvidia-container-toolkit &>/dev/null; then
    pacman -S --noconfirm --needed nvidia-container-toolkit
  else
    warn "No encontrado en repos oficiales, intentando con AUR..."
    if command -v yay &>/dev/null; then
      sudo -u "$REAL_USER" yay -S --noconfirm nvidia-container-toolkit
    elif command -v paru &>/dev/null; then
      sudo -u "$REAL_USER" paru -S --noconfirm nvidia-container-toolkit
    else
      error "No se encontró yay ni paru. Instala un helper de AUR e intenta de nuevo."
    fi
  fi
}

if is_debian_based; then
  install_nvidia_toolkit_debian
elif is_fedora_based; then
  install_nvidia_toolkit_fedora
elif is_arch_based; then
  install_nvidia_toolkit_arch
else
  error "Distribución no soportada: $DISTRO_ID"
fi

# ══════════════════════════════════════════════════════════════
#  CONFIGURAR DOCKER RUNTIME
# ══════════════════════════════════════════════════════════════
step "Configurando runtime de Docker para NVIDIA"

nvidia-ctk runtime configure --runtime=docker
systemctl restart docker
success "Runtime configurado y Docker reiniciado."

# ══════════════════════════════════════════════════════════════
#  TEST RÁPIDO
# ══════════════════════════════════════════════════════════════
if $NVIDIA_DRIVER_OK; then
  step "Ejecutando prueba de GPU en Docker"
  if docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi; then
    success "¡GPU accesible dentro de Docker!"
  else
    warn "La prueba falló. Prueba reiniciando el sistema e intenta de nuevo con:"
    warn "docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi"
  fi
fi

# ══════════════════════════════════════════════════════════════
#  RESUMEN FINAL
# ══════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                  Resumen final                      ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}✔${NC} NVIDIA Container Toolkit instalado"
echo -e "  ${GREEN}✔${NC} Runtime de Docker configurado"
$NVIDIA_DRIVER_OK && echo -e "  ${GREEN}✔${NC} GPU probada correctamente en contenedor"
echo ""
echo -e "  Úsala en tus contenedores con:"
echo -e "  ${CYAN}docker run --rm --gpus all <imagen>${NC}"
echo ""
echo -e "${GREEN}✔ Configuración completada.${NC}"
echo ""
