#!/bin/bash

FALLBACK_SCRIPT="/usr/local/bin/run_backup_fallback.sh"
LOG_FILE="/var/log/backup_fallback.log"
CRON_ENTRY="0 4 * * * $FALLBACK_SCRIPT >> $LOG_FILE 2>&1"

echo "[INFO] Criando script de fallback em $FALLBACK_SCRIPT"

cat <<EOF > "$FALLBACK_SCRIPT"
#!/bin/bash
CONTAINER_NAME="postgres_backup"
BACKUP_SCRIPT="/usr/local/bin/backup.sh"

echo "[HOST] Executando fallback \$(date)"
docker exec "\$CONTAINER_NAME" "\$BACKUP_SCRIPT"
EOF

chmod +x "$FALLBACK_SCRIPT"

LOG_DIR=$(dirname "$LOG_FILE")
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

echo "[INFO] Verificando cron..."
( crontab -l 2>/dev/null | grep -v "$FALLBACK_SCRIPT" ; echo "$CRON_ENTRY" ) | crontab -

echo "[OK] Cron configurado. Você pode ver com: crontab -l"
echo "[OK] Script de fallback: $FALLBACK_SCRIPT"
echo "[OK] Logs em: $LOG_FILE"
