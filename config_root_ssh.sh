#!/bin/bash

# ╔═══════════════════════════════════════════════════════════╗
# ║       🔐 SCRIPT DE CONFIGURACIÓN DE ROOT Y SSH + FIREWALL           ║
# ║           Autor: ChristopherAGT - Guatemalteco 🇬🇹                   ║
# ╚═══════════════════════════════════════════════════════════╝

# 🎨 Colores y formato
VERDE="\033[1;32m"
ROJO="\033[1;31m"
AMARILLO="\033[1;33m"
AZUL="\033[1;34m"
NEGRITA="\033[1m"
NORMAL="\033[0m"
NEUTRO="\033[0m"

# ⏳ Spinner de carga
spinner() {
  local pid=$!
  local delay=0.1
  local spinstr='|/-\'
  echo -ne "${AMARILLO}"
  while kill -0 $pid 2>/dev/null; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  echo -ne "${NEUTRO}"
}

# 🛡️ Verificar si se ejecuta como root, y si no, relanzar con sudo
if [[ "$EUID" -ne 0 ]]; then
  echo -e "${ROJO}⚠️ Este script requiere permisos de administrador.${NEUTRO}"
  echo -e "${AMARILLO}🔁 Reintentando con sudo...${NEUTRO}\n"
  sudo bash "$0" "$@"
  exit
fi

clear
echo -e "${AZUL}${NEGRITA}╔════════════════════════════════════════════╗"
echo -e "║      🔐 CONFIGURACIÓN ROOT Y SSH           ║"
echo -e "╚════════════════════════════════════════════╝${NORMAL}\n"

# 🔥 Limpiar iptables
echo -e "${AMARILLO}🧹 Limpiando reglas de iptables...${NEUTRO}"
iptables -F > /dev/null 2>&1 & spinner
if [ $? -ne 0 ]; then
  echo -e "${ROJO}❌ Error al limpiar reglas de iptables.${NEUTRO}"
fi

# 🌐 Configurar DNS
echo -e "${AMARILLO}🌍 Estableciendo DNS de Cloudflare y Google...${NEUTRO}"
cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
if [ $? -ne 0 ]; then
  echo -e "${ROJO}❌ Error al configurar /etc/resolv.conf.${NEUTRO}"
fi

# 🔄 Actualizar paquetes
echo -e "${AZUL}📦 Actualizando el sistema...${NEUTRO}"
apt update -y > /dev/null 2>&1 & spinner
if [ $? -ne 0 ]; then
  echo -e "${ROJO}❌ Error al actualizar paquetes.${NEUTRO}"
fi

# 🛠️ Configuración de SSH
SSH_CONFIG="/etc/ssh/sshd_config"
SSH_CONFIG_CLOUDIMG="/etc/ssh/sshd_config.d/60-cloudimg-settings.conf"

echo -e "${AMARILLO}🔧 Configurando acceso root por SSH...${NEUTRO}"

# Función para reemplazar o agregar configuraciones
reemplazar_o_agregar() {
  local archivo="$1"
  local buscar="$2"
  local reemplazo="$3"
  if grep -q "$buscar" "$archivo"; then
    sed -i "s/$buscar/$reemplazo/g" "$archivo" > /dev/null 2>&1
  else
    echo "$reemplazo" >> "$archivo"
  fi
}

reemplazar_o_agregar "$SSH_CONFIG" "prohibit-password" "yes"
reemplazar_o_agregar "$SSH_CONFIG" "without-password" "yes"
sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin yes/g" "$SSH_CONFIG" > /dev/null 2>&1
sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g" "$SSH_CONFIG" > /dev/null 2>&1

if [ -f "$SSH_CONFIG_CLOUDIMG" ]; then
  sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" "$SSH_CONFIG_CLOUDIMG" > /dev/null 2>&1
fi

# 🔄 Reiniciar servicio SSH
echo -e "${AZUL}🔁 Reiniciando SSH para aplicar cambios...${NEUTRO}"
(systemctl restart ssh > /dev/null 2>&1 || service ssh restart > /dev/null 2>&1) & spinner
if [ $? -ne 0 ]; then
  echo -e "${ROJO}❌ Error al reiniciar el servicio SSH.${NEUTRO}"
fi

# 🔓 Abrir puertos importantes
echo -e "${AMARILLO}🌐 Configurando iptables: abriendo puertos TCP comunes...${NEUTRO}"
iptables -F > /dev/null 2>&1
PUERTOS=(81 80 443 8799 8080 1194)
for puerto in "${PUERTOS[@]}"; do
  iptables -A INPUT -p tcp --dport "$puerto" -j ACCEPT > /dev/null 2>&1
done

# 🔐 Solicitar nueva contraseña root
echo -ne "\n${VERDE}${NEGRITA}📝 Ingresa la nueva contraseña para el usuario ROOT:${NEUTRO} "
read -s nueva_pass
echo

if [[ -z "$nueva_pass" ]]; then
  echo -e "${ROJO}❌ No ingresaste ninguna contraseña. Cancelando...${NEUTRO}"
  exit 1
fi

echo "root:$nueva_pass" | chpasswd > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo -e "${ROJO}❌ Error al actualizar la contraseña.${NEUTRO}"
  exit 1
fi
echo -e "${VERDE}✅ Contraseña actualizada correctamente.${NEUTRO}"

# ⚠️ Advertencia
echo -e "\n${ROJO}${NEGRITA}⚠️ IMPORTANTE:${NEUTRO} Este script habilita el acceso SSH root con contraseña."
echo -e "${ROJO}Se recomienda combinarlo con otras medidas de seguridad como fail2ban, firewall o acceso por VPN.${NEUTRO}"

# 🎉 Fin
echo -e "\n${VERDE}${NEGRITA}🎉 Script ejecutado exitosamente. Tu servidor está listo.${NEUTRO}\n"
