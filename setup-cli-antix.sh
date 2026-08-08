#!/usr/bin/env bash
# ==============================================================================
#  setup-cli.sh - a comfortable terminal for antiX core (32-bit / i386)
# ------------------------------------------------------------------------------
#  Built for a machine where most "modern CLI" tools DO NOT ship binaries:
#
#    · apt first. Debian i386 packages are the reliable path.
#    · GitHub releases only as a fallback, and only where i686 builds exist.
#    · When a tool simply isn't available for 32-bit, it says so and wires up
#      a sane substitute instead of silently doing nothing.
#    · No X assumed (antiX core is console-only): no fonts, no X clipboard,
#      no GUI anything. Clipboard falls back to OSC-52 over SSH.
#
#  Quick start:  bash setup-cli.sh --dry-run
#                bash setup-cli.sh
#                bash setup-cli.sh --ascii     # bare TTY, no Nerd Font glyphs
# ==============================================================================

set -Eeuo pipefail

VERSION="2.0.0-i386"
# When the script is piped into bash (curl | bash) there is no BASH_SOURCE,
# and set -u would abort right here. Fall back to a plain name.
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-setup-cli-antix.sh}")"

BIN_DIR="$HOME/.local/bin"
SHARE_DIR="$HOME/.local/share"
CONF_DIR="$HOME/.config"
SHELL_CONF_DIR="$CONF_DIR/shell"
PLUGIN_DIR="$SHARE_DIR/zsh/plugins"
NOTES_DIR="$HOME/notes"
STATE_DIR="$SHARE_DIR/setup-cli"
BACKUP_DIR="$HOME/.setup-cli-backup/$(date +%Y%m%d-%H%M%S)"

# ------------------------------------------------------------------------------
#  Output style
# ------------------------------------------------------------------------------
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" == "" ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_PINK=$'\033[38;5;211m'; C_MAUVE=$'\033[38;5;183m'; C_BLUE=$'\033[38;5;117m'
  C_GREEN=$'\033[38;5;114m'; C_AMBER=$'\033[38;5;222m'; C_RED=$'\033[38;5;210m'
  C_GREY=$'\033[38;5;245m'
else
  C_RESET=""; C_BOLD=""; C_PINK=""; C_MAUVE=""; C_BLUE=""
  C_GREEN=""; C_AMBER=""; C_RED=""; C_GREY=""
fi

STEP_N=0; STEP_TOTAL=0
FAILED=(); INSTALLED=(); SKIPPED=(); FALLBACKS=()

