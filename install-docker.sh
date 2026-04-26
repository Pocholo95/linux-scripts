#!/bin/bash
# ============================================================
#  install-docker.sh
#  Instala Docker, configura permisos de usuario y opcionalmente
#  añade soporte para GPU NVIDIA en Docker.
#  Compatible con Ubuntu/Debian y Fedora/RHEL/CentOS
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
echo "║          Instalador de Docker para Linux             ║"
echo "║        con soporte opcional de GPU NVIDIA            ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ─── Verificar root ─────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "Este script debe ejecutarse con sudo o como root.\n       Intenta: sudo bash install-docker.sh"
fi

# ─── Detectar usuario real (quien llamó sudo) ────────────────
REAL_USER="${SUDO_USER:-$USER}"
if [[ "$REAL_USER" == "root" ]]; then
  warn "Estás ejecutando como root puro. El usuario de Docker será 'root'."
fi

# ─── Detectar distro ─────────────────────────────────────────
if [[ -f /etc/os-release ]]; then
  source /etc/os-release
  DISTRO_ID="${ID,,}"       # ubuntu, debian, fedora, rhel, centos, etc.
  DISTRO_LIKE="${ID_LIKE:-}"
else
  error "No se puede detectar la distribución Linux."
fi

is_debian_based() {
  [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "debian" || "$DISTRO_LIKE" == *"debian"* ]]
}

is_fedora_based() {
  [[ "$DISTRO_ID" == "fedora" || "$DISTRO_ID" == "rhel" || "$DISTRO_ID" == "centos" || \
     "$DISTRO_ID" == "rocky" || "$DISTRO_ID" == "almalinux" || "$DISTRO_LIKE" == *"fedora"* ]]
}

is_arch_based() {
  [[ "$DISTRO_ID" == "arch" || "$DISTRO_ID" == "manjaro" || "$DISTRO_ID" == "cachyos" || \
     "$DISTRO_ID" == "endeavouros" || "$DISTRO_ID" == "garuda" || "$DISTRO_LIKE" == *"arch"* ]]
}

info "Distribución detectada: ${PRETTY_NAME:-$DISTRO_ID}"

# ══════════════════════════════════════════════════════════════
#  1. INSTALAR DOCKER
# ══════════════════════════════════════════════════════════════
step "Instalando Docker"

install_docker_debian() {
  info "Eliminando versiones antiguas de Docker si existen..."
  apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

  info "Instalando dependencias..."
  apt-get update -qq
  apt-get install -y ca-certificates curl gnupg lsb-release

  info "Añadiendo repositorio oficial de Docker..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${DISTRO_ID} $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_fedora() {
  info "Eliminando versiones antiguas de Docker si existen..."
  dnf remove -y docker docker-client docker-client-latest docker-common \
    docker-latest docker-latest-logrotate docker-logrotate docker-engine \
    podman runc 2>/dev/null || true

  info "Añadiendo repositorio oficial de Docker..."
  dnf -y install dnf-plugins-core
  dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null || \
  dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

  info "Instalando Docker..."
  dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_arch() {
  info "Actualizando sistema..."
  pacman -Syu --noconfirm

  info "Instalando Docker..."
  pacman -S --noconfirm --needed docker docker-compose

  # docker-buildx viene como plugin en el paquete extra
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

# ─── Iniciar y habilitar Docker ──────────────────────────────
step "Habilitando servicio de Docker"
systemctl enable docker
systemctl start docker
success "Docker iniciado y habilitado al arranque."

# ─── Verificar instalación ───────────────────────────────────
DOCKER_VERSION=$(docker --version)
success "Docker instalado: ${DOCKER_VERSION}"

# ══════════════════════════════════════════════════════════════
#  2. CONFIGURAR PERMISOS DE USUARIO
# ══════════════════════════════════════════════════════════════
step "Configurando permisos de usuario"

if [[ "$REAL_USER" != "root" ]]; then
  if ! getent group docker > /dev/null; then
    groupadd docker
    info "Grupo 'docker' creado."
  fi

  usermod -aG docker "$REAL_USER"
  success "Usuario '${REAL_USER}' añadido al grupo 'docker'."

  # Activar grupo en sesión actual sin necesidad de reiniciar
  info "Aplicando cambio de grupo en la sesión actual..."
else
  warn "Ejecutando como root — no se configura grupo 'docker' adicional."
fi

# ─── Docker socket permissions ───────────────────────────────
chmod 666 /var/run/docker.sock 2>/dev/null || true

# ══════════════════════════════════════════════════════════════
#  3. DETECTAR GPU NVIDIA
# ══════════════════════════════════════════════════════════════
step "Detectando GPU NVIDIA"

NVIDIA_DETECTED=false
NVIDIA_DRIVER_OK=false

if command -v nvidia-smi &>/dev/null; then
  GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "desconocida")
  success "GPU NVIDIA detectada: ${GPU_NAME}"
  NVIDIA_DETECTED=true
  NVIDIA_DRIVER_OK=true
elif lspci 2>/dev/null | grep -qi nvidia; then
  warn "GPU NVIDIA detectada en hardware pero el driver NO está instalado."
  NVIDIA_DETECTED=true
else
  info "No se detectó GPU NVIDIA en este sistema."
fi

# ══════════════════════════════════════════════════════════════
#  4. SOPORTE OPCIONAL DE GPU EN DOCKER
# ══════════════════════════════════════════════════════════════
INSTALL_NVIDIA_DOCKER=false

if $NVIDIA_DETECTED; then
  echo ""
  echo -e "${BOLD}┌─────────────────────────────────────────────────────┐${NC}"
  echo -e "${BOLD}│  GPU NVIDIA encontrada                              │${NC}"
  echo -e "${BOLD}│  ¿Deseas instalar soporte de GPU para Docker?       │${NC}"
  echo -e "${BOLD}│  (NVIDIA Container Toolkit)                         │${NC}"
  echo -e "${BOLD}└─────────────────────────────────────────────────────┘${NC}"
  echo ""

  if ! $NVIDIA_DRIVER_OK; then
    warn "El driver NVIDIA no está instalado. Si continúas, se instalará"
    warn "el toolkit pero necesitarás instalar el driver manualmente."
    echo ""
  fi

  while true; do
    read -rp "$(echo -e "${YELLOW}¿Instalar soporte GPU NVIDIA para Docker? [s/N]:${NC} ")" choice
    case "${choice,,}" in
      s|si|sí|y|yes) INSTALL_NVIDIA_DOCKER=true; break ;;
      n|no|"")        INSTALL_NVIDIA_DOCKER=false; break ;;
      *) echo "  Por favor responde 's' para sí o 'n' para no." ;;
    esac
  done
