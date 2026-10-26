
#!/usr/bin/env bash

# ============================================================
# GESTOR DE HOSTNAME VPS
# Compatible con Ubuntu / Debian
# Actualiza hostnamectl y /etc/hosts de forma segura
# Incluye validaciones, respaldo y verificación final
# ============================================================

set -Eeuo pipefail
umask 077

# Colores
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
    RESET='' BOLD='' CYAN='' BLUE='' GREEN=''
    YELLOW='' RED='' WHITE=''
fi

HOSTS_FILE="/etc/hosts"
BACKUP_DIR="/var/backups/hostname-manager"
TMP_FILE=""

# Funciones de interfaz
line() {
    printf '%b\n' "${BLUE}────────────────────────────────────────────────────${RESET}"
}

info() {
    printf '  %bℹ%b  %s\n' "$CYAN" "$RESET" "$1"
}

success() {
    printf '  %b✓%b  %s\n' "$GREEN" "$RESET" "$1"
}

warning() {
    printf '  %b!%b  %s\n' "$YELLOW" "$RESET" "$1"
}

error() {
    printf '  %b✗%b  %s\n' "$RED" "$RESET" "$1" >&2
}

cleanup() {
    if [[ -n "${TMP_FILE:-}" && -f "$TMP_FILE" ]]; then
        rm -f -- "$TMP_FILE"
    fi
}

trap cleanup EXIT

# Errores inesperados
on_error() {
    local code=$?
    error "Ocurrió un error inesperado (código $code)."
    error "Comprueba el hostname y /etc/hosts antes de volver a ejecutar."
    exit "$code"
}

trap on_error ERR

# Requiere root
if [[ "$EUID" -ne 0 ]]; then
    error "Ejecuta este script como root."
    printf '  Ejemplo: %bsudo bash %s%b\n' "$CYAN" "$0" "$RESET"
    exit 1
fi

# Dependencias
for cmd in hostnamectl python3 cp mktemp date; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "Falta el comando requerido: $cmd"
        exit 1
    fi
done

if [[ ! -f "$HOSTS_FILE" || ! -r "$HOSTS_FILE" || ! -w "$HOSTS_FILE" ]]; then
    error "No se puede leer o modificar $HOSTS_FILE."
    exit 1
fi

# Información inicial
clear 2>/dev/null || true
printf '\n'
printf '  %bGESTOR DE HOSTNAME VPS%b\n' "$CYAN$BOLD" "$RESET"
printf '  %bConfiguración segura del nombre del servidor%b\n' "$WHITE" "$RESET"
line
printf '\n'

CURRENT_HOST="$(hostnamectl --static 2>/dev/null || hostname)"
printf '  Hostname actual : %b%s%b\n' "$YELLOW" "$CURRENT_HOST" "$RESET"
printf '  Sistema         : %s\n' "$(
    . /etc/os-release 2>/dev/null
    printf '%s' "${PRETTY_NAME:-Linux}"
)"
printf '  Arquitectura    : %s\n' "$(uname -m)"
printf '\n'
line
printf '\n'