hr()    { printf '%s%s%s\n' "$C_GREY" "$(printf -- '-%.0s' $(seq 1 62))" "$C_RESET"; }
say()   { printf '%s\n' "$*"; }
info()  { printf '  %s.%s %s\n' "$C_GREY" "$C_RESET" "$*"; }
ok()    { printf '  %s+%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '  %s!%s %s\n' "$C_AMBER" "$C_RESET" "$*"; }
bad()   { printf '  %sx%s %s\n' "$C_RED" "$C_RESET" "$*"; }
die()   { printf '\n%sError:%s %s\n' "$C_RED$C_BOLD" "$C_RESET" "$*" >&2; exit 1; }

# "tool X has no 32-bit build -> using Y instead"
fallback() {
  # In a dry run we cannot actually probe apt or GitHub, so reporting a
  # substitution would be a lie. Say what we would check instead.
  $DRY_RUN && { info "(dry run) would look for a 32-bit build first"; return 0; }
  FALLBACKS+=("$1"); warn "$1"
}

step() {
  STEP_N=$((STEP_N + 1))
  printf '\n%s[%s/%s]%s %s%s%s\n' \
    "$C_MAUVE" "$STEP_N" "$STEP_TOTAL" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"
}

# ------------------------------------------------------------------------------
#  Header box. ASCII only, width computed - safe on a plain Linux console.
# ------------------------------------------------------------------------------
BOX_W=58

box_rule() { printf '  %s%s%s\n' "$C_MAUVE" "$(printf -- '-%.0s' $(seq 1 $BOX_W))" "$C_RESET"; }

box_fit() {
  local text="$1" max="$2"
  if (( ${#text} > max )); then printf '%s...' "${text:0:$((max - 3))}"
  else printf '%s' "$text"; fi
}

box_line() {
  local max=$((BOX_W - 4)) text pad
  text="$(box_fit "$1" "$max")"; pad=$(( max - ${#text} )); (( pad < 0 )) && pad=0
  printf '  %s|%s  %s%s%s%*s%s|%s\n' \
    "$C_MAUVE" "$C_RESET" "${2:-}" "$text" "$C_RESET" "$pad" "" "$C_MAUVE" "$C_RESET"
}

box_row() {
  local max=$((BOX_W - 4)) label value pad
  label="$(printf '%-9s' "$1")"
  value="$(box_fit "$2" "$(( max - ${#label} ))")"
  pad=$(( max - ${#label} - ${#value} )); (( pad < 0 )) && pad=0
  printf '  %s|%s  %s%s%s%s%*s%s|%s\n' \
    "$C_MAUVE" "$C_RESET" "$C_GREY" "$label" "$C_RESET" "$value" "$pad" "" "$C_MAUVE" "$C_RESET"
}

os_name()   { ( . /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-Linux}" ) || printf 'Linux'; }
mem_usage() { command -v free   >/dev/null && free -m | awk 'NR==2 {print $3"M used of "$2"M"}'; }
disk_free() { command -v df     >/dev/null && df -h / | awk 'NR==2 {print $4" free of "$2}'; }
up_time()   { command -v uptime >/dev/null && uptime -p 2>/dev/null | sed 's/^up //'; }

banner() {
  local host os kern shl now mem disk upt
  host="$(id -un)@$(hostname 2>/dev/null || echo localhost)"
  os="$(os_name) ($(dpkg --print-architecture 2>/dev/null || uname -m))"
  kern="$(uname -r)"
  shl="$(basename "${SHELL:-sh}")"
  now="$(date '+%a %Y-%m-%d  %H:%M')"
  mem="$(mem_usage || true)"; disk="$(disk_free || true)"; upt="$(up_time || true)"

  printf '\n'
  box_rule
  box_line "setup-cli v$VERSION" "$C_BOLD"
  box_rule
  box_row "host"   "$host"
  box_row "os"     "$os"
  box_row "kernel" "$kern"
  box_row "shell"  "$shl"
  [[ -n "$upt"  ]] && box_row "uptime" "$upt"
  [[ -n "$mem"  ]] && box_row "memory" "$mem"
  [[ -n "$disk" ]] && box_row "disk"   "$disk"
  box_row "time"   "$now"
  box_rule
}

# ------------------------------------------------------------------------------
#  Options
# ------------------------------------------------------------------------------
DRY_RUN=false
ASSUME_YES=false
MINIMAL=false
CHANGE_SHELL=true
ICONS=true          # Nerd Font glyphs in prompt/listings
ONLY=""; SKIP=""

ALL_MODULES=(base modern navigation tools media prompt zsh config theme cheatsheet)

usage() {
  cat <<HELP
${C_BOLD}$SCRIPT_NAME${C_RESET} v$VERSION - CLI setup for antiX core (i386).

${C_BOLD}USAGE${C_RESET}
  bash $SCRIPT_NAME [options]

${C_BOLD}OPTIONS${C_RESET}
  -n, --dry-run       Show what it would do, change nothing.
  -y, --yes           Never ask, assume yes.
  -m, --minimal       Skip media tools and heavy extras (good for old hardware).
      --ascii         No Nerd Font glyphs - for a bare TTY with no font support.
      --only=A,B      Run these modules only.
      --skip=A,B      Skip these modules.
      --keep-shell    Do not switch your default shell to zsh.
  -h, --help          This help.
  -v, --version       Version.

${C_BOLD}MODULES${C_RESET}
  base         system packages (git, curl, zsh, procps, less...)
  modern       ripgrep, bat, fd + whatever 32-bit builds actually exist
  navigation   fzf, zoxide  (atuin has no i386 build - fzf covers Ctrl+R)
  tools        lazygit, mc, htop/btop, tmux, taskwarrior
  media        ffmpeg, imagemagick, yt-dlp, poppler  (skipped by --minimal)
  prompt       starship, or a pure-zsh git prompt if i686 build is missing
  zsh          zsh + autosuggestions + syntax highlighting
  config       modular .zshrc, aliases and functions
  theme        Catppuccin Mocha for bat and fzf
  cheatsheet   a shortcut reference you can reopen any time

${C_BOLD}NOTE ON FONTS${C_RESET}
  There is no font module: on a console-only system the Nerd Font has to be
  installed on whatever machine runs your terminal emulator (e.g. Tabby on
  Windows over SSH). If this box IS your terminal, use --ascii.
HELP
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run)  DRY_RUN=true ;;
    -y|--yes)      ASSUME_YES=true ;;
    -m|--minimal)  MINIMAL=true ;;
    --ascii)       ICONS=false ;;
    --only=*)      ONLY="${1#*=}" ;;
    --skip=*)      SKIP="${1#*=}" ;;
    --keep-shell)  CHANGE_SHELL=false ;;
    -h|--help)     usage; exit 0 ;;
    -v|--version)  echo "$SCRIPT_NAME $VERSION"; exit 0 ;;
    *)             die "Unknown option: $1  (try --help)" ;;
  esac
  shift
done

$MINIMAL && SKIP="${SKIP:+$SKIP,}media"

MODULES=()
for m in "${ALL_MODULES[@]}"; do
  if [[ -n "$ONLY" ]]; then
    [[ ",$ONLY," == *",$m,"* ]] && MODULES+=("$m")
  else
    [[ ",$SKIP," == *",$m,"* ]] || MODULES+=("$m")
  fi
done
[[ ${#MODULES[@]} -gt 0 ]] || die "No modules left to run."
STEP_TOTAL=${#MODULES[@]}

# ------------------------------------------------------------------------------
#  Utilities
# ------------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

run() {
  if $DRY_RUN; then printf '  %s>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; return 0; fi
  "$@"
}

run_quiet() {
  if $DRY_RUN; then printf '  %s>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; return 0; fi
  local out
  if ! out="$("$@" 2>&1)"; then printf '%s\n' "$out" | tail -n 15 >&2; return 1; fi
}

confirm() {
  $ASSUME_YES && return 0
  $DRY_RUN && return 0
  local answer
  printf '  %s?%s %s [y/N] ' "$C_AMBER" "$C_RESET" "$1"
  read -r answer </dev/tty || return 1
  [[ "$answer" =~ ^[yY]$ ]]
}

backup() {
  local file="$1"
  [[ -e "$file" ]] || return 0
  $DRY_RUN && { info "would back up $file"; return 0; }
  mkdir -p "$BACKUP_DIR"; cp -a "$file" "$BACKUP_DIR/" 2>/dev/null || true
  info "backed up: $(basename "$file")"
}

write_file() {
  local dest="$1" content; content="$(cat)"
  if $DRY_RUN; then
    printf '  %s>%s would write %s (%s lines)\n' \
      "$C_BLUE" "$C_RESET" "$dest" "$(printf '%s' "$content" | wc -l)"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" ]] && [[ "$(cat "$dest")" == "$content" ]]; then
    info "$(basename "$dest") already up to date"; return 0
  fi
  [[ -f "$dest" ]] && backup "$dest"
  printf '%s\n' "$content" > "$dest"
  ok "$(basename "$dest")"
}

# ------------------------------------------------------------------------------
#  Preflight
# ------------------------------------------------------------------------------
APT_UPDATED=false
SCRATCH=""          # scratch dir for downloads, wiped on exit
SUDO=""
ARCH_DEB=""
ARCH_GNU=""
IS_32BIT=false
HAS_X=false

preflight() {
  [[ "$(uname -s)" == "Linux" ]] || die "This script targets Linux."
  have apt-get || die "No apt-get found. This script assumes antiX/Debian."

  # antiX often has no passwordless sudo; root via su is the normal path there.
  if [[ $EUID -eq 0 ]]; then
    SUDO="command"
  elif have sudo && sudo -n true 2>/dev/null; then
    SUDO="sudo"
  elif have sudo; then
    SUDO="sudo"
    info "sudo will ask for your password"
  else
    die "No sudo here. On antiX, run:  su -  then re-run this script as root."
  fi

  ARCH_DEB="$(dpkg --print-architecture 2>/dev/null || echo unknown)"
  case "$ARCH_DEB" in
    i386)  ARCH_GNU="i686";   IS_32BIT=true ;;
    amd64) ARCH_GNU="x86_64" ;;
    arm64) ARCH_GNU="aarch64" ;;
    armhf) ARCH_GNU="armv7";  IS_32BIT=true ;;
    *)     die "Unsupported architecture: $ARCH_DEB" ;;
  esac

  [[ -n "${DISPLAY:-}" ]] || [[ -n "${WAYLAND_DISPLAY:-}" ]] && HAS_X=true

  if ! $DRY_RUN && ! curl -fsS --max-time 8 -o /dev/null https://github.com 2>/dev/null; then
    warn "GitHub seems unreachable; fallbacks will be used more often."
  fi

  mkdir -p "$BIN_DIR" "$SHELL_CONF_DIR" "$STATE_DIR" 2>/dev/null || true

  # One scratch directory for the whole run. A RETURN trap per function would
  # fire after its local $tmp is gone, which under set -u aborts the script.
  SCRATCH="$(mktemp -d 2>/dev/null || echo /tmp/setup-cli.$$)"
  mkdir -p "$SCRATCH" 2>/dev/null || true
  trap 'rm -rf "${SCRATCH:-}"' EXIT
}

apt_update_once() {
  $APT_UPDATED && return 0
  info "refreshing apt indexes..."
  run_quiet $SUDO apt-get update -qq || warn "apt-get update had trouble"
  APT_UPDATED=true
}

# apt_install pkg...    -> installs whatever is missing, tolerates absent packages
apt_install() {
  local pending=()
  for p in "$@"; do dpkg -s "$p" >/dev/null 2>&1 || pending+=("$p"); done
  if [[ ${#pending[@]} -eq 0 ]]; then info "already present: $*"; return 0; fi
  apt_update_once
  info "installing: ${pending[*]}"
  DEBIAN_FRONTEND=noninteractive run_quiet $SUDO apt-get install -y --no-install-recommends "${pending[@]}" \
    || { bad "apt failed on: ${pending[*]}"; return 1; }
  $DRY_RUN || { INSTALLED+=("${pending[@]}"); ok "apt: ${pending[*]}"; }
}

# apt_try pkg   -> install one package, quietly accept that it may not exist
apt_try() {
  local p="$1"
  dpkg -s "$p" >/dev/null 2>&1 && { info "$p already present"; return 0; }
  $DRY_RUN && { info "> would try apt: $p"; return 1; }
  apt_update_once
  if apt-cache show "$p" >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive run_quiet $SUDO apt-get install -y --no-install-recommends "$p" \
      && { INSTALLED+=("$p"); ok "apt: $p"; return 0; }
  fi
  return 1
}

# ==============================================================================
#  GitHub releases (fallback path only)
# ==============================================================================

gh_url() {
  local repo="$1" pattern="$2" url
  url="$(curl -fsSL --max-time 20 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
        | grep -oP '"browser_download_url":\s*"\K[^"]+' \
        | grep -E "$pattern" | head -n1)" || true
  [[ -n "$url" ]] || return 1
  printf '%s' "$url"
}

deb_from_gh() {
  local name="$1" repo="$2" pattern="$3"
  have "$name" && { info "$name already installed"; return 0; }
  $DRY_RUN && { info "> would try $name (.deb from $repo)"; return 1; }

  local url tmp
  url="$(gh_url "$repo" "$pattern")" || return 1
  tmp="$(mktemp -d "${SCRATCH:-/tmp}/deb.XXXXXX")" || return 1
  curl -fsSL --max-time 180 -o "$tmp/p.deb" "$url" || return 1
  $SUDO dpkg -i "$tmp/p.deb" >/dev/null 2>&1 || $SUDO apt-get -f install -y -qq >/dev/null 2>&1
  have "$name" && { ok "$name (github)"; INSTALLED+=("$name"); return 0; }
  return 1
}

bin_from_gh() {
  local name="$1" repo="$2" pattern="$3" binary="${4:-$1}"
  have "$name" && { info "$name already installed"; return 0; }
  $DRY_RUN && { info "> would try $name (binary from $repo)"; return 1; }

  local url tmp found
  url="$(gh_url "$repo" "$pattern")" || return 1
  tmp="$(mktemp -d "${SCRATCH:-/tmp}/bin.XXXXXX")" || return 1

  case "$url" in
    *.zip)
      curl -fsSL --max-time 240 -o "$tmp/a.zip" "$url" || return 1
      unzip -qo "$tmp/a.zip" -d "$tmp/x" || return 1 ;;
    *)
      mkdir -p "$tmp/x"
      curl -fsSL --max-time 240 "$url" | tar -xz -C "$tmp/x" || return 1 ;;
  esac

  found="$(find "$tmp/x" -type f -name "$binary" -perm -u+x 2>/dev/null | head -n1)"
  [[ -z "$found" ]] && found="$(find "$tmp/x" -type f -name "$binary" | head -n1)"
  [[ -n "$found" ]] || return 1

  install -Dm755 "$found" "$BIN_DIR/$name"
  ok "$name (github) -> $BIN_DIR/$name"
  INSTALLED+=("$name")
}

git_sync() {
  local repo="$1" dest="$2"
  $DRY_RUN && { info "> would clone/update $(basename "$dest")"; return 0; }
  if [[ -d "$dest/.git" ]]; then
    git -C "$dest" pull --quiet --ff-only 2>/dev/null || true
    info "$(basename "$dest") updated"
  else
    mkdir -p "$(dirname "$dest")"
    git clone --depth 1 --quiet "https://github.com/$repo" "$dest" \
      && ok "$(basename "$dest")" || { bad "could not clone $repo"; return 1; }
  fi
}

# ==============================================================================
#  MODULES
# ==============================================================================

mod_base() {
  step "System base"
  apt_install \
    git curl wget unzip zip tar ca-certificates \
    procps less man-db file grep sed gawk \
    build-essential pkg-config tree ncdu p7zip-full || true
  apt_try jq || true
  apt_try python3 || true
}

mod_modern() {
  step "Modern replacements (apt first, 32-bit reality second)"

  # These three exist as Debian i386 packages. They are the backbone.
  apt_install ripgrep bat fd-find || true
  if ! $DRY_RUN; then
    have batcat && [[ ! -e "$BIN_DIR/bat" ]] && ln -sf "$(command -v batcat)" "$BIN_DIR/bat" && ok "bat -> batcat"
    have fdfind && [[ ! -e "$BIN_DIR/fd"  ]] && ln -sf "$(command -v fdfind)"  "$BIN_DIR/fd"  && ok "fd -> fdfind"
  fi

  # eza: only in newer Debian. Try apt, then an i686 build, then plain ls.
  if ! have eza; then
    apt_try eza \
      || bin_from_gh eza "eza-community/eza" "${ARCH_GNU}-unknown-linux-(gnu|musl)\\.tar\\.gz$" eza \
      || fallback "eza: no i386 build -> using coreutils ls with color aliases"
  else
    info "eza already installed"
  fi

  # duf / dust / procs / delta: Go and Rust tools, spotty 32-bit coverage.
  if ! have duf; then
    apt_try duf \
      || deb_from_gh duf "muesli/duf" "linux_(i386|386)\\.deb$" \
      || fallback "duf: no i386 build -> 'df' stays as df -h"
  fi
  if ! have dust; then
    apt_try dust \
      || bin_from_gh dust "bootandy/dust" "${ARCH_GNU}-unknown-linux-(gnu|musl)\\.tar\\.gz$" dust \
      || fallback "dust: no i386 build -> using ncdu for disk usage"
  fi
  if ! have procs; then
    apt_try procs \
      || fallback "procs: no i386 build -> using htop / ps"
  fi
  if ! have delta; then
    apt_try git-delta \
      || deb_from_gh delta "dandavison/delta" "git-delta_.*_i386\\.deb$" \
      || fallback "delta: no i386 build -> git keeps its own colored diff"
  fi
}

mod_navigation() {
  step "Fuzzy navigation"

  # fzf: Go, ships a linux_386 binary, and Debian packages it too.
  if have fzf; then
    info "fzf already installed"
  else
    apt_try fzf || {
      if git_sync "junegunn/fzf" "$HOME/.fzf"; then
        run "$HOME/.fzf/install" --bin >/dev/null 2>&1 || true
        if ! $DRY_RUN && [[ -x "$HOME/.fzf/bin/fzf" ]]; then
          ln -sf "$HOME/.fzf/bin/fzf" "$BIN_DIR/fzf"; ok "fzf"; INSTALLED+=(fzf)
        fi
      fi
    }
  fi
  # Debian's fzf ships the key bindings separately
  if ! $DRY_RUN && [[ ! -f "$HOME/.fzf/shell/key-bindings.zsh" ]]; then
    [[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]] \
      && info "using Debian's fzf key bindings"
  fi

  # zoxide: in Debian, and Rust upstream does publish i686-musl.
  if have zoxide; then
    info "zoxide already installed"
  else
    apt_try zoxide \
      || bin_from_gh zoxide "ajeetdsouza/zoxide" "${ARCH_GNU}-unknown-linux-musl\\.tar\\.gz$" zoxide \
      || fallback "zoxide: unavailable -> 'cd' stays plain (zsh AUTO_CD still helps)"
  fi

  # atuin: x86_64/aarch64 only. Not worth chasing on i386.
  if $IS_32BIT && ! have atuin; then
    fallback "atuin: no 32-bit build -> Ctrl+R uses fzf over zsh history"
    SKIPPED+=("atuin")
  fi
}

mod_tools() {
  step "Everyday tools"

  # mc instead of yazi: yazi is x86_64/aarch64 only, mc is perfect on old kit.
  apt_install mc tmux htop || true
  apt_try btop || fallback "btop: not in this release -> htop is installed"
  apt_try taskwarrior || apt_try task || true

  # lazygit publishes an explicit 32-bit Linux build.
  if ! have lazygit; then
    bin_from_gh lazygit "jesseduffield/lazygit" "Linux_(32bit|x86)\\.tar\\.gz$" lazygit \
      || fallback "lazygit: 32-bit build not found -> use 'tig' or plain git"
    have lazygit || apt_try tig || true
  fi

  $IS_32BIT && fallback "yazi / zellij: 64-bit only -> mc (files) and tmux (panes)" || true
}

mod_media() {
  step "Media and file conversion"
  apt_install ffmpeg poppler-utils rsync || true
  apt_try imagemagick || true
  apt_try trash-cli || fallback "trash-cli: not available -> 'del' will not exist"

  if $HAS_X; then
    apt_try xclip || true
  else
    info "no X session: clipboard will use OSC-52 (works over SSH in Tabby)"
  fi

  # yt-dlp is pure Python: architecture does not matter.
  if have yt-dlp; then
    info "yt-dlp already installed"
  elif ! $DRY_RUN; then
    if curl -fsSL --max-time 90 -o "$BIN_DIR/yt-dlp" \
        "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"; then
      chmod +x "$BIN_DIR/yt-dlp"; ok "yt-dlp"; INSTALLED+=(yt-dlp)
    else
      warn "could not download yt-dlp"
    fi
  else
    info "> would install yt-dlp"
  fi
}

mod_prompt() {
  step "Prompt"
  if have starship; then
    info "starship already installed"
    return 0
  fi
  $DRY_RUN && { info "> would try starship (i686 build)"; return 0; }

  if curl -fsSL --max-time 120 https://starship.rs/install.sh \
      | sh -s -- --yes --bin-dir "$BIN_DIR" >/dev/null 2>&1 && have starship; then
    ok "starship"; INSTALLED+=(starship)
  elif bin_from_gh starship "starship/starship" "${ARCH_GNU}-unknown-linux-(gnu|musl)\\.tar\\.gz$" starship; then
    : # done
  else
    fallback "starship: no i386 build -> using the built-in pure-zsh git prompt"
  fi
}

mod_zsh() {
  step "Zsh and plugins"
  apt_install zsh || true

  git_sync "zsh-users/zsh-autosuggestions"              "$PLUGIN_DIR/zsh-autosuggestions"
  git_sync "zdharma-continuum/fast-syntax-highlighting" "$PLUGIN_DIR/fast-syntax-highlighting"
  git_sync "zsh-users/zsh-completions"                  "$PLUGIN_DIR/zsh-completions"

  if $CHANGE_SHELL && ! $DRY_RUN; then
    local zsh_path; zsh_path="$(command -v zsh || true)"
    if [[ -n "$zsh_path" ]] && [[ "${SHELL:-}" != "$zsh_path" ]]; then
      if confirm "Make zsh your default shell?"; then
        chsh -s "$zsh_path" && ok "default shell: zsh (applies on next login)" \
          || warn "chsh failed; run manually: chsh -s $zsh_path"
      else
        SKIPPED+=("shell switch")
      fi
    fi
  fi
}

# ==============================================================================
#  Configuration
# ==============================================================================

mod_config() {
  step "Zsh configuration"

  backup "$HOME/.zshrc"
  $DRY_RUN || mkdir -p "$NOTES_DIR" 2>/dev/null || true

  write_file "$HOME/.zshrc" <<'ZSHRC'
# ~/.zshrc - generated by setup-cli (antiX / i386)
# This file only loads things. Your tweaks go in ~/.config/shell/*.zsh
# (or ~/.config/shell/99-local.zsh, which is never overwritten).

# --- History ------------------------------------------------------------------
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt EXTENDED_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS SHARE_HISTORY INC_APPEND_HISTORY

# --- Behaviour ----------------------------------------------------------------
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT
setopt INTERACTIVE_COMMENTS NO_BEEP GLOB_DOTS EXTENDED_GLOB

# --- Completion ---------------------------------------------------------------
fpath=("$HOME/.local/share/zsh/plugins/zsh-completions/src" $fpath)
autoload -Uz compinit
# full compinit once a day - matters on slow 32-bit hardware
if [[ -n $HOME/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$HOME/.cache/zsh/zcompcache"

# --- Plugins ------------------------------------------------------------------
ZPLUG="$HOME/.local/share/zsh/plugins"
[[ -f "$ZPLUG/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] \
  && source "$ZPLUG/zsh-autosuggestions/zsh-autosuggestions.zsh"
[[ -f "$ZPLUG/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh" ]] \
  && source "$ZPLUG/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh"

ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=40   # keeps typing snappy on slow CPUs

# --- Keys ---------------------------------------------------------------------
bindkey -e
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[3~' delete-char
bindkey '^ ' autosuggest-accept

# --- Our fragments ------------------------------------------------------------
for fragment in "$HOME"/.config/shell/*.zsh(N); do source "$fragment"; done
ZSHRC

  write_file "$SHELL_CONF_DIR/00-env.zsh" <<'ENV'
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
export EDITOR="${EDITOR:-nano}"
export VISUAL="$EDITOR"
export PAGER="less"
export LESS="-R -F -X"
command -v bat >/dev/null && export MANPAGER="sh -c 'col -bx | bat -l man -p'" && export MANROFFOPT="-c"

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

export NOTES="$HOME/notes"
export BAT_THEME="Catppuccin Mocha"
ENV

  # 10-tools.zsh: everything here is conditional, so a missing 32-bit tool
  # degrades instead of erroring on every prompt.
  write_file "$SHELL_CONF_DIR/10-tools.zsh" <<'TOOLS'
# --- fzf ----------------------------------------------------------------------
export FZF_DEFAULT_OPTS="
  --height 40% --layout=reverse --border --info=inline
  --prompt='> ' --pointer='>' --marker='+'
  --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8
  --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc
  --color=marker:#a6e3a1,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8
  --bind='ctrl-/:toggle-preview'
"
if command -v fd >/dev/null; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi
command -v bat >/dev/null \
  && export FZF_CTRL_T_OPTS="--preview 'bat -n --color=always --line-range :200 {}'"

# fzf key bindings live in different places depending on how it was installed
for f in "$HOME/.fzf/shell/key-bindings.zsh" \
         /usr/share/doc/fzf/examples/key-bindings.zsh \
         /usr/share/fzf/key-bindings.zsh; do
  [[ -f "$f" ]] && { source "$f"; break; }
done
for f in "$HOME/.fzf/shell/completion.zsh" \
         /usr/share/doc/fzf/examples/completion.zsh; do
  [[ -f "$f" ]] && { source "$f"; break; }
done

# --- zoxide -------------------------------------------------------------------
command -v zoxide >/dev/null && eval "$(zoxide init zsh --cmd cd)"

# --- prompt -------------------------------------------------------------------
if command -v starship >/dev/null; then
  eval "$(starship init zsh)"
else
  # Pure-zsh fallback prompt: no binary needed, costs nothing on old hardware.
  autoload -Uz vcs_info add-zsh-hook
  zstyle ':vcs_info:git:*' formats       ' %F{yellow}%b%f'
  zstyle ':vcs_info:git:*' actionformats ' %F{yellow}%b|%a%f'
  zstyle ':vcs_info:*' enable git
  add-zsh-hook precmd vcs_info
  setopt PROMPT_SUBST
  PROMPT='%F{blue}%~%f${vcs_info_msg_0_}
%(?.%F{green}.%F{red})>%f '
  RPROMPT='%F{8}%*%f'
fi
TOOLS

  # ---- aliases: written with icons, stripped afterwards when --ascii ---------
  write_file "$SHELL_CONF_DIR/20-aliases.zsh" <<'ALIASES'
# --- Listing ------------------------------------------------------------------
if command -v eza >/dev/null; then
  alias ls='eza --icons --group-directories-first'
  alias l='eza -l --icons --group-directories-first --git'
  alias ll='eza -la --icons --group-directories-first --git --header'
  alias lt='eza --tree --level=2 --icons --group-directories-first'
  alias lnew='eza -la --icons --sort=modified --reverse'
  alias lbig='eza -la --icons --sort=size --reverse'
else
  # No eza on i386: coreutils ls gets you most of the way there.
  alias ls='ls --color=auto --group-directories-first'
  alias l='ls -lh --color=auto'
  alias ll='ls -lah --color=auto'
  alias lt='tree -L 2'
  alias lnew='ls -laht --color=auto'
  alias lbig='ls -lahS --color=auto'
fi

# --- Viewing ------------------------------------------------------------------
command -v bat   >/dev/null && { alias cat='bat --paging=never'; alias catp='bat'; }
command -v dust  >/dev/null && alias du='dust'
command -v duf   >/dev/null && alias df='duf'
command -v procs >/dev/null && alias ps='procs'
command -v btop  >/dev/null && alias top='btop' || alias top='htop'
command -v ncdu  >/dev/null && alias usage='ncdu'

# rg and fd are NOT aliased over grep/find - different flags, and you will copy
# commands from the internet that expect the real thing.
alias rgi='rg -i'
alias rgh='rg --hidden --no-ignore'

# --- Moving around ------------------------------------------------------------
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'
alias down='cd ~/Downloads 2>/dev/null || cd ~/Descargas'
alias notes='cd "$NOTES"'

# --- Safety -------------------------------------------------------------------
alias cp='cp -i'
alias mv='mv -i'
alias mkdir='mkdir -p'
command -v trash-put >/dev/null && alias del='trash-put'

# --- Git ----------------------------------------------------------------------
command -v lazygit >/dev/null && alias lg='lazygit'
command -v tig     >/dev/null && alias tg='tig'
alias g='git'
alias gs='git status -sb'
alias ga='git add'
alias gaa='git add -A'
alias gc='git commit -m'
alias gca='git commit --amend --no-edit'
alias gp='git push'
alias gpl='git pull --rebase'
alias gd='git diff'
alias gds='git diff --staged'
alias glog='git log --oneline --graph --decorate --all -20'
alias gundo='git reset --soft HEAD~1'

# --- Files and system ---------------------------------------------------------
command -v mc >/dev/null && alias f='mc'
alias ports='ss -tulpn 2>/dev/null || netstat -tulpn'
alias myip='curl -s ifconfig.me; echo'
alias reload='exec zsh'
alias zshrc='$EDITOR ~/.zshrc'
alias aliases='$EDITOR ~/.config/shell/20-aliases.zsh'
alias path='echo $PATH | tr ":" "\n"'
ALIASES

  if ! $ICONS && ! $DRY_RUN; then
    sed -i 's/ --icons//g' "$SHELL_CONF_DIR/20-aliases.zsh"
    info "ascii mode: removed icon flags from listing aliases"
  fi

  write_file "$SHELL_CONF_DIR/30-functions.zsh" <<'FUNCS'
# --- Files --------------------------------------------------------------------
mkcd() { mkdir -p "$1" && cd "$1"; }

extract() {
  [[ -f "$1" ]] || { echo "No such file: $1"; return 1; }
  case "$1" in
    *.tar.bz2|*.tbz2) tar xjf "$1" ;;
    *.tar.gz|*.tgz)   tar xzf "$1" ;;
    *.tar.xz)         tar xJf "$1" ;;
    *.tar)            tar xf  "$1" ;;
    *.bz2)            bunzip2 "$1" ;;
    *.gz)             gunzip  "$1" ;;
    *.zip)            unzip   "$1" ;;
    *.7z|*.rar)       7z x    "$1" ;;
    *) echo "Unknown format: $1"; return 1 ;;
  esac
}

# ff -> pick a file, open it
ff() {
  local file
  if command -v bat >/dev/null; then
    file="$(fzf --preview 'bat -n --color=always --line-range :200 {}')" || return
  else
    file="$(fzf --preview 'head -200 {}')" || return
  fi
  [[ -n "$file" ]] && "${EDITOR}" "$file"
}

# search "text" -> grep inside files, jump to the hit
search() {
  [[ -z "$1" ]] && { echo "usage: search <text>"; return 1; }
  local hit
  hit="$(rg --line-number --no-heading --color=always --smart-case "$1" \
    | fzf --ansi --delimiter=: --preview 'head -80 {1}')" || return
  [[ -n "$hit" ]] && "${EDITOR}" "${hit%%:*}"
}

# --- Processes and git --------------------------------------------------------
fkill() {
  local pid
  pid="$(command ps -eo pid,ppid,%cpu,%mem,comm,args --sort=-%cpu \
        | sed 1d | fzf --header='Pick a process - Enter kills it' -m \
        | awk '{print $1}')" || return
  [[ -n "$pid" ]] && echo "$pid" | xargs -r kill -${1:-15} && echo "Terminated: $pid"
}

gb() {
  local branch
  branch="$(git branch --all --sort=-committerdate --format='%(refname:short)' \
      | fzf --preview 'git log --oneline --graph --color=always -20 {}')" || return
  [[ -n "$branch" ]] && git checkout "${branch#origin/}"
}

gl() {
  git log --oneline --color=always --decorate \
    | fzf --ansi --preview 'git show --color=always {1}' --preview-window=right:55%
}

# --- Notes --------------------------------------------------------------------
n() {
  mkdir -p "$NOTES"
  if [[ -n "$1" ]]; then
    "${EDITOR}" "$NOTES/$(date +%Y-%m-%d)-${1// /-}.md"
  else
    local note
    if command -v fd >/dev/null; then
      note="$(fd -e md . "$NOTES" 2>/dev/null | fzf)" || return
    else
      note="$(find "$NOTES" -name '*.md' 2>/dev/null | fzf)" || return
    fi
    [[ -n "$note" ]] && "${EDITOR}" "$note"
  fi
}

today() { mkdir -p "$NOTES/journal"; "${EDITOR}" "$NOTES/journal/$(date +%Y-%m-%d).md"; }

# --- Everyday -----------------------------------------------------------------
weather() { curl -s "https://wttr.in/${1:-}?m" | head -n 37; }
qr()      { curl -s "https://qrenco.de/${1:?usage: qr <text|url>}"; }
serve()   { command -v python3 >/dev/null && python3 -m http.server "${1:-8000}" || echo "python3 missing"; }
port()    { ss -tulpn 2>/dev/null | grep ":${1:?usage: port <number>}"; }

ytdl()  { yt-dlp -f 'bv*[height<=720]+ba/b' -o '%(title)s.%(ext)s' "$@"; }
ytmp3() { yt-dlp -x --audio-format mp3 -o '%(title)s.%(ext)s' "$@"; }

shrink() {
  local im; im="$(command -v magick || command -v convert)" || { echo "ImageMagick missing"; return 1; }
  "$im" "$1" -resize "${2:-1600}x${2:-1600}>" -quality 85 "small-$1" && echo "-> small-$1"
}

pdfjoin() { pdfunite "$@" merged.pdf && echo "-> merged.pdf"; }
pdftext() { pdftotext -layout "$1" - | ${PAGER}; }

# clip -> xclip if there is an X session, otherwise OSC-52, which travels
# through SSH and lands in your local clipboard (Tabby, WezTerm, kitty...).
clip() {
  local data; data="$(command cat)"
  if command -v xclip >/dev/null && [[ -n "${DISPLAY:-}" ]]; then
    printf '%s' "$data" | xclip -selection clipboard
  else
    printf '\033]52;c;%s\a' "$(printf '%s' "$data" | base64 | tr -d '\n')"
  fi
}

# --- System -------------------------------------------------------------------
sys() {
  printf '  %-8s %s\n' \
    "host"   "$(id -un)@$(hostname)" \
    "os"     "$( . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}")" \
    "arch"   "$(uname -m)" \
    "kernel" "$(uname -r)" \
    "uptime" "$(uptime -p 2>/dev/null | sed 's/^up //')" \
    "memory" "$(free -m | awk 'NR==2 {print $3"M / "$2"M"}')" \
    "disk"   "$(df -h / | awk 'NR==2 {print $4" free of "$2}')" \
    "time"   "$(date '+%a %Y-%m-%d %H:%M')"
}

update() {
  echo "-- system --"
  sudo apt-get update -qq && sudo apt-get upgrade -y
  echo "-- zsh plugins --"
  for d in "$HOME"/.local/share/zsh/plugins/*/; do
    [[ -d "$d/.git" ]] && git -C "$d" pull --quiet --ff-only && echo "  ok $(basename "$d")"
  done
  command -v yt-dlp >/dev/null && yt-dlp -U 2>/dev/null
  echo "Done."
}

cheat() { bat --style=plain "$HOME/.local/share/setup-cli/cheatsheet.md" 2>/dev/null \
          || command cat "$HOME/.local/share/setup-cli/cheatsheet.md"; }
FUNCS

  if [[ ! -f "$SHELL_CONF_DIR/99-local.zsh" ]]; then
    write_file "$SHELL_CONF_DIR/99-local.zsh" <<'LOCAL'
# Your own stuff. NEVER overwritten when you re-run the script.
LOCAL
  else
    info "99-local.zsh left alone (it's yours)"
  fi

  # ---- starship config, only if starship actually made it onto the box ------
  if have starship || $DRY_RUN; then
    if $ICONS; then
      write_file "$CONF_DIR/starship.toml" <<'STAR_ICONS'
"$schema" = 'https://starship.rs/config-schema.json'
add_newline = true
command_timeout = 1500          # generous: 32-bit CPUs are slow

format = """
$directory$git_branch$git_status$cmd_duration
$character"""

[directory]
style = "bold blue"
format = "[ $path ]($style)[$read_only]($read_only_style)"
truncation_length = 3
truncate_to_repo = true
read_only = " "
read_only_style = "red"

[git_branch]
symbol = " "
style = "yellow"
format = "[on $symbol$branch ]($style)"

[git_status]
style = "red"
format = '([$all_status$ahead_behind]($style) )'
ahead = "^${count} "
behind = "v${count} "
diverged = "^v "
untracked = "?${count} "
modified = "!${count} "
staged = "+${count} "

[cmd_duration]
min_time = 2000
style = "purple"
format = "[took $duration]($style)"

[character]
success_symbol = "[>](bold green)"
error_symbol = "[>](bold red)"

# Language modules off by default: each one costs a subprocess per prompt,
# which you feel on this hardware. Enable the ones you actually use.
[nodejs]
disabled = true
[python]
disabled = true
[rust]
disabled = true
[package]
disabled = true
STAR_ICONS
    else
      write_file "$CONF_DIR/starship.toml" <<'STAR_ASCII'
"$schema" = 'https://starship.rs/config-schema.json'
add_newline = true
command_timeout = 1500

format = """
$directory$git_branch$git_status$cmd_duration
$character"""

[directory]
style = "bold blue"
format = "[ $path ]($style)"
truncation_length = 3
truncate_to_repo = true

[git_branch]
symbol = ""
style = "yellow"
format = "[on $branch ]($style)"

[git_status]
style = "red"
format = '([$all_status$ahead_behind]($style) )'
ahead = "^${count} "
behind = "v${count} "
diverged = "^v "
untracked = "?${count} "
modified = "!${count} "
staged = "+${count} "

[cmd_duration]
min_time = 2000
style = "purple"
format = "[took $duration]($style)"

[character]
success_symbol = "[>](bold green)"
error_symbol = "[>](bold red)"

[nodejs]
disabled = true
[python]
disabled = true
[rust]
disabled = true
[package]
disabled = true
STAR_ASCII
    fi
  else
    info "starship not present: the pure-zsh prompt in 10-tools.zsh takes over"
  fi

  # ---- git ------------------------------------------------------------------
  if ! $DRY_RUN && have git; then
    if have delta; then
      git config --global core.pager "delta"
      git config --global interactive.diffFilter "delta --color-only"
      git config --global delta.navigate true
      git config --global delta.line-numbers true
      ok "git uses delta for diffs"
    else
      git config --global core.pager "less -R"
      git config --global color.ui auto
      info "no delta: git keeps its own colored diff"
    fi
    git config --global init.defaultBranch main
    git config --global pull.rebase true
  fi
}

mod_theme() {
  step "Catppuccin Mocha for bat"
  if $DRY_RUN; then info "> would apply the bat theme"; return 0; fi
  have bat || { info "bat not installed, nothing to theme"; return 0; }

  local bat_themes="$CONF_DIR/bat/themes"
  mkdir -p "$bat_themes"
  if [[ ! -f "$bat_themes/Catppuccin Mocha.tmTheme" ]]; then
    curl -fsSL --max-time 60 -o "$bat_themes/Catppuccin Mocha.tmTheme" \
      "https://raw.githubusercontent.com/catppuccin/bat/main/themes/Catppuccin%20Mocha.tmTheme" \
      && ok "bat theme downloaded" || warn "could not download the bat theme"
  else
    info "bat theme already present"
  fi

  write_file "$CONF_DIR/bat/config" <<'BATCONF'
--theme="Catppuccin Mocha"
--style="numbers,changes,header"
BATCONF

  bat cache --build >/dev/null 2>&1 && ok "bat cache rebuilt" || true
}

mod_cheatsheet() {
  step "Cheatsheet"

  write_file "$STATE_DIR/cheatsheet.md" <<'CHEAT'
# Cheatsheet - antiX core CLI

Some commands below only exist if the tool had a 32-bit build.
Run `cheat` any time. Run `sys` for a system summary.

## Key bindings
| Key           | What it does                                  |
|---------------|-----------------------------------------------|
| `Ctrl+R`      | Fuzzy search through shell history (fzf)      |
| `Ctrl+T`      | Pick a file, with preview                     |
| `Alt+C`       | Jump to a directory                           |
| `Ctrl+Space`  | Accept the grey suggestion                    |
| `Up` / `Down` | History filtered by what you already typed    |

## Commands that changed
| Before  | Now                | Notes                              |
|---------|--------------------|------------------------------------|
| `ls`    | `eza` or `ls`      | `l` `ll` `lt` `lnew` `lbig`        |
| `cat`   | `bat`              | `catp` to page                     |
| `grep`  | `rg` (by name)     | `rgi` ignore case, `rgh` hidden    |
| `find`  | `fd` (by name)     | human syntax                       |
| `cd`    | `zoxide`           | `cd partial-name` jumps there      |
| `top`   | `btop` or `htop`   | whichever installed                |
| `du`    | `dust` or `usage`  | `usage` runs ncdu                  |
| `rm`    | `del`              | trash, recoverable (if trash-cli)  |

## Functions
| Command               | What it does                                |
|-----------------------|---------------------------------------------|
| `ff`                  | Find a file, open it                        |
| `search "text"`       | Grep inside files, jump to the hit          |
| `fkill`               | Pick a process from a list and kill it      |
| `gb` / `gl`           | Pick a git branch / browse the git log      |
| `n` / `n "title"`     | Open or create a note                       |
| `today`               | Today's journal entry                       |
| `weather [city]`      | Forecast                                    |
| `ytdl` / `ytmp3`      | Download video (720p cap) or audio          |
| `shrink photo.jpg`    | Resize and compress an image                |
| `pdfjoin` / `pdftext` | Merge PDFs / read a PDF as text             |
| `extract file`        | Unpack anything                             |
| `serve [port]`        | Web server for the current directory        |
| `port 8080`           | Who is listening there                      |
| `qr "text"`           | QR code in the terminal                     |
| `mkcd dir`            | Create a directory and step in              |
| `clip`                | Pipe into the clipboard (OSC-52 over SSH)   |
| `sys`                 | System summary                              |
| `update`              | Update system, plugins, yt-dlp              |
| `cheat`               | Show this again                             |

## Full-screen tools
| Command | For what                                       |
|---------|------------------------------------------------|
| `f`     | Midnight Commander - two-pane file manager     |
| `lg`    | lazygit, if the 32-bit build was available     |
| `tg`    | tig, the fallback git browser                  |
| `htop`  | Processes                                      |
| `tmux`  | Panes and sessions that survive disconnects    |
| `task`  | Task manager                                   |

## Notes for 32-bit
- Most Rust/Go CLI tools ship x86_64 only. This setup leans on Debian's i386
  packages, which are maintained and complete.
- `tmux` replaces zellij, `mc` replaces yazi, `fzf` Ctrl+R replaces atuin.
- If starship had no i686 build, the prompt is pure zsh with git info. It is
  lighter, and honestly hard to tell apart.

## Where to change things
- `~/.zshrc` - only loads, don't edit
- `~/.config/shell/20-aliases.zsh` - aliases (`aliases`)
- `~/.config/shell/30-functions.zsh` - functions
- `~/.config/shell/99-local.zsh` - yours, never overwritten
- `~/.config/starship.toml` - prompt, if starship is installed
CHEAT
  ok "saved to $STATE_DIR/cheatsheet.md  (command: cheat)"
}

# ==============================================================================
#  Wrap-up
# ==============================================================================

final_summary() {
  printf '\n'; hr
  printf '%s  Done%s\n\n' "$C_GREEN$C_BOLD" "$C_RESET"

  [[ ${#INSTALLED[@]} -gt 0 ]] && printf '  %sInstalled:%s %s\n\n' "$C_BOLD" "$C_RESET" "${INSTALLED[*]}"
  [[ ${#SKIPPED[@]}   -gt 0 ]] && printf '  %sSkipped:%s %s\n\n'   "$C_AMBER" "$C_RESET" "${SKIPPED[*]}"

  if [[ ${#FALLBACKS[@]} -gt 0 ]]; then
    printf '  %s32-bit substitutions:%s\n' "$C_BOLD" "$C_RESET"
    for f in "${FALLBACKS[@]}"; do printf '    - %s\n' "$f"; done
    printf '\n'
  fi

  if [[ ${#FAILED[@]} -gt 0 ]]; then
    printf '  %sFailed:%s %s\n' "$C_RED" "$C_RESET" "${FAILED[*]}"
    printf '  %sRetry just those: bash %s --only=<module>%s\n\n' "$C_GREY" "$SCRIPT_NAME" "$C_RESET"
  fi

  [[ -d "$BACKUP_DIR" ]] && printf '  %sBackup:%s %s\n\n' "$C_GREY" "$C_RESET" "$BACKUP_DIR"

  printf '  %sNext steps:%s\n' "$C_BOLD" "$C_RESET"
  printf '    1. Log out and back in, or run: %sexec zsh%s\n' "$C_MAUVE" "$C_RESET"
  printf '    2. Run %scheat%s for the full list, %ssys%s for system info.\n' \
    "$C_MAUVE" "$C_RESET" "$C_MAUVE" "$C_RESET"
  if $ICONS; then
    printf '    3. Icons need a Nerd Font on the machine running your terminal,\n'
    printf '       not on this box. If you see boxes, re-run with %s--ascii%s.\n' "$C_MAUVE" "$C_RESET"
  fi
  printf '    4. Try: %sCtrl+R%s, %sll%s, %sf%s, %sff%s, %sweather%s\n\n' \
    "$C_PINK" "$C_RESET" "$C_PINK" "$C_RESET" "$C_PINK" "$C_RESET" \
    "$C_PINK" "$C_RESET" "$C_PINK" "$C_RESET"
  hr

  $DRY_RUN && printf '\n  %sThat was a dry run: nothing was changed.%s\n\n' "$C_AMBER" "$C_RESET"
  return 0
}

on_error() {
  local code=$? line=${1:-?}
  printf '\n%sScript stopped%s at line %s (exit %s).\n' "$C_RED$C_BOLD" "$C_RESET" "$line" "$code" >&2
  [[ -d "$BACKUP_DIR" ]] && printf '  Your original files are still in: %s\n' "$BACKUP_DIR" >&2
  exit "$code"
}
trap 'on_error $LINENO' ERR

main() {
  banner
  preflight

  if ! $IS_32BIT; then
    warn "This build is tuned for 32-bit (i386). You are on $ARCH_DEB;"
    warn "it will still work, but the 64-bit version installs more tools."
  fi

  printf '\n  %smodules:%s %s\n' "$C_GREY" "$C_RESET" "${MODULES[*]}"
  $ICONS || printf '  %sascii mode: no Nerd Font glyphs%s\n' "$C_GREY" "$C_RESET"
  $DRY_RUN && printf '  %sdry run: nothing will be modified.%s\n' "$C_AMBER" "$C_RESET"

  if ! $DRY_RUN && ! $ASSUME_YES; then
    printf '\n'; confirm "Start?" || { say "  Cancelled."; exit 0; }
  fi

  for m in "${MODULES[@]}"; do
    "mod_$m" || warn "module '$m' finished with warnings"
  done

  final_summary
}

main "$@"
