#!/bin/bash

# ╔════════════════════════════════════════════════════════════════════╗
# ║       🔐 CONFIGURACIÓN DE ROOT Y SSH                                ║
# ║       👤 Autor: ChristopherAGT                                      ║
# ║       🛠️ Script para configurar acceso root SSH y actualizar sistema║
# ╚════════════════════════════════════════════════════════════════════╝

# Colores para presentación
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RED="\033[1;31m"
MAGENTA="\033[1;35m"
RESET="\033[0m"

# Función para imprimir sección con borde
print_section() {
  local title="$1"
  echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${MAGENTA}║  $title${RESET}$(printf ' %.0s' {1..$(($(tput cols)-${#title}-4))})${MAGENTA}║${RESET}"
  echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${RESET}"
}

# Función para mostrar spinner y manejar errores
run_with_spinner() {
  local msg="$1"
  local cmd="$2"

  echo -ne "${CYAN}${msg}...${RESET}"
  bash -c "$cmd" &>/tmp/root_ssh_spinner.log &
  local pid=$!

  local delay=0.1
  local spinstr='|/-\'
  while kill -0 $pid 2>/dev/null; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  wait $pid
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    echo -e " ${GREEN}✔️${RESET}"
  else
    echo -e " ${RED}❌ Error${RESET}"
    echo -e "${RED}🛑 Ocurrió un error al ejecutar:${RESET} ${YELLOW}$msg${RESET}"
    echo -e "${RED}📄 Detalles del error:${RESET}"
    cat /tmp/root_ssh_spinner.log
    rm -f /tmp/root_ssh_spinner.log
    exit 1
  fi
  rm -f /tmp/root_ssh_spinner.log
}

# Verificar si se ejecuta como root
if [[ "$EUID" -ne 0 ]]; then
  echo -e "${RED}⚠️ Este script requiere permisos de administrador.${RESET}"
  echo -e "${YELLOW}🔁 Reintentando con sudo...${RESET}\n"
  exec sudo bash "$0" "$@"
fi

clear

print_section "🔐 INICIANDO CONFIGURACIÓN DE ROOT Y SSH"

print_section "🧹 LIMPIANDO REGLAS DE IPTABLES"
run_with_spinner "🔄 Limpiando reglas iptables" "iptables -F"

print_section "🌍 CONFIGURANDO DNS DE CLOUDFLARE Y GOOGLE"
run_with_spinner "🔄 Actualizando /etc/resolv.conf" "bash -c 'chattr -i /etc/resolv.conf 2>/dev/null && echo -e \"nameserver 1.1.1.1\nnameserver 8.8.8.8\" > /etc/resolv.conf'"

print_section "📦 ACTUALIZANDO EL SISTEMA"
run_with_spinner "🔄 Ejecutando apt update y upgrade" "apt update -y && apt upgrade -y"

print_section "🔧 CONFIGURANDO ACCESO ROOT POR SSH"
SSH_CONFIG="/etc/ssh/sshd_config"
SSH_CONFIG_CLOUDIMG="/etc/ssh/sshd_config.d/60-cloudimg-settings.conf"

# Backup antes de modificar
run_with_spinner "🔄 Creando backup de sshd_config" "cp $SSH_CONFIG ${SSH_CONFIG}.bak"

# Cambiar configuración para permitir root y password
run_with_spinner "🔄 Modificando $SSH_CONFIG para permitir root y password" "sed -i \
    -e 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' \
    -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' \
    $SSH_CONFIG"

if [[ -f "$SSH_CONFIG_CLOUDIMG" ]]; then
  run_with_spinner "🔄 Modificando $SSH_CONFIG_CLOUDIMG para PasswordAuthentication yes" "sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' $SSH_CONFIG_CLOUDIMG"
fi

run_with_spinner "🔄 Reiniciando servicio SSH" "systemctl restart ssh || service ssh restart"

print_section "🔐 CONFIGURANDO CONTRASEÑA DE ROOT"

echo -ne "${GREEN}📝 Ingrese nueva contraseña para root: ${RESET}"
read -s pass_root
echo

if [[ -z "$pass_root" ]]; then
  echo -e "${RED}❌ No ingresaste contraseña. Abortando...${RESET}"
  exit 1
fi

run_with_spinner "🔄 Actualizando contraseña de root" "echo 'root:$pass_root' | chpasswd"

echo -e "${GREEN}✅ Contraseña de root actualizada correctamente.${RESET}"

echo -e "\n${RED}⚠️ IMPORTANTE:${RESET} Este script habilita acceso SSH root con contraseña."
echo -e "${YELLOW}Se recomienda usar junto con medidas de seguridad (firewall, fail2ban, VPN).${RESET}"

print_section "🎉 SCRIPT FINALIZADO CON ÉXITO"
