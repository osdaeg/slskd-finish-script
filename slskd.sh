#!/bin/bash
# =============================================================================
# slskd.sh — Script post-descarga de SLSKD
# Ubicación: /scripts/slskd.sh
# Logs: /app/scripts/finished.log
# =============================================================================

source /app/scripts/.env

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"
}

# -----------------------------------------------------------------------------
# Notificación Gotify
# -----------------------------------------------------------------------------
gotify_notify() {
    local title="$1"
    local message="$2"
    local priority="${3:-5}"

    wget -q -O- \
        --post-data="" \
        --header="X-Gotify-Key: ${GOTIFY_TOKEN}" \
        --header="Content-Type: application/x-www-form-urlencoded" \
        "${GOTIFY_URL}?title=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$title" 2>/dev/null || printf '%s' "$title" | od -A n -t x1 | tr -d ' \n' | sed 's/../%&/g')&message=$(printf '%s' "$message" | sed 's/ /+/g')&priority=${priority}" \
        > /dev/null 2>&1 || true

    # Alternativa más limpia con curl (si estuviera disponible):
    # curl -s -X POST "$GOTIFY_URL" \
    #     -H "X-Gotify-Key: ${GOTIFY_TOKEN}" \
    #     -F "title=${title}" \
    #     -F "message=${message}" \
    #     -F "priority=${priority}"
}

# Gotify con wget usando form urlencoded simple (sin encoding especial)
gotify_send() {
    local title="$1"
    local message="$2"
    local priority="${3:-5}"

    log "Gotify: [P${priority}] ${title} — ${message}"

    if [ "$NOTIFICATION" == "yes" ]; then
        wget -q -O /dev/null \
          --post-data="title=${title}&message=${message}&priority=${priority}" \
          --header="X-Gotify-Key: ${GOTIFY_TOKEN}" \
          "${GOTIFY_URL}" 2>>"$LOGFILE" || log "WARN: Falló notificación Gotify"
    fi      
}

