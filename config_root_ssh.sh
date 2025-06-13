#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════╗
# ║                🔐 SCRIPT DE CONFIGURACIÓN DE ROOT Y SSH (MEJORADO)               ║
# ║                  Autor: ChristopherAGT - Guatemalteco 🇬🇹                         ║
# ╚══════════════════════════════════════════════════════════════════════╝

# 🎨 Colores y estilos
VERDE="\033[1;32m"
ROJO="\033[1;31m"
AMARILLO="\033[1;33m"
AZUL="\033[1;34m"
NEGRITA="\033[1m"
NEUTRO="\033[0m"

# ⏳ Spinner para tareas en segundo plano
spinner() {
  local pid=$!
  local delay=0.1
  local spinstr='|/-\'
  echo -ne "${AMARILLO}"
  while [ "$(ps a | awk '{print $1}' | grep "$pid")" ]; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  echo -ne "${NEUTRO}"
}

# 🛡️ Asegurar ejecución como root o relanzar con sudo
if [[ "$EUID" -ne 0 ]]; then
  echo -e "${ROJO}⚠️ Este script requiere permisos de administrador.${NEUTRO}"
  echo -e "${AMARILLO}🔁 Reintentando con sudo...${NEUTRO}\n"
  exec sudo bash "$0" "$@"
fi

clear
echo -e "${AZUL}${NEGRITA}╔════════════════════════════════════════════╗"
echo -e "║      🔐 CONFIGURACIÓN ROOT Y SSH           ║"
echo -e "╚════════════════════════════════════════════╝${NEUTRO}\n"

# 🌍 Establecer DNS públicos confiables
echo -e "${AMARILLO}🌐 Configurando DNS de Cloudflare y Google...${NEUTRO}"
cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# 🔄 Actualización de paquetes
echo -e "${AZUL}📦 Actualizando lista de paquetes...${NEUTRO}"
apt update -y & spinner

# 🔧 Configuración de SSH
SSH_CONFIG="/etc/ssh/sshd_config"
SSH_CONFIG_CLOUDIMG="/etc/ssh/sshd_config.d/60-cloudimg-settings.conf"

echo -e "${AMARILLO}🔐 Configurando acceso root y autenticación por contraseña en SSH...${NEUTRO}"

# Función para reemplazar o agregar líneas de configuración
reemplazar_o_agregar() {
  local archivo="$1"
  local buscar="$2"
  local reemplazo="$3"
  if grep -q "$buscar" "$archivo"; then
    sed -i "s/$buscar/$reemplazo/g" "$archivo"
  else
    echo "$reemplazo" >> "$archivo"
  fi
}

# Cambios en sshd_config
reemplazar_o_agregar "$SSH_CONFIG" "prohibit-password" "yes"
reemplazar_o_agregar "$SSH_CONFIG" "without-password" "yes"
sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin yes/g" "$SSH_CONFIG"
sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g" "$SSH_CONFIG"

# Archivo cloudimg (solo si existe)
if [ -f "$SSH_CONFIG_CLOUDIMG" ]; then
  sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" "$SSH_CONFIG_CLOUDIMG"
fi

# 🔁 Reiniciar SSH para aplicar cambios
echo -e "${AZUL}🔁 Reiniciando el servicio SSH...${NEUTRO}"
systemctl restart ssh || service ssh restart

# 🔐 Solicitar nueva contraseña root
echo -ne "\n${VERDE}${NEGRITA}📝 Ingresa la nueva contraseña para el usuario ROOT:${NEUTRO} "
read -s nueva_pass
echo

if [[ -z "$nueva_pass" ]]; then
  echo -e "${ROJO}❌ No ingresaste ninguna contraseña. Cancelando...${NEUTRO}"
  exit 1
fi

echo "root:$nueva_pass" | chpasswd
echo -e "${VERDE}✅ Contraseña actualizada exitosamente.${NEUTRO}"

# ⚠️ Advertencia de seguridad
echo -e "\n${ROJO}${NEGRITA}⚠️ IMPORTANTE:${NEUTRO} Este script habilita el acceso SSH root con contraseña."
echo -e "${ROJO}Se recomienda usar medidas de seguridad como firewall, fail2ban o acceso por VPN.${NEUTRO}"

# ✅ Fin del script
echo -e "\n${VERDE}${NEGRITA}🎉 ¡Todo listo! Tu servidor ha sido configurado correctamente.${NEUTRO}\n"
