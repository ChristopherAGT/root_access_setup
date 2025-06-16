#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════╗
# ║       🔐 SCRIPT DE CONFIGURACIÓN DE ROOT Y SSH                       ║
# ║           Autor: ChristopherAGT - Guatemalteco 🇬🇹                   ║
# ╚══════════════════════════════════════════════════════════════════════╝

# 🎨 Colores y formato
VERDE="\033[1;32m"
ROJO="\033[1;31m"
AMARILLO="\033[1;33m"
AZUL="\033[1;34m"
NEGRITA="\033[1m"
NEUTRO="\033[0m"

# 🌀 Spinner de carga (solo para comandos largos)
spinner() {
  local pid
  "$@" &> /dev/null &
  pid=$!
  local delay=0.1
  local spinstr='|/-\'
  echo -ne "${AMARILLO}"
  while ps -p $pid &>/dev/null; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  wait $pid 2>/dev/null
  echo -ne "${NEUTRO}"
}

# 📦 Imprimir sección visual
print_section() {
  local title="$1"
  echo -e "${AZUL}${NEGRITA}"
  echo "╔════════════════════════════════════════════════════════════════╗"
  printf "║  %-60s ║\n" "$title"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo -e "${NEUTRO}"
}

# ⚠️ Verificar si se ejecuta como root
if [[ "$EUID" -ne 0 ]]; then
  echo -e "${ROJO}⚠️ Este script requiere permisos de administrador.${NEUTRO}"
  echo -e "${AMARILLO}🔁 Reintentando con sudo...${NEUTRO}\n"
  exec sudo bash "$0" "$@"
fi

clear
print_section "🔐 INICIANDO CONFIGURACIÓN DE ROOT Y SSH"

# 🧹 Limpiar iptables
print_section "🧹 LIMPIANDO REGLAS DE IPTABLES"
echo -e "🔄 Limpiando reglas de iptables..."
iptables -F || echo -e "${ROJO}❌ Error al limpiar iptables.${NEUTRO}"

# ➕ Permitir tráfico esencial
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# 🌐 Configurar DNS
print_section "🌍 CONFIGURANDO DNS DE CLOUDFLARE Y GOOGLE"
echo -e "🔄 Estableciendo DNS de Cloudflare y Google..."
chattr -i /etc/resolv.conf 2>/dev/null
cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
chattr +i /etc/resolv.conf 2>/dev/null

# 📦 Actualizar paquetes
print_section "📦 ACTUALIZANDO EL SISTEMA"
echo -e "🔄 Ejecutando apt update..."
spinner apt update -y

# 🔧 Configuración SSH
print_section "🔧 CONFIGURANDO ACCESO ROOT POR SSH"

SSH_CONFIG="/etc/ssh/sshd_config"
SSH_CONFIG_CLOUDIMG="/etc/ssh/sshd_config.d/60-cloudimg-settings.conf"

# Backup
if [[ -f "$SSH_CONFIG" ]]; then
  cp "$SSH_CONFIG" "${SSH_CONFIG}.bak"
fi

# Función para establecer o agregar directivas SSH
set_ssh_option() {
  local key="$1"
  local value="$2"
  if grep -qE "^#?\s*${key}" "$SSH_CONFIG"; then
    sed -i "s|^#\?\s*${key}.*|${key} ${value}|" "$SSH_CONFIG"
  else
    echo "${key} ${value}" >> "$SSH_CONFIG"
  fi
}

set_ssh_option "PermitRootLogin" "yes"
set_ssh_option "PasswordAuthentication" "yes"

if [[ -f "$SSH_CONFIG_CLOUDIMG" ]]; then
  sed -i "s/^PasswordAuthentication no/PasswordAuthentication yes/" "$SSH_CONFIG_CLOUDIMG"
fi

# Verificar configuración
if ! sshd -t 2>/tmp/sshd_error.log; then
  echo -e "${ROJO}❌ Error en configuración SSHD:${NEUTRO}"
  cat /tmp/sshd_error.log
  exit 1
fi

# Reiniciar SSH
echo -e "🔄 Reiniciando SSH para aplicar cambios..."
if systemctl restart ssh 2>/dev/null || service ssh restart; then
  echo -e "${VERDE}✅ SSH reiniciado correctamente.${NEUTRO}"
else
  echo -e "${ROJO}❌ Fallo al reiniciar el servicio SSH.${NEUTRO}"
  exit 1
fi

# 🔐 Cambiar contraseña root
print_section "🔐 CONFIGURANDO CONTRASEÑA DE ROOT"

while true; do
  echo -ne "${VERDE}${NEGRITA}📝 Ingresa la nueva contraseña para el usuario ROOT:${NEUTRO} "
  read -s pass1
  echo
  echo -ne "${VERDE}${NEGRITA}🔁 Confirma la nueva contraseña:${NEUTRO} "
  read -s pass2
  echo
  if [[ -z "$pass1" ]]; then
    echo -e "${ROJO}❌ No ingresaste ninguna contraseña. Cancelando...${NEUTRO}"
    exit 1
  elif [[ "$pass1" != "$pass2" ]]; then
    echo -e "${ROJO}❌ Las contraseñas no coinciden. Intenta de nuevo.${NEUTRO}"
  else
    echo "root:$pass1" | chpasswd
    echo -e "${VERDE}✅ Contraseña actualizada correctamente.${NEUTRO}"
    break
  fi
done

# ⚠️ Advertencia de seguridad
echo -e "\n${ROJO}${NEGRITA}⚠️ IMPORTANTE:${NEUTRO} Este script habilita el acceso SSH root con contraseña."
echo -e "${ROJO}Se recomienda combinarlo con medidas de seguridad como fail2ban, firewall o VPN.${NEUTRO}"

# 🎉 Final
print_section "🎉 SCRIPT FINALIZADO CON ÉXITO"
