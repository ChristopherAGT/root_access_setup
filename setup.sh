#!/usr/bin/env bash

# ============================================================
# GESTOR DE HOSTNAME VPS
# Compatible con Ubuntu y Debian
# Conserva mayúsculas y minúsculas
# Respaldo, validación y verificación de cambios
# ============================================================

set -Eeuo pipefail
umask 077

# ============================================================
# COLORES DE LA INTERFAZ
# ============================================================

if [[ -t 1 ]]; then
    RESET='\033[0m'
    BOLD='\033[1m'
    DIM='\033[2m'
    CYAN='\033[1;36m'
    BLUE='\033[1;34m'
    GREEN='\033[1;32m'
    YELLOW='\033[1;33m'
    RED='\033[1;31m'
    WHITE='\033[1;37m'
    MAGENTA='\033[1;35m'
    GRAY='\033[0;37m'
else
    RESET='' BOLD='' DIM='' CYAN='' BLUE=''
    GREEN='' YELLOW='' RED='' WHITE=''
    MAGENTA='' GRAY=''
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

line() {
    printf '  %b%s%b\n' "$BLUE" \
        '────────────────────────────────────────────────────' "$RESET"
}

title() {
    printf '\n'
    printf '  %b%s%b\n' "$CYAN$BOLD" "$1" "$RESET"
    line
}

ok() {
    printf '  %b✓%b  %b%s%b\n' "$GREEN$BOLD" "$RESET" "$WHITE" "$1" "$RESET"
}

fail() {
    printf '  %b✗%b  %b%s%b\n' "$RED$BOLD" "$RESET" "$WHITE" "$1" "$RESET" >&2
}

warn() {
    printf '  %b!%b  %b%s%b\n' "$YELLOW$BOLD" "$RESET" "$YELLOW" "$1" "$RESET"
}

detail() {
    printf '  %b›%b  %s\n' "$CYAN" "$RESET" "$1"
}

# Etiquetas y valores alineados
field() {
    printf '  %b%-21s%b %b%s%b\n' \
        "$GRAY" "$1" "$RESET" "$2" "$3" "$RESET"
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

    fail "La operación falló (código $code)."

    if (( CHANGE_STARTED == 1 )); then
        warn "Comprueba el hostname y el archivo /etc/hosts."

        if [[ -n "$BACKUP_FILE" && -f "$BACKUP_FILE" ]]; then
            detail "Respaldo disponible: $BACKUP_FILE"
        fi
    fi

    exit "$code"
}

trap on_error ERR

# ============================================================
# COMPROBACIONES INICIALES
# ============================================================

if (( EUID != 0 )); then
    fail "Debes ejecutar este script como root."
    detail "Ejemplo: sudo bash hostname-manager.sh"
    exit 1
fi

for cmd in hostnamectl python3 mktemp cp mv date uname grep; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        fail "No se encontró el comando requerido: $cmd"
        exit 1
    fi
done

if [[ ! -f "$HOSTS_FILE" || ! -r "$HOSTS_FILE" ||
      ! -w "$HOSTS_FILE" ]]; then
    fail "No se puede leer o modificar $HOSTS_FILE."
    exit 1
fi

if ! hostnamectl --static >/dev/null 2>&1; then
    fail "No se pudo consultar el hostname actual."
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

field "Hostname actual:" "$CURRENT_HOST" "$YELLOW$BOLD"

OS_NAME="$(
    . /etc/os-release
    printf '%s' "${PRETTY_NAME:-Linux}"
)"

field "Sistema operativo:" "$OS_NAME" "$WHITE"
field "Arquitectura:" "$(uname -m)" "$MAGENTA"
field "Archivo de hosts:" "$HOSTS_FILE" "$CYAN"

printf '\n'
line
printf '\n'

ok "Configuración lista para comenzar."
ok "Se conservarán las entradas IPv6 y localhost."
ok "El hostname podrá conservar las mayúsculas."

# ============================================================
# SOLICITUD Y VALIDACIÓN DEL HOSTNAME
# ============================================================

