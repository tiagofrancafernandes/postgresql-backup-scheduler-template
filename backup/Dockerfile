FROM php:8.2-cli

RUN apt-get update && \
    apt-get install -y cron openssh-client lftp gzip postgresql-client sendmail && \
    docker-php-ext-install pcntl

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

COPY crontab /etc/cron.d/backup-cron
RUN chmod 0644 /etc/cron.d/backup-cron && \
    crontab /etc/cron.d/backup-cron

CMD ["cron", "-f"]