fi

# ─── Instalar NVIDIA Container Toolkit ──────────────────────
if $INSTALL_NVIDIA_DOCKER; then
  step "Instalando NVIDIA Container Toolkit"

  install_nvidia_toolkit_debian() {
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
      | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
      | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
      > /etc/apt/sources.list.d/nvidia-container-toolkit.list

    apt-get update -qq
    apt-get install -y nvidia-container-toolkit
  }

  install_nvidia_toolkit_fedora() {
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
      > /etc/yum.repos.d/nvidia-container-toolkit.repo
    dnf install -y nvidia-container-toolkit
  }

  install_nvidia_toolkit_arch() {
    # nvidia-container-toolkit está disponible en los repos de Arch/CachyOS
    pacman -S --noconfirm --needed nvidia-container-toolkit 2>/dev/null || {
      warn "No encontrado en repos oficiales, intentando con AUR via yay..."
      if command -v yay &>/dev/null; then
        sudo -u "$REAL_USER" yay -S --noconfirm nvidia-container-toolkit
      elif command -v paru &>/dev/null; then
        sudo -u "$REAL_USER" paru -S --noconfirm nvidia-container-toolkit
      else
        error "No se pudo instalar nvidia-container-toolkit. Instala 'yay' o 'paru' e inténtalo de nuevo."
      fi
    }
  }

  if is_debian_based; then
    install_nvidia_toolkit_debian
  elif is_fedora_based; then
    install_nvidia_toolkit_fedora
  elif is_arch_based; then
    install_nvidia_toolkit_arch
  fi

  # Configurar Docker runtime para NVIDIA
  info "Configurando Docker runtime para NVIDIA..."
  nvidia-ctk runtime configure --runtime=docker
  systemctl restart docker
  success "NVIDIA Container Toolkit instalado y Docker reiniciado."

  # Test rápido (solo si el driver está activo)
  if $NVIDIA_DRIVER_OK; then
    echo ""
    info "Ejecutando prueba rápida de GPU en Docker..."
    if docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi 2>/dev/null; then
      success "¡GPU accesible dentro de Docker!"
    else
      warn "La prueba falló. Puede ser que la imagen tarde en descargarse o el driver necesite reinicio."
    fi
  fi
fi

# ══════════════════════════════════════════════════════════════
#  5. RESUMEN FINAL
# ══════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                   Resumen final                     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}✔${NC} Docker instalado       → $(docker --version)"
echo -e "  ${GREEN}✔${NC} Docker Compose         → $(docker compose version 2>/dev/null || echo 'incluido en Docker')"
if [[ "$REAL_USER" != "root" ]]; then
  echo -e "  ${GREEN}✔${NC} Usuario en grupo docker → ${REAL_USER}"
fi
if $INSTALL_NVIDIA_DOCKER; then
  echo -e "  ${GREEN}✔${NC} NVIDIA Container Toolkit instalado"
fi
echo ""

if [[ "$REAL_USER" != "root" ]]; then
  echo -e "${YELLOW}⚠  IMPORTANTE:${NC} Para usar Docker sin sudo, cierra sesión y vuelve a entrar,"
  echo -e "   o ejecuta en tu terminal actual:"
  echo -e "   ${CYAN}newgrp docker${NC}"
  echo ""
fi

echo -e "${GREEN}✔ Instalación completada. Docker está listo para usar.${NC}"
echo ""
