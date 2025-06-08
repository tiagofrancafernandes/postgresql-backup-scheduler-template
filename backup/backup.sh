#!/bin/bash
set -e

CURRENT_PATH=$(dirname "$(readlink -f $0)")

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

if [ -f "${CURRENT_PATH}/../.env" ]; then
    source "${CURRENT_PATH}/../.env"
else
    echo "[ERROR] .env file not found"
    exit 1
fi

if [ -z "${POSTGRES_USER}" ]; then
    echo "[ERROR] POSTGRES_USER is not set"
    exit 1
fi

############ DEFAULTS #########
BACKUP_DB_NAME="${BACKUP_DB_NAME:-$POSTGRES_DB}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
REMOTE_HOST="${REMOTE_HOST:-localhost}"
REMOTE_PORT="${REMOTE_PORT:-22}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
REMOTE_METHOD="${REMOTE_METHOD:-scp}"
BACKUP_EXTENSION="${BACKUP_EXTENSION:-sql.gz}"
####### END OF DEFAULTS #######

if [ -z "${BACKUP_DB_NAME}" ]; then
    echo "[ERROR] BACKUP_DB_NAME is not set"
    exit 1
fi

BACKUPS_DIR="${CURRENT_PATH}/../backups"

if [ ! -d "${BACKUPS_DIR}" ]; then
    echo "[INFO] Criando diretório de backups em ${BACKUPS_DIR}"
    mkdir -p "${BACKUPS_DIR}"
    chmod 777 "${BACKUPS_DIR}"
fi

BACKUP_FILENAME="${BACKUPS_DIR}/${BACKUP_DB_NAME}_${TIMESTAMP}"

# sql.gz ou gzip
if [ "${BACKUP_EXTENSION}" = "sql.gz" ] || [ "${BACKUP_EXTENSION}" = "gzip" ]; then
    BACKUP_FILENAME="${BACKUP_FILENAME}.sql.gz"
    # echo "[INFO] Backup com compressão gzip"
elif [ "${BACKUP_EXTENSION}" = "sql" ]; then
    BACKUP_FILENAME="${BACKUP_FILENAME}.sql"
    # echo "[INFO] Backup sem compressão"
elif [ "${BACKUP_EXTENSION}" = "zip" ]; then
    BACKUP_FILENAME="${BACKUP_FILENAME}.zip"
    # echo "[INFO] Backup com compressão zip"
else
    BACKUP_FILENAME="${BACKUP_FILENAME}.sql"
    # echo "[INFO] Backup sem compressão (...)"
fi

LOG_FILE="${BACKUPS_DIR}/backup.log"
ERROR_LOG_FILE="${BACKUPS_DIR}/backup_errors.log"

if [ ! -f "${LOG_FILE}" ]; then
    echo "[INFO] Criando arquivo de backup em ${LOG_FILE}"
    touch "${LOG_FILE}"
    chmod 777 "${LOG_FILE}"
fi

if [ ! -f "${ERROR_LOG_FILE}" ]; then
    echo "[INFO] Criando arquivo de backup em ${ERROR_LOG_FILE}"
    touch "${ERROR_LOG_FILE}"
    chmod 777 "${ERROR_LOG_FILE}"
fi

echo "[INFO] Iniciando backup em ${TIMESTAMP}" | tee -a "$LOG_FILE"

function send_alert_via_email() {
    if [ "${SEND_ALERT_VIA_EMAIL_ENABLED}" = "on" ]; then
        echo "[INFO] Enviando alerta por e-mail"
        local SUBJECT="[ALERTA] Backup PostgreSQL"
        local TO="admin@example.com"
        local MESSAGE="$1"
        echo -e "Subject: ${SUBJECT}\n\n${MESSAGE}" | sendmail -v "${TO}"
    fi
}

function send_alert_via_webhook() {
    if [ "${SEND_ALERT_VIA_WEBHOOK_ENABLED}" = "on" ]; then
        local WEBHOOK_METHOD="${WEBHOOK_METHOD:-POST}"
        if [ -n "${WEBHOOK_URL}" ]; then
            echo "[INFO] Enviando alerta via webhook"
            curl -s -X ${WEBHOOK_METHOD} -H "Content-Type: application/json" \
                -d "{"text":"$1"}" "${WEBHOOK_URL}"
        fi
    fi
}

