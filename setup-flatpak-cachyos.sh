#!/usr/bin/env bash
# =============================================================================
# setup-flatpak-cachyos.sh
# Instala y configura soporte de Flatpak (solo Flathub) en CachyOS
# =============================================================================

set -euo pipefail

# ── Colores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

# ── Verificar que se ejecuta como usuario normal (no root directo) ─────────────
if [[ $EUID -eq 0 ]]; then
    die "No ejecutes este script como root. Se usará sudo cuando sea necesario."
fi

# ── Verificar que sudo está disponible ───────────────────────────────────────
command -v sudo &>/dev/null || die "sudo no está instalado o no está en el PATH."

echo
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   Configuración de Flatpak + Flathub en CachyOS  ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
echo

# ── 1. Instalar Flatpak si no existe ─────────────────────────────────────────
if command -v flatpak &>/dev/null; then
    FLATPAK_VER=$(flatpak --version 2>/dev/null | awk '{print $2}')
    success "Flatpak ya está instalado (versión ${FLATPAK_VER})."
else
    info "Instalando flatpak con pacman..."
    sudo pacman -Sy --noconfirm flatpak || die "No se pudo instalar flatpak."
    success "Flatpak instalado correctamente."
fi

# ── 2. Agregar repositorio Flathub (solo si no existe) ───────────────────────
FLATHUB_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"
FLATHUB_NAME="flathub"

if flatpak remotes --columns=name 2>/dev/null | grep -qx "${FLATHUB_NAME}"; then
    success "El repositorio Flathub ya está configurado."
else
    info "Agregando repositorio Flathub..."
    sudo flatpak remote-add --if-not-exists "${FLATHUB_NAME}" "${FLATHUB_URL}" \
        || die "No se pudo agregar el repositorio Flathub."
    success "Flathub agregado correctamente."
fi

# ── 3. Verificar que Flathub es el ÚNICO remote activo ───────────────────────
info "Verificando remotos configurados..."
REMOTES=$(flatpak remotes --columns=name 2>/dev/null)

# Desactivar cualquier otro remote que no sea flathub
while IFS= read -r remote; do
    [[ -z "$remote" ]] && continue
    if [[ "$remote" != "${FLATHUB_NAME}" ]]; then
        warn "Remote adicional detectado: '${remote}'. Desactivándolo..."
        sudo flatpak remote-modify --disable "${remote}" 2>/dev/null \
            && warn "Remote '${remote}' desactivado (no eliminado)." \
            || warn "No se pudo desactivar '${remote}'. Revísalo manualmente."
    fi
done <<< "$REMOTES"

# ── 4. Asegurarse de que Flathub está habilitado ─────────────────────────────
sudo flatpak remote-modify --enable "${FLATHUB_NAME}" \
    || die "No se pudo habilitar el remote Flathub."
success "Flathub está habilitado y es el único remote activo."

# ── 5. Resumen final ──────────────────────────────────────────────────────────
echo
echo -e "${BOLD}══════════════════════ Resumen ══════════════════════${RESET}"
echo -e "  Flatpak versión : $(flatpak --version | awk '{print $2}')"
echo -e "  Remotos activos :"
flatpak remotes --columns=name,url 2>/dev/null | while IFS=$'\t' read -r name url; do
    echo -e "    ${GREEN}▸${RESET} ${name} → ${url}"
done
echo
echo -e "${GREEN}${BOLD}¡Configuración completada!${RESET}"
echo -e "Ahora puedes buscar e instalar apps con:"
echo -e "  ${BLUE}flatpak search <nombre>${RESET}"
echo -e "  ${BLUE}flatpak install flathub <app-id>${RESET}"
echo
echo -e "${YELLOW}Nota:${RESET} Si es la primera vez que instalas Flatpak, reinicia la sesión"
echo -e "o ejecuta ${BLUE}source /etc/profile.d/flatpak.sh${RESET} para que el PATH se actualice."
echo