while true; do
    printf '\n'
    printf '  %bNuevo hostname%b: ' "$CYAN$BOLD" "$RESET"

    if ! IFS= read -r NEW_HOST; then
        printf '\n'
        fail "No se recibió ningún nombre."
        exit 1
    fi

    # Eliminar espacios externos sin cambiar mayúsculas.
    NEW_HOST="${NEW_HOST#"${NEW_HOST%%[![:space:]]*}"}"
    NEW_HOST="${NEW_HOST%"${NEW_HOST##*[![:space:]]}"}"

    if [[ -z "$NEW_HOST" ]]; then
        fail "El hostname no puede estar vacío."
        continue
    fi

    if (( ${#NEW_HOST} > 64 )); then
        fail "El hostname no puede superar 64 caracteres."
        continue
    fi

    # Admitir letras mayúsculas y minúsculas.
    if [[ ! "$NEW_HOST" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        fail "Usa letras, números, puntos o guiones."
        fail "No utilices espacios ni guiones en los extremos."
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
        fail "Una sección del hostname tiene un formato inválido."
        continue
    fi

    break
done

# ============================================================
# RESUMEN Y CONFIRMACIÓN
# ============================================================

title "RESUMEN DEL CAMBIO"

printf '\n'

field "Hostname anterior:" "$CURRENT_HOST" "$YELLOW"
field "Hostname nuevo:" "$NEW_HOST" "$GREEN$BOLD"

printf '\n'
line
printf '\n'

printf '  %b¿Aplicar el cambio?%b [%bS%b/n]: ' \
    "$WHITE$BOLD" "$RESET" "$GREEN$BOLD" "$RESET"

IFS= read -r CONFIRM || CONFIRM=""

# S/n: Enter acepta; n cancela.
if [[ -n "$CONFIRM" ]]; then
    CONFIRM="${CONFIRM,,}"

    if [[ "$CONFIRM" != "s" &&
          "$CONFIRM" != "si" &&
          "$CONFIRM" != "sí" ]]; then
        warn "Operación cancelada. No se realizaron cambios."
        exit 0
    fi
fi

if [[ "$CURRENT_HOST" == "$NEW_HOST" ]]; then
    ok "El hostname ya coincide con el nombre solicitado."
fi

# ============================================================
# RESPALDO
# ============================================================

title "APLICANDO CONFIGURACIÓN"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

BACKUP_FILE="$BACKUP_DIR/hosts-$(date +%Y%m%d-%H%M%S)-$$.bak"

cp -a -- "$HOSTS_FILE" "$BACKUP_FILE"

ok "Respaldo creado correctamente."
detail "$BACKUP_FILE"

# Crear temporal en el mismo sistema de archivos.
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
    fail "No se pudo preparar /etc/hosts."
    exit 1
fi

# ============================================================
# APLICAR CAMBIOS
# ============================================================

CHANGE_STARTED=1

if ! hostnamectl set-hostname "$NEW_HOST"; then
    fail "No se pudo cambiar el hostname."
    exit 1
fi

# Reemplazo atómico del archivo.
if ! mv -f -- "$TMP_FILE" "$HOSTS_FILE"; then
    warn "No se pudo instalar el nuevo archivo /etc/hosts."
    warn "Intentando restaurar el hostname anterior."

    hostnamectl set-hostname "$OLD_HOST" || true

    fail "El respaldo permanece disponible: $BACKUP_FILE"
    exit 1
fi

TMP_FILE=""

# ============================================================
# VERIFICACIÓN FINAL
# ============================================================

FINAL_HOST="$(hostnamectl --static)"

if [[ "$FINAL_HOST" != "$NEW_HOST" ]]; then
    fail "El hostname resultante no coincide con el solicitado."
    detail "Respaldo disponible: $BACKUP_FILE"
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
    fail "No se verificó la entrada de /etc/hosts."
    detail "Respaldo disponible: $BACKUP_FILE"
    exit 1
fi

# ============================================================
# RESULTADO FINAL
# ============================================================

title "CAMBIO COMPLETADO"

printf '\n'

field "Hostname:" "$FINAL_HOST" "$GREEN$BOLD"
field "hostnamectl:" "Verificado" "$GREEN"
field "/etc/hosts:" "Verificado" "$GREEN"
field "Respaldo:" "Guardado" "$CYAN"

printf '\n'
line
printf '\n'

printf '  %b✓%b  %bHostname actualizado correctamente.%b\n' \
    "$GREEN$BOLD" "$RESET" "$WHITE" "$RESET"

printf '  %b✓%b  %bMayúsculas y minúsculas conservadas.%b\n' \
    "$GREEN$BOLD" "$RESET" "$WHITE" "$RESET"

printf '  %b✓%b  %bEntradas IPv6 y localhost preservadas.%b\n' \
    "$GREEN$BOLD" "$RESET" "$WHITE" "$RESET"

printf '  %b✓%b  %bNo se requiere reiniciar el VPS.%b\n' \
    "$GREEN$BOLD" "$RESET" "$WHITE" "$RESET"

printf '\n'
title "ENTRADAS LOCALES"

while IFS= read -r HOST_LINE; do
    printf '  %b›%b  %s\n' "$CYAN" "$RESET" "$HOST_LINE"
done < <(
    grep -E '^(127\.0\.0\.1|127\.0\.1\.1|::1)[[:space:]]' \
        "$HOSTS_FILE" || true
)

printf '\n'
line
printf '  %b✓  PROCESO FINALIZADO%b\n' "$GREEN$BOLD" "$RESET"
printf '\n'