# sql.gz ou gzip
if [ "${BACKUP_EXTENSION}" = "sql.gz" ] || [ "${BACKUP_EXTENSION}" = "gzip" ]; then
    echo -e "[INFO] Backup com compressão gzip"
    PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump -h "${POSTGRES_HOST}" -U "${POSTGRES_USER}" -p "${POSTGRES_PORT}" "${BACKUP_DB_NAME}" | gzip >"${BACKUP_FILENAME}"
elif [ "${BACKUP_EXTENSION}" = "zip" ]; then
    echo -e "[INFO] Backup com compressão zip"
    PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump -h "${POSTGRES_HOST}" -U "${POSTGRES_USER}" -p "${POSTGRES_PORT}" "${BACKUP_DB_NAME}" | zip >"${BACKUP_FILENAME}"
else
    echo -e "[INFO] Backup sem compressão (...)"
    PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump -h "${POSTGRES_HOST}" -U "${POSTGRES_USER}" -p "${POSTGRES_PORT}" "${BACKUP_DB_NAME}" > "${BACKUP_FILENAME}"
fi

if [ $? -ne 0 ]; then
    MSG="[ERRO] Falha no backup de ${BACKUP_DB_NAME} em ${TIMESTAMP}"
    echo "${MSG}" | tee -a "${ERROR_LOG_FILE}"
    send_alert_via_email "${MSG}"
    send_alert_via_webhook "${MSG}"
    exit 1
fi

echo "[INFO] Backup salvo: ${BACKUP_FILENAME}" | tee -a "${LOG_FILE}"

sha256sum "${BACKUP_FILENAME}" >"${BACKUP_FILENAME}.sha256"
sha256sum -c "${BACKUP_FILENAME}.sha256"

if [ $? -ne 0 ]; then
    MSG="[ERRO] Falha na verificação de integridade: ${BACKUP_FILENAME}"
    echo "${MSG}" | tee -a "${ERROR_LOG_FILE}"
    send_alert_via_email "${MSG}"
    send_alert_via_webhook "${MSG}"
    exit 1
fi

echo "[INFO] Verificação de integridade OK" | tee -a "${LOG_FILE}"

if [ $BACKUP_RETENTION_DAYS -gt 0 ]; then
    echo "[INFO] Removendo backups antigos"
    find "${BACKUPS_DIR}" -type f -name "*.sql" -mtime +${BACKUP_RETENTION_DAYS} -exec rm {} \;
    find "${BACKUPS_DIR}" -type f -name "*.zip" -mtime +${BACKUP_RETENTION_DAYS} -exec rm {} \;
    find "${BACKUPS_DIR}" -type f -name "*.gz" -mtime +${BACKUP_RETENTION_DAYS} -exec rm {} \;
    find "${BACKUPS_DIR}" -type f -name "*.sha256" -mtime +${BACKUP_RETENTION_DAYS} -exec rm {} \;
fi

if [ "${REMOTE_BACKUP_ENABLED}" = "on" ]; then
    if [ "${REMOTE_METHOD}" = "scp" ]; then
        echo -e "[INFO] Enviando backup para o servidor remoto via scp"
        # scp "${BACKUP_FILENAME}" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"
        # scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${BACKUP_FILENAME}" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"

        if [ -n "${REMOTE_KEY_PATH}" ]; then
            scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "${REMOTE_KEY_PATH}" -P "${REMOTE_PORT}" "${BACKUP_FILENAME}" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"
        else
            scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P "${REMOTE_PORT}" "${BACKUP_FILENAME}" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"
        fi
    elif [ "${REMOTE_METHOD}" = "ftp" ]; then
        echo -e "[INFO] Enviando backup para o servidor remoto via FTP"
        lftp -e "put ${BACKUP_FILENAME} -o ${REMOTE_PATH}; bye" -u "${REMOTE_USER}" -p "${REMOTE_PORT}" "${REMOTE_HOST}"
    fi
fi

FINAL_MESSEGE="[INFO] Backup concluído"
if [ "${REMOTE_BACKUP_ENABLED}" = "on" ]; then
    FINAL_MESSEGE="${FINAL_MESSEGE} e enviado para os destinos remotos"
fi

echo "${FINAL_MESSEGE}" | tee -a "${LOG_FILE}"
