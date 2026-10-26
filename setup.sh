#!/usr/bin/env bash

# ============================================================
# GESTOR DE HOSTNAME VPS
# Compatible con Ubuntu y Debian
# Conserva mayúsculas y minúsculas
# Respaldo, validación y verificación de cambios
# ============================================================

set -Eeuo pipefail
umask 077

# Colores de la interfaz
if [[ -t 1 ]]; then
    RESET='\033[0m'
    BOLD='\033[1m'
    CYAN='\033[1;36m'
    BLUE='\033[1;34m'
    GREEN='\033[1;32m'
    YELLOW='\033[1;33m'
    RED='\033[1;31m'
    WHITE='\033[1;37m'
else
    RESET='' BOLD='' CYAN='' BLUE=''
    GREEN='' YELLOW='' RED='' WHITE=''
fi

HOSTS_FILE="/etc/hosts"
BACKUP_DIR="/var/backups/hostname-manager"
TMP_FILE=""
BACKUP_FILE=""
OLD_HOST=""
CHANGE_STARTED=0

# ============================================================
# INTERFAZ
# ============================================================

title() {
    printf '\n'
    printf '  %b%s%b\n' "$CYAN$BOLD" "$1" "$RESET"
    printf '  %b%s%b\n' "$BLUE" \
        '────────────────────────────────────────────────────' "$RESET"
}

info() {
    printf '  %b%-9s%b %s\n' "$CYAN" "[INFO]" "$RESET" "$1"
}

success() {
    printf '  %b%-9s%b %s\n' "$GREEN" "[OK]" "$RESET" "$1"
}

warning() {
    printf '  %b%-9s%b %s\n' "$YELLOW" "[AVISO]" "$RESET" "$1"
}

error() {
    printf '  %b%-9s%b %s\n' "$RED" "[ERROR]" "$RESET" "$1" >&2
}

cleanup() {
    if [[ -n "$TMP_FILE" && -f "$TMP_FILE" ]]; then
        rm -f -- "$TMP_FILE"
    fi
}

trap cleanup EXIT

# ============================================================
# CONTROL DE ERRORES
# ============================================================

on_error() {
    local code=$?
    trap - ERR

    error "La operación falló (código $code)."

    if (( CHANGE_STARTED == 1 )); then
        warning "Comprueba el hostname y /etc/hosts."
        if [[ -n "$BACKUP_FILE" && -f "$BACKUP_FILE" ]]; then
            info "Respaldo disponible: $BACKUP_FILE"
        fi
    fi

    exit "$code"
}

trap on_error ERR

# ============================================================
# COMPROBACIONES INICIALES
# ============================================================

if (( EUID != 0 )); then
    error "Debes ejecutar este script como root."
    printf '  %s\n' 'Ejemplo: sudo bash hostname-manager.sh'
    exit 1
fi

for cmd in hostnamectl python3 mktemp cp mv date uname; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "No se encontró el comando requerido: $cmd"
        exit 1
    fi
done

if [[ ! -f "$HOSTS_FILE" || ! -r "$HOSTS_FILE" ||
      ! -w "$HOSTS_FILE" ]]; then
    error "No se puede leer o modificar $HOSTS_FILE."
    exit 1
fi

if ! hostnamectl --static >/dev/null 2>&1; then
    error "No se pudo consultar el hostname actual."
    exit 1
fi

CURRENT_HOST="$(hostnamectl --static)"
OLD_HOST="$CURRENT_HOST"

# ============================================================
# PANTALLA PRINCIPAL
# ============================================================

clear 2>/dev/null || true

title "GESTOR DE HOSTNAME VPS"

printf '\n'
printf '  %-20s %b%s%b\n' \
    "Hostname actual:" "$YELLOW" "$CURRENT_HOST" "$RESET"

printf '  %-20s %s\n' "Sistema:" \
    "$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-Linux}")"

