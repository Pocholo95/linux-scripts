#!/usr/bin/env bash
# ============================================================
# setup-vim.sh — Instala vim y aplica configuración sólida
# Uso: bash setup-vim.sh
# ============================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1"; exit 1; }

echo ""
echo "  vim setup script"
echo "  ========================"
echo ""

# ── 1. Instalar vim si no está ──────────────────────────────
if command -v vim &>/dev/null; then
    ok "vim ya está instalado ($(vim --version | head -1 | cut -d' ' -f1-5))"
else
    warn "vim no encontrado, instalando..."

    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y vim
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y vim
    elif command -v yum &>/dev/null; then
        sudo yum install -y vim
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm vim
    elif command -v apk &>/dev/null; then
        sudo apk add --no-cache vim
    else
        err "No se reconoció el gestor de paquetes. Instala vim manualmente."
    fi

    ok "vim instalado correctamente"
fi

# ── 2. Crear carpeta para undodir ───────────────────────────
UNDODIR="$HOME/.vim/undodir"
mkdir -p "$UNDODIR"
ok "carpeta undodir lista → $UNDODIR"

# ── 3. Backup del .vimrc existente ──────────────────────────
VIMRC="$HOME/.vimrc"
if [[ -f "$VIMRC" ]]; then
    BACKUP="$VIMRC.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$VIMRC" "$BACKUP"
    warn "backup del .vimrc anterior guardado en $BACKUP"
fi

# ── 4. Escribir la nueva configuración ──────────────────────
cat > "$VIMRC" << 'EOF'
" ===========================
" Apariencia y UI
" ===========================
set number
set cursorline
set scrolloff=5
set wrap
set linebreak
set showmatch
set laststatus=2
set ruler
set showcmd
set wildmenu
set ttyfast
set lazyredraw

" ===========================
" Comportamiento del editor
" ===========================
set nocompatible
set backspace=indent,eol,start
set mouse=a
set clipboard=unnamedplus
set encoding=utf-8
set hidden
set confirm
set undolevels=1000
set updatetime=300

" ===========================
" Indentado
" ===========================
set autoindent
set smartindent
set tabstop=4
set shiftwidth=4
set expandtab
set softtabstop=4

" ===========================
" Búsqueda
" ===========================
set incsearch
set hlsearch
set ignorecase
set smartcase

" ===========================
" Archivos de respaldo
" ===========================
set noswapfile
set nobackup
set undofile
set undodir=~/.vim/undodir

" ===========================
" Atajos útiles (leader = space)
" ===========================
let mapleader = " "

" limpiar resaltado de búsqueda con Esc
nnoremap <Esc> :noh<CR><Esc>

" guardar con Ctrl+S en modo normal e inserción
nnoremap <C-s> :w<CR>
inoremap <C-s> <Esc>:w<CR>a

" mover líneas con Alt+j/k
nnoremap <A-j> :m .+1<CR>==
nnoremap <A-k> :m .-2<CR>==

" navegación entre splits con Ctrl+hjkl
nnoremap <C-h> <C-w>h
nnoremap <C-l> <C-w>l
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k

" ===========================
" Sintaxis y colores
" ===========================
syntax on
filetype plugin indent on
set background=dark
colorscheme desert
EOF

ok "configuración aplicada → $VIMRC"

# ── 5. Resultado final ──────────────────────────────────────
echo ""
echo "  Listo. Abre vim para probarlo:"
echo "  vim ~/.vimrc"
echo ""
