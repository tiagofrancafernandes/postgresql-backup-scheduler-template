FROM php:8.4-cli

# Evita prompts interativos durante a instalação
ENV DEBIAN_FRONTEND=noninteractive

# Instala dependências necessárias
RUN apt-get update && apt-get install -y wget gnupg lsb-release ca-certificates

# Adiciona o repositório oficial do PostgreSQL
RUN echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list

# Importa a chave GPG oficial
RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

# Atualiza a lista de pacotes e instala o cliente
RUN apt-get update && apt-get install -y postgresql-client-16

RUN apt-get update && \
    apt-get install -y cron openssh-client lftp gzip sendmail && \
    docker-php-ext-install pcntl

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

COPY crontab /etc/cron.d/backup-cron
RUN chmod 0644 /etc/cron.d/backup-cron && \
    crontab /etc/cron.d/backup-cron

# Limpa cache do apt para reduzir o tamanho da imagem
RUN apt-get clean && rm -rf /var/lib/apt/lists/*
CMD ["cron", "-f"]