printf '  %-20s %s\n' "Arquitectura:" "$(uname -m)"
printf '  %-20s %s\n' "Archivo de hosts:" "$HOSTS_FILE"

printf '\n'
info "Configura el nombre del servidor de forma segura."
info "Se conservarán las entradas IPv6 y localhost."
info "No se requiere reiniciar el VPS."

# ============================================================
# SOLICITUD Y VALIDACIÓN DEL HOSTNAME
# ============================================================

while true; do
    printf '\n'
    printf '  %bNuevo hostname:%b ' "$CYAN$BOLD" "$RESET"

    if ! IFS= read -r NEW_HOST; then
        error "No se recibió ningún nombre."
        exit 1
    fi

    # Quitar espacios externos sin modificar las mayúsculas.
    NEW_HOST="${NEW_HOST#"${NEW_HOST%%[![:space:]]*}"}"
    NEW_HOST="${NEW_HOST%"${NEW_HOST##*[![:space:]]}"}"

    if [[ -z "$NEW_HOST" ]]; then
        error "El hostname no puede estar vacío."
        continue
    fi

    # No convertir a minúsculas: conservar la entrada original.
    if (( ${#NEW_HOST} > 64 )); then
        error "El hostname no puede superar 64 caracteres."
        continue
    fi

    # Validar caracteres y estructura.
    if [[ ! "$NEW_HOST" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        error "Formato inválido. Usa letras, números, puntos o guiones."
        error "No uses espacios ni guiones al inicio o al final."
        continue
    fi

    VALID_HOST=1
    IFS='.' read -r -a LABELS <<< "$NEW_HOST"

    for LABEL in "${LABELS[@]}"; do
        if (( ${#LABEL} > 63 )) ||
           [[ ! "$LABEL" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
            VALID_HOST=0
            break
        fi
    done

    if (( VALID_HOST == 0 )); then
        error "Una sección del hostname tiene un formato inválido."
        continue
    fi

    break
done

# ============================================================
# CONFIRMACIÓN
# ============================================================

title "RESUMEN DEL CAMBIO"

printf '\n'
printf '  %-20s %s\n' "Hostname anterior:" "$CURRENT_HOST"
printf '  %-20s %b%s%b\n' \
    "Hostname nuevo:" "$GREEN$BOLD" "$NEW_HOST" "$RESET"

printf '\n'
printf '  %b¿Deseas aplicar el cambio? [s/N]:%b ' "$CYAN" "$RESET"

IFS= read -r CONFIRM || CONFIRM=""
CONFIRM="${CONFIRM,,}"

if [[ "$CONFIRM" != "s" && "$CONFIRM" != "si" && "$CONFIRM" != "sí" ]]; then
    warning "Operación cancelada. No se realizaron cambios."
    exit 0
fi

if [[ "$CURRENT_HOST" == "$NEW_HOST" ]]; then
    success "El hostname ya coincide con el nombre solicitado."
fi

# ============================================================
# RESPALDO
# ============================================================

title "APLICANDO CONFIGURACIÓN"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

BACKUP_FILE="$BACKUP_DIR/hosts-$(date +%Y%m%d-%H%M%S)-$$.bak"

cp -a -- "$HOSTS_FILE" "$BACKUP_FILE"

success "Respaldo creado correctamente."

# Preparar archivo temporal en el mismo sistema de archivos.
TMP_FILE="$(mktemp /etc/.hosts.hostname.XXXXXX)"

chmod --reference="$HOSTS_FILE" "$TMP_FILE"
chown --reference="$HOSTS_FILE" "$TMP_FILE"

# ============================================================
# ACTUALIZACIÓN SEGURA DE /etc/hosts
# ============================================================

if ! python3 - "$HOSTS_FILE" "$TMP_FILE" "$NEW_HOST" <<'PY'
import ipaddress
import sys

source, destination, hostname = sys.argv[1:4]

with open(source, "r", encoding="utf-8") as f:
    lines = f.readlines()

result = []
found = False

for line in lines:
    stripped = line.strip()

    if not stripped or stripped.startswith("#"):
        result.append(line)
        continue

    content, separator, comment = line.partition("#")
    fields = content.split()

    if not fields:
        result.append(line)
        continue

    try:
        address = ipaddress.ip_address(fields[0])
    except ValueError:
        result.append(line)
        continue

    if address == ipaddress.ip_address("127.0.1.1"):
        if not found:
            replacement = f"127.0.1.1\t{hostname}"
            if separator:
                replacement += f"  #{comment.rstrip()}"
            result.append(replacement + "\n")
            found = True
        # Evitar duplicados de 127.0.1.1.
        continue

    result.append(line)

if not found:
    # Insertar después de localhost IPv4 si existe.
    insert_at = 0

    for i, line in enumerate(result):
        content = line.split("#", 1)[0].split()
        if content and content[0] == "127.0.0.1":
            insert_at = i + 1
            break

    result.insert(insert_at, f"127.0.1.1\t{hostname}\n")

with open(destination, "w", encoding="utf-8") as f:
    f.writelines(result)
PY
then
    error "No se pudo preparar /etc/hosts."
    exit 1
fi

# ============================================================
# APLICAR CAMBIOS
# ============================================================

CHANGE_STARTED=1

if ! hostnamectl set-hostname "$NEW_HOST"; then
    error "No se pudo cambiar el hostname."
    exit 1
fi

# Reemplazo atómico del archivo.
if ! mv -f -- "$TMP_FILE" "$HOSTS_FILE"; then
    warning "No se pudo instalar el nuevo archivo /etc/hosts."
    warning "Intentando restaurar el hostname anterior."

    hostnamectl set-hostname "$OLD_HOST" || true

    error "El respaldo permanece disponible: $BACKUP_FILE"
    exit 1
fi

TMP_FILE=""

# ============================================================
# VERIFICACIÓN FINAL
# ============================================================

FINAL_HOST="$(hostnamectl --static)"

if [[ "$FINAL_HOST" != "$NEW_HOST" ]]; then
    error "El hostname resultante no coincide con el solicitado."
    warning "Respaldo disponible: $BACKUP_FILE"
    exit 1
fi

if ! python3 - "$HOSTS_FILE" "$NEW_HOST" <<'PY'
import sys

path, hostname = sys.argv[1:3]

with open(path, encoding="utf-8") as f:
    for line in f:
        content = line.split("#", 1)[0].split()
        if len(content) >= 2 and content[0] == "127.0.1.1":
            if content[1] == hostname:
                sys.exit(0)

sys.exit(1)
PY
then
    error "No se verificó la entrada de /etc/hosts."
    warning "Respaldo disponible: $BACKUP_FILE"
    exit 1
fi

# ============================================================
# RESULTADO
# ============================================================

title "CAMBIO COMPLETADO"

printf '\n'
printf '  %-20s %b%s%b\n' \
    "Hostname:" "$GREEN$BOLD" "$FINAL_HOST" "$RESET"

printf '  %-20s %b%s%b\n' \
    "hostnamectl:" "$GREEN" "Correcto" "$RESET"

printf '  %-20s %b%s%b\n' \
    "/etc/hosts:" "$GREEN" "Actualizado" "$RESET"

printf '  %-20s %s\n' "Respaldo:" "$BACKUP_FILE"

printf '\n'
info "Entradas locales verificadas:"

while IFS= read -r HOST_LINE; do
    printf '    %s\n' "$HOST_LINE"
done < <(grep -E '^(127\.0\.0\.1|127\.0\.1\.1|::1)[[:space:]]' "$HOSTS_FILE" || true)

printf '\n'
success "El hostname conserva las mayúsculas introducidas."
info "No es necesario reiniciar el VPS."
printf '\n'
