#!/bin/bash
# ╔════════════════════════════════════════════════════════════════╗
# ║            SCRIPT DE CONFIGURACIÓN DE ROOT Y SSH               ║
# ║           Autor: ChristopherAGT - Guatemalteco 🇬🇹              ║
# ╚════════════════════════════════════════════════════════════════╝

# 🛑 Verificar si se ejecuta como root
if [[ "$EUID" -ne 0 ]]; then
  echo -e "\n\033[1;31m🚫 ERROR: Debes ejecutar este script como usuario ROOT o con sudo.\033[0m"
  echo -e "\033[1;33mEjemplo:\033[0m sudo bash $0\n"
  exit 1
fi

# 🎨 Colores para el script
VERDE="\033[1;32m"
ROJO="\033[1;31m"
AMARILLO="\033[1;33m"
AZUL="\033[1;34m"
NEGRITA="\033[1m"
NORMAL="\033[0m"

clear
echo -e "${AZUL}${NEGRITA}╔════════════════════════════════════════════╗"
echo -e "║      🔐 CONFIGURACIÓN ROOT Y SSH           ║"
echo -e "╚════════════════════════════════════════════╝${NORMAL}\n"

# 🔥 Limpieza reglas firewall iptables
echo -e "${AMARILLO}→ Limpiando reglas iptables existentes...${NORMAL}"
iptables -F

# 🌐 Configuración DNS pública (Cloudflare y Google)
echo -e "${AMARILLO}→ Configurando DNS públicos...${NORMAL}"
cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# 📦 Actualizar lista de paquetes
echo -e "${AMARILLO}→ Actualizando lista de paquetes (apt)...${NORMAL}"
apt update -y

# 🛠️ Configuración SSH para permitir root y autenticación por contraseña

SSH_CONFIG="/etc/ssh/sshd_config"
SSH_CONFIG_CLOUDIMG="/etc/ssh/sshd_config.d/60-cloudimg-settings.conf"

echo -e "${AMARILLO}→ Configurando SSH para permitir acceso root y autenticación por contraseña...${NORMAL}"

# Función para reemplazar texto en archivos si existe
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

# Modificaciones importantes
reemplazar_o_agregar "$SSH_CONFIG" "prohibit-password" "yes"
reemplazar_o_agregar "$SSH_CONFIG" "without-password" "yes"

# Descomentar y habilitar PermitRootLogin
sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin yes/g" "$SSH_CONFIG"

# Activar PasswordAuthentication
sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g" "$SSH_CONFIG"

# Configurar también el archivo cloudimg si existe
if [ -f "$SSH_CONFIG_CLOUDIMG" ]; then
  sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" "$SSH_CONFIG_CLOUDIMG"
fi

# Reiniciar SSH para aplicar cambios
echo -e "${AMARILLO}→ Reiniciando servicio SSH...${NORMAL}"
systemctl restart ssh || service ssh restart

# 🔥 Configuración de iptables: limpiar y abrir puertos importantes
echo -e "${AMARILLO}→ Configurando reglas iptables: abriendo puertos TCP comunes...${NORMAL}"
iptables -F

PUERTOS=(81 80 443 8799 8080 1194)
for puerto in "${PUERTOS[@]}"; do
  iptables -A INPUT -p tcp --dport "$puerto" -j ACCEPT
done

# 🚨 Solicitar nueva contraseña root
echo -ne "\n${VERDE}${NEGRITA}→ ESCRIBE LA NUEVA CONTRASEÑA ROOT:${NORMAL} "
read -s nueva_pass
echo

if [[ -z "$nueva_pass" ]]; then
  echo -e "${ROJO}⚠️ Contraseña vacía. No se realizó ningún cambio.${NORMAL}"
  exit 1
fi

echo "root:$nueva_pass" | chpasswd

echo -e "\n${VERDE}${NEGRITA}✅ CONTRASEÑA ROOT ACTUALIZADA CON ÉXITO${NORMAL}"

# ⚠️ Advertencia final
echo -e "\n${ROJO}${NEGRITA}IMPORTANTE:${NORMAL} Este script habilita el acceso root vía SSH y autenticación por contraseña,"
echo -e "${ROJO}${NEGRITA}lo que puede ser un riesgo de seguridad si no se usan medidas adicionales como firewall, fail2ban o VPN.\n${NORMAL}"

echo -e "${AZUL}Script finalizado.${NORMAL}\n"