# Solicitar nuevo hostname
while true; do
    printf '  %bIntroduce el nuevo hostname:%b ' "$CYAN$BOLD" "$RESET"

    if ! IFS= read -r NEW_HOST; then
        error "No se recibió ningún nombre."
        exit 1
    fi

    # Quitar espacios al inicio y al final
    NEW_HOST="${NEW_HOST#"${NEW_HOST%%[![:space:]]*}"}"
    NEW_HOST="${NEW_HOST%"${NEW_HOST##*[![:space:]]}"}"

    if [[ -z "$NEW_HOST" ]]; then
        error "El hostname no puede estar vacío."
        continue
    fi

    # Normalizar a minúsculas
    NEW_HOST="${NEW_HOST,,}"

    # Validar longitud máxima del hostname estático de Linux
    if (( ${#NEW_HOST} > 64 )); then
        error "El nombre supera los 64 caracteres."
        continue
    fi

    # Validar caracteres y estructura DNS
    if [[ ! "$NEW_HOST" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]]; then
        error "Usa solamente letras, números, puntos y guiones."
        error "No uses espacios ni guiones al inicio o al final."
        continue
    fi

    # Validar cada etiqueta separada por puntos
    VALID_HOST=1
    IFS='.' read -r -a LABELS <<< "$NEW_HOST"

    for LABEL in "${LABELS[@]}"; do
        if (( ${#LABEL} < 1 || ${#LABEL} > 63 )) ||
           [[ ! "$LABEL" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
            VALID_HOST=0
            break
        fi
    done

    if (( VALID_HOST == 0 )); then
        error "Formato de hostname inválido."
        error "Cada etiqueta debe tener 1-63 caracteres y no iniciar ni terminar con guion."
        continue
    fi

    break
done

printf '\n'
line
printf '  %bRESUMEN DEL CAMBIO%b\n' "$CYAN$BOLD" "$RESET"
printf '\n'
printf '  Anterior : %s\n' "$CURRENT_HOST"
printf '  Nuevo    : %b%s%b\n' "$GREEN" "$NEW_HOST" "$RESET"
printf '  Archivo  : %s\n' "$HOSTS_FILE"
printf '\n'

if [[ "$CURRENT_HOST" == "$NEW_HOST" ]]; then
    success "El hostname ya tiene ese nombre."
    info "Se comprobará también la entrada de /etc/hosts."
fi

printf '  ¿Deseas aplicar el cambio? [s/N]: '
IFS= read -r CONFIRM || true
CONFIRM="${CONFIRM,,}"

if [[ "$CONFIRM" != "s" && "$CONFIRM" != "si" && "$CONFIRM" != "sí" ]]; then
    warning "Operación cancelada. No se realizaron cambios."
    exit 0
fi

printf '\n'
line

# Crear respaldo antes de modificar
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

BACKUP_FILE="$BACKUP_DIR/hosts-$(date +%Y%m%d-%H%M%S)-$$.bak"
cp -a -- "$HOSTS_FILE" "$BACKUP_FILE"
success "Respaldo creado: $BACKUP_FILE"

# Guardar hostname anterior para recuperación
OLD_HOST="$CURRENT_HOST"

# Preparar un archivo temporal en el mismo sistema de archivos
TMP_FILE="$(mktemp /etc/.hosts.hostname.XXXXXX)"
chmod --reference="$HOSTS_FILE" "$TMP_FILE"
chown --reference="$HOSTS_FILE" "$TMP_FILE"

# Actualizar /etc/hosts mediante Python.
# - Conserva las entradas IPv6 y localhost.
# - Actualiza la dirección local 127.0.1.1.
# - Elimina entradas duplicadas de 127.0.1.1.
# - Si esa dirección no existe, la añade sin borrar otras líneas.
if ! python3 - "$HOSTS_FILE" "$TMP_FILE" "$NEW_HOST" <<'PY'
import sys
import ipaddress

source, destination, new_host = sys.argv[1:4]

with open(source, "r", encoding="utf-8") as f:
    lines = f.readlines()

result = []
found = False

for line in lines:
    stripped = line.strip()

    if not stripped or stripped.startswith("#"):
        result.append(line)
        continue

    content, sep, comment = line.partition("#")
    fields = content.split()

    if fields:
        try:
            address = ipaddress.ip_address(fields[0])
        except ValueError:
            result.append(line)
            continue

        if address == ipaddress.ip_address("127.0.1.1"):
            if not found:
                replacement = f"127.0.1.1\t{new_host}"
                if sep:
                    replacement += f"  #{comment.rstrip()}"
                result.append(replacement + "\n")
                found = True
            # Descarta entradas duplicadas de 127.0.1.1.
            continue

    result.append(line)

if not found:
    insert_at = 0
    for i, line in enumerate(result):
        if line.strip().split("#", 1)[0].split()[:1] == ["127.0.0.1"]:
            insert_at = i + 1
            break
    result.insert(insert_at, f"127.0.1.1\t{new_host}\n")

with open(destination, "w", encoding="utf-8") as f:
    f.writelines(result)
PY
then
    error "No se pudo preparar la actualización de /etc/hosts."
    exit 1
fi

# Aplicar el hostname estático
if ! hostnamectl set-hostname "$NEW_HOST"; then
    error "hostnamectl no pudo aplicar el nuevo hostname."
    exit 1
fi

# Reemplazar /etc/hosts de forma atómica
if ! mv -f -- "$TMP_FILE" "$HOSTS_FILE"; then
    warning "No se pudo actualizar /etc/hosts."
    warning "Intentando restaurar el hostname anterior."
    hostnamectl set-hostname "$OLD_HOST" || true
    error "Se conserva el respaldo: $BACKUP_FILE"
    exit 1
fi
TMP_FILE=""

# Verificación final
FINAL_HOST="$(hostnamectl --static 2>/dev/null || true)"

if [[ "$FINAL_HOST" != "$NEW_HOST" ]] ||
   ! grep -Eq "^127\.0\.1\.1[[:space:]]+${NEW_HOST//./\\.}([[:space:]]|$)" "$HOSTS_FILE"; then
    warning "La verificación final no coincide con lo esperado."
    warning "El respaldo está disponible en: $BACKUP_FILE"
    warning "No se restaurará automáticamente para evitar sobrescribir otros cambios."
    exit 1
fi

printf '\n'
line
printf '  %bCAMBIO COMPLETADO%b\n' "$GREEN$BOLD" "$RESET"
printf '\n'
success "Hostname estático: $FINAL_HOST"
success "Entrada de /etc/hosts actualizada."
success "Configuración IPv6 conservada."
info "Respaldo: $BACKUP_FILE"
printf '\n'
printf '  %bVerificación actual:%b\n' "$CYAN" "$RESET"
hostnamectl --static
printf '\n'
grep -E '^(127\.0\.0\.1|127\.0\.1\.1|::1)[[:space:]]' "$HOSTS_FILE" || true
printf '\n'
info "No es necesario reiniciar el VPS."
printf '\n'
line
