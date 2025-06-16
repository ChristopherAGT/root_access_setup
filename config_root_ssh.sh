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
MAGENTA="\033[1;35m"
NEGRITA="\033[1m"
NEUTRO="\033[0m"

# Función para mostrar sección
print_section() {
  local title="$1"
  echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NEUTRO}"
  printf "${MAGENTA}║  ${NEUTRO}%-60s${MAGENTA}║\n" "$title"
  echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NEUTRO}"
}

# Spinner solo para procesos largos
spinner() {
  local msg="$1"
  shift
  local cmd=("$@")
  echo -ne "${AMARILLO}🔄 $msg... ${NEUTRO}"
  "${cmd[@]}" &> /tmp/spinner.log &
  local pid=$!
  local spin='|/-\\'
  local i=0

  while kill -0 $pid 2>/dev/null; do
    i=$(( (i+1) %4 ))
    printf "\b${spin:$i:1}"
    sleep 0.1
  done

  wait $pid
  local status=$?
  if [[ $status -eq 0 ]]; then
    echo -e "\b${VERDE}✔️${NEUTRO}"
  else
    echo -e "\b${ROJO}❌ Error${NEUTRO}"
    echo -e "${ROJO}🛑 Detalles del error:${NEUTRO}"
    cat /tmp/spinner.log
    exit 1
  fi
}

# ⚠️ Verificar permisos
if [[ "$EUID" -ne 0 ]]; then
  echo -e "${ROJO}⚠️ Este script requiere permisos de administrador.${NEUTRO}"
  echo -e "${AMARILLO}🔁 Reintentando con sudo...${NEUTRO}\n"
  exec sudo bash "$0" "$@"
fi

clear
print_section "🔐 INICIANDO CONFIGURACIÓN DE ROOT Y SSH"

# 🔥 Limpiar iptables
print_section "🧹 LIMPIANDO REGLAS DE IPTABLES"
echo -e "${AMARILLO}🔄 Limpiando reglas de iptables...${NEUTRO}"
iptables -F

# ➕ Permitir tráfico esencial
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT  # SSH

# 🌐 Configurar DNS
print_section "🌍 CONFIGURANDO DNS DE CLOUDFLARE Y GOOGLE"
echo -e "${AMARILLO}🔄 Estableciendo DNS de Cloudflare y Google...${NEUTRO}"
chattr -i /etc/resolv.conf 2>/dev/null
cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# 📦 Actualizar sistema
print_section "📦 ACTUALIZANDO EL SISTEMA"
spinner "Ejecutando apt update" apt update -y
spinner "Ejecutando apt upgrade" apt upgrade -y

# 🔧 Configuración SSH
print_section "🔧 CONFIGURANDO ACCESO ROOT POR SSH"

SSH_CONFIG="/etc/ssh/sshd_config"
SSH_CONFIG_CLOUDIMG="/etc/ssh/sshd_config.d/60-cloudimg-settings.conf"

# Backup antes de modificar
cp "$SSH_CONFIG" "${SSH_CONFIG}.bak"

# Reemplazar o añadir configuraciones
reemplazar_o_agregar() {
  local archivo="$1"
  local buscar="$2"
  local reemplazo="$3"
  if grep -q "$buscar" "$archivo"; then
    sed -i "s|$buscar|$reemplazo|g" "$archivo"
  else
    echo "$reemplazo" >> "$archivo"
  fi
}

reemplazar_o_agregar "$SSH_CONFIG" "prohibit-password" "yes"
reemplazar_o_agregar "$SSH_CONFIG" "without-password" "yes"
sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin yes/" "$SSH_CONFIG"
sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/" "$SSH_CONFIG"

if [[ -f "$SSH_CONFIG_CLOUDIMG" ]]; then
  sed -i "s/^PasswordAuthentication no/PasswordAuthentication yes/" "$SSH_CONFIG_CLOUDIMG"
fi

# Verificar configuración antes de reiniciar
if ! sshd -t 2>/tmp/sshd_error.log; then
  echo -e "${ROJO}❌ Error en configuración SSHD.${NEUTRO}"
  cat /tmp/sshd_error.log
  exit 1
fi

# Reiniciar servicio SSH
echo -e "${AMARILLO}🔄 Reiniciando SSH para aplicar cambios...${NEUTRO}"
systemctl restart ssh 2>/dev/null || service ssh restart

# 🔐 Contraseña root
print_section "🔐 CONFIGURANDO CONTRASEÑA DE ROOT"
echo -ne "${VERDE}📝 Ingresa la nueva contraseña para el usuario ROOT:${NEUTRO} "
read -s nueva_pass
echo

if [[ -z "$nueva_pass" ]]; then
  echo -e "${ROJO}❌ No ingresaste ninguna contraseña. Cancelando...${NEUTRO}"
  exit 1
fi

echo "root:$nueva_pass" | chpasswd
echo -e "${VERDE}✅  Contraseña actualizada correctamente.${NEUTRO}"

# ⚠️ Advertencia
echo -e "\n${ROJO}⚠️ IMPORTANTE:${NEUTRO} Este script habilita el acceso SSH root con contraseña."
echo -e "${ROJO}Se recomienda combinarlo con medidas de seguridad como fail2ban, firewall o VPN.${NEUTRO}"

# 🎉 Fin
print_section "🎉 SCRIPT FINALIZADO CON ÉXITO"
