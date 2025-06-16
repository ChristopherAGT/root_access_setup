#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════╗
# ║       🔐 SCRIPT DE CONFIGURACIÓN DE ROOT Y SSH                                    ║
# ║       👾 Autor: ChristopherAGT - Guatemalteco 🇬🇹                                  ║
# ╚══════════════════════════════════════════════════════════════════════╝

# 🎨 Colores y formato
VERDE="\033[1;32m"
ROJO="\033[1;31m"
AMARILLO="\033[1;33m"
AZUL="\033[1;34m"
NEGRITA="\033[1m"
NEUTRO="\033[0m"

# 🌀 Spinner para comandos largos
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

# 🖼️ Sección visual destacada
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

# 🌎 Detectar sistema operativo
detect_os() {
  if [ -e /etc/os-release ]; then
    . /etc/os-release
    OS_ID="$ID"
    OS_NAME="$NAME"
  else
    echo -e "${ROJO}❌ No se pudo detectar el sistema operativo.${NEUTRO}"
    exit 1
  fi
}
detect_os

clear
print_section "⚙️ INICIANDO CONFIGURACIÓN DE ROOT Y SSH EN $OS_NAME"

# 🧹 Limpiar iptables
print_section "🧹 LIMPIANDO REGLAS DE IPTABLES"
echo -e "🔄 Limpiando reglas de iptables..."
iptables -F || echo -e "${ROJO}❌ Error al limpiar iptables.${NEUTRO}"

# ➕ Permitir tráfico básico
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# 🌐 Configurar DNS
print_section "🌍 CONFIGURANDO DNS DE CLOUDFLARE Y GOOGLE"
echo -e "🔄 Estableciendo DNS..."
chattr -i /etc/resolv.conf 2>/dev/null
cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
chattr +i /etc/resolv.conf 2>/dev/null

# 📦 Actualizar sistema según distro
print_section "📦 ACTUALIZANDO EL SISTEMA"
echo -e "🔄 Ejecutando actualización..."
case "$OS_ID" in
  debian|ubuntu)
    spinner apt update -y
    ;;
  centos|rhel|rocky|almalinux)
    spinner yum update -y
    ;;
  arch)
    spinner pacman -Syu --noconfirm
    ;;
  *)
    echo -e "${ROJO}⚠️ Sistema no compatible para actualización automática.${NEUTRO}"
    ;;
esac

# 🔧 Configurar acceso root por SSH
print_section "🔧 CONFIGURANDO ACCESO ROOT POR SSH"

SSH_CONFIG="/etc/ssh/sshd_config"
SSH_CONFIG_CLOUDIMG="/etc/ssh/sshd_config.d/60-cloudimg-settings.conf"

[[ -f "$SSH_CONFIG" ]] && cp "$SSH_CONFIG" "${SSH_CONFIG}.bak"

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

[[ -f "$SSH_CONFIG_CLOUDIMG" ]] && sed -i "s/^PasswordAuthentication no/PasswordAuthentication yes/" "$SSH_CONFIG_CLOUDIMG"

# Verificar SSH
if ! sshd -t 2>/tmp/sshd_error.log; then
  echo -e "${ROJO}❌ Error en configuración SSHD:${NEUTRO}"
  cat /tmp/sshd_error.log
  exit 1
fi

# Reiniciar SSH
echo -e "🔄 Reiniciando SSH..."
if systemctl restart ssh 2>/dev/null || service ssh restart; then
  echo -e "${VERDE}✅ SSH reiniciado correctamente.${NEUTRO}"
else
  echo -e "${ROJO}❌ Fallo al reiniciar SSH.${NEUTRO}"
  exit 1
fi

# 🔐 Cambiar contraseña root
print_section "🔐 CONFIGURANDO CONTRASEÑA DE ROOT"

while true; do
  echo -ne "${VERDE}${NEGRITA}📝 Ingresa nueva contraseña para ROOT:${NEUTRO} "
  read -s pass1
  echo
  echo -ne "${VERDE}${NEGRITA}🔁 Confirma la contraseña:${NEUTRO} "
  read -s pass2
  echo
  if [[ -z "$pass1" ]]; then
    echo -e "${ROJO}❌ No se ingresó ninguna contraseña. Cancelando...${NEUTRO}"
    exit 1
  elif [[ "$pass1" != "$pass2" ]]; then
    echo -e "${ROJO}❌ Las contraseñas no coinciden. Intenta de nuevo.${NEUTRO}"
  else
    echo "root:$pass1" | chpasswd
    echo -e "${VERDE}✅ Contraseña actualizada correctamente.${NEUTRO}"
    break
  fi
done

# 🛡️ Advertencia de seguridad
echo -e "\n${ROJO}${NEGRITA}⚠️ IMPORTANTE:${NEUTRO} El acceso root por contraseña está habilitado."
echo -e "${ROJO}Se recomienda usar medidas de seguridad adicionales (fail2ban, firewall, VPN).${NEUTRO}"

# 🧾 RESUMEN DE CONFIGURACIÓN
print_section "📄 RESUMEN DE CONFIGURACIÓN"

echo -e "${VERDE}✔ Acceso root por SSH habilitado"
echo -e "✔ Contraseña de root actualizada"
echo -e "✔ DNS configurado (1.1.1.1 y 8.8.8.8)"
echo -e "✔ Reglas básicas de iptables aplicadas"
echo -e "✔ Sistema actualizado (${OS_NAME})"
echo -e "\n${AZUL}ℹ Puedes conectarte vía SSH así:${NEUTRO}"
echo -e "${AZUL}ℹ Puedes conectarte vía SSH así:${NEUTRO}"

# IP privada (red interna)
#echo -e "${NEGRITA}➡️ root@$(hostname -I | awk '{print $1}')${NEUTRO}"

# IP pública (internet)
PUBLIC_IP=$(curl -s ifconfig.co)
if [[ -n "$PUBLIC_IP" ]]; then
  echo -e "${NEGRITA}➡️ root@${PUBLIC_IP}${NEUTRO}"
fi

# 🎉 MENSAJE FINAL
print_section "✅️ CONFIGURACIÓN COMPLETA Y SERVICIO LISTO"
