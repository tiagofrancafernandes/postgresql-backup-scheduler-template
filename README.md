# Ambiente Docker com PostgreSQL 16 + Backup Automatizado

Este ambiente configura um banco PostgreSQL 16 em Docker com backups automáticos, retenção de 7 dias e envio remoto via SCP/FTP.

## Passos de uso

### 1. Criar volume nomeado externo

```bash
docker volume create external_postgres_data
```

### 2. Configurar o arquivo `.env`

(variáveis de ambiente já incluídas no projeto)

### 3. Subir o ambiente

```bash
docker-compose up -d --build
```

### 4. (Opcional) Configurar fallback no host

```bash
chmod +x setup_cron.sh
./setup_cron.sh
```

## Observações

- O volume `external_postgres_data` é **externo** e **não será removido** com `docker-compose down -v`.
- Os backups são comprimidos com `gzip`, validados com `sha256sum`, mantidos por 7 dias, e enviados via `scp` ou `ftp`.

Feito com ❤️ para ambientes PostgreSQL resilientes.
