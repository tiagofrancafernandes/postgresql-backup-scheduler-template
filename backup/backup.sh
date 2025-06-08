#!/bin/bash

CURRENT_PATH=$(dirname "$(readlink -f $0)")

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

BACKUPS_DIR="${CURRENT_PATH}/backups"

FILENAME="${BACKUPS_DIR}/${POSTGRES_DB}_${TIMESTAMP}.sql.gz"
LOG_FILE="${BACKUPS_DIR}/backup.log"
ERROR_LOG_FILE="${BACKUPS_DIR}/backup_errors.log"

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

PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -h "$POSTGRES_HOST" -U "$POSTGRES_USER" "$POSTGRES_DB" | gzip >"${FILENAME}"
if [ $? -ne 0 ]; then
    MSG="[ERRO] Falha no backup de ${POSTGRES_DB} em ${TIMESTAMP}"
    echo "${MSG}" | tee -a "${ERROR_LOG_FILE}"
    send_alert_via_email "${MSG}"
    send_alert_via_webhook "${MSG}"
    exit 1
fi

echo "[INFO] Backup salvo: ${FILENAME}" | tee -a "${LOG_FILE}"

sha256sum "${FILENAME}" >"${FILENAME}.sha256"
sha256sum -c "${FILENAME}.sha256"

if [ $? -ne 0 ]; then
    MSG="[ERRO] Falha na verificação de integridade: ${FILENAME}"
    echo "${MSG}" | tee -a "${ERROR_LOG_FILE}"
    send_alert_via_email "${MSG}"
    send_alert_via_webhook "${MSG}"
    exit 1
fi

echo "[INFO] Verificação de integridade OK" | tee -a "$LOG_FILE"

find "${BACKUPS_DIR}" -type f -name "*.gz" -mtime +${BACKUP_RETENTION_DAYS} -exec rm {} \;
find "${BACKUPS_DIR}" -type f -name "*.sha256" -mtime +${BACKUP_RETENTION_DAYS} -exec rm {} \;

if [ "${REMOTE_BACKUP_ENABLED}" = "on" ]; then
    if [ "${REMOTE_METHOD}" = "scp" ]; then
        scp "${FILENAME}" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"
    elif [ "${REMOTE_METHOD}" = "ftp" ]; then
        lftp -e "put ${FILENAME} -o ${REMOTE_PATH}; bye" -u "${REMOTE_USER}" "${REMOTE_HOST}"
    fi
fi

echo "[INFO] Backup e envio concluídos." | tee -a "$LOG_FILE"