# -----------------------------------------------------------------------------
# Subir log a pastebin y notificar error (usa wget + python3, sin curl)
# -----------------------------------------------------------------------------
paste_error() {
    local context="${1:-error desconocido}"
    local log_content
    log_content=$(tail -100 "$LOGFILE" 2>/dev/null)
    [ -z "$log_content" ] && log_content="(sin log disponible)"

    # Construir JSON con python3 para escapar correctamente el contenido
    local payload paste_id paste_url
    payload=$(python3 -c "
import json, sys
title = 'slskd: ${FILENAME:-desconocido} — ${context}'
content = sys.stdin.read()
print(json.dumps({
    'title': title,
    'content': content,
    'language': 'plaintext',
    'ttl_seconds': 604800
}))
" <<< "$log_content")

    local resp
    resp=$(wget -q -O- \
        --post-data="$payload" \
        --header="Content-Type: application/json" \
        "${PASTEBIN_URL}/api/pastes" 2>/dev/null)

    paste_id=$(echo "$resp" | jq -r '.id // empty' 2>/dev/null)

    if [ -n "$paste_id" ]; then
        paste_url="${PASTEBIN_URL}/p/${paste_id}"
        log "Log subido a pastebin: ${paste_url}"
        gotify_send "SLSKD: Error" "${context} — Log: ${paste_url}" 10
    else
        log "WARN: No se pudo subir el log a pastebin."
        gotify_send "SLSKD: Error" "${context} (pastebin no disponible)" 10
    fi
}

# Trap global para errores inesperados
if [ "$PASTEBIN" == "yes" ]; then
    trap 'paste_error "error inesperado en línea $LINENO (exit $?)"' ERR
fi    

# -----------------------------------------------------------------------------
# Parseo del evento
# -----------------------------------------------------------------------------
log "=========================================="
log "Evento recibido"

EVENT_TYPE=$(echo "$SLSKD_SCRIPT_DATA" | jq -r '.type' 2>/dev/null)

if [ "$EVENT_TYPE" != "DownloadFileComplete" ]; then
    log "Tipo de evento ignorado: ${EVENT_TYPE}"
    exit 0
fi

FILEPATH=$(echo "$SLSKD_SCRIPT_DATA" | jq -r '.localFilename' 2>/dev/null)
FILENAME=$(basename "$FILEPATH")
FILESIZE_BYTES=$(echo "$SLSKD_SCRIPT_DATA" | jq -r '.transfer.size' 2>/dev/null)
FILESIZE_MB=$(echo "scale=2; ${FILESIZE_BYTES} / 1048576" | bc 2>/dev/null || echo "?")
USERNAME=$(echo "$SLSKD_SCRIPT_DATA" | jq -r '.transfer.username' 2>/dev/null)
EXTENSION="${FILENAME##*.}"
EXTENSION_LOWER=$(echo "$EXTENSION" | tr '[:upper:]' '[:lower:]')

log "Archivo: ${FILEPATH}"
log "Tamaño: ${FILESIZE_MB} MB"
log "Usuario: ${USERNAME}"

# -----------------------------------------------------------------------------
# PASO 1: Archivo de bloqueo
# -----------------------------------------------------------------------------
log "Creando lockfile: ${LOCKFILE}"
touch "$LOCKFILE"

# -----------------------------------------------------------------------------
# PASO 2: Notificación de descarga finalizada
# -----------------------------------------------------------------------------


gotify_send "SLSKD: Descarga completa" "${FILENAME} (${FILESIZE_MB} MB) de ${USERNAME}" 5


# -----------------------------------------------------------------------------
# PASO 3: Escaneo antivirus con ClamAV
# -----------------------------------------------------------------------------

if [ "$CLAMAV" == "yes" ]; then
    log "Escaneando con ClamAV: ${FILEPATH}"

    CLEAN_FILE=""
    SCAN_RESULT=""
    IS_INFECTED=false

# NOTA: wget no soporta multipart/form-data nativamente.
# El escaneo ClamAV requiere multipart. Si se dispone de curl en el futuro,
# descomentar el bloque curl y eliminar el mensaje de omisión.

# Con curl (comentado — curl no disponible en esta imagen):
# SCAN_RESPONSE=$(curl -s -X POST "$CLAMAV_URL" \
#     -F "FILES=@\"${FILEPATH}\"")
# IS_INFECTED=$(echo "$SCAN_RESPONSE" | jq -r '.data.result[0].is_infected' 2>/dev/null)
# VIRUSES=$(echo "$SCAN_RESPONSE" | jq -r '.data.result[0].viruses | join(", ")' 2>/dev/null)
#
# if [ "$IS_INFECTED" = "true" ]; then
#     log "INFECTADO: ${FILENAME} — ${VIRUSES}"
#     rm -f "$FILEPATH" && log "Eliminado: ${FILEPATH}"
#     gotify_send "SLSKD: VIRUS DETECTADO" "${FILENAME} infectado con: ${VIRUSES}. Archivo eliminado." 10
# else
#     log "Limpio: ${FILENAME}"
#     CLEAN_FILE="$FILEPATH"
#     gotify_send "SLSKD: Escaneo OK" "${FILENAME} limpio." 1
# fi

# Sin curl: omitir escaneo y asumir archivo limpio
    log "WARN: curl no disponible — escaneo ClamAV omitido. Asumiendo archivo limpio."
    CLEAN_FILE="$FILEPATH"
    gotify_send "SLSKD: Escaneo omitido" "curl no disponible. ${FILENAME} no fue escaneado." 5
fi

# Si CLAMAV=no, no hay escaneo que defina CLEAN_FILE → se asume archivo limpio
CLEAN_FILE="$FILEPATH"

# -----------------------------------------------------------------------------
# PASO 4: Butler-API — ficha HTML (solo música)
# -----------------------------------------------------------------------------
if [ "$BUTLER" == "yes" ]; then
    if [ -n "$CLEAN_FILE" ]; then
        if echo "$EXTENSION_LOWER" | grep -qE "^(${MUSIC_EXTENSIONS})$"; then
            log "Generando ficha Butler-API para: ${FILENAME}"

            BUTLER_RESPONSE=$(wget -q -O- \
              --post-data="filename=${FILENAME}" \
              "$BUTLER_URL" 2>>"$LOGFILE")

            # Alternativa con curl (si estuviera disponible):
            # BUTLER_RESPONSE=$(curl -s -X POST "$BUTLER_URL" \
            #     -F "filename=${FILENAME}")

            BUTLER_STATUS=$(echo "$BUTLER_RESPONSE" | jq -r '.status' 2>/dev/null)
            BUTLER_TITULO=$(echo "$BUTLER_RESPONSE" | jq -r '.titulo' 2>/dev/null)

            if [ "$BUTLER_STATUS" = "ok" ]; then
                log "Ficha generada: ${BUTLER_TITULO}"
            else
                log "WARN: Butler-API no devolvió ok para ${FILENAME}. Respuesta: ${BUTLER_RESPONSE}"
                gotify_send "SLSKD: Error ficha" "No se pudo generar ficha para ${FILENAME}" 5
            fi
        else
            log "Extensión '${EXTENSION_LOWER}' no requiere ficha Butler-API."
        fi
    else
        log "No hay archivo limpio disponible para Butler-API."
    fi
fi    

# -----------------------------------------------------------------------------
# PASO 5: Eliminar archivo de bloqueo
# -----------------------------------------------------------------------------
log "Eliminando lockfile: ${LOCKFILE}"
rm -f "$LOCKFILE"

log "Script finalizado OK"
log "=========================================="

exit 0
