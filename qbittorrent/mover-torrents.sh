#!/usr/bin/env bash
# Move os downloads concluídos do qBittorrent para o Nextcloud do davi
# e atualiza o índice de arquivos do Nextcloud.
# Uso: sudo /usr/local/bin/mover-torrents.sh  (ou automático via systemd/mover-torrents.path)
set -euo pipefail

ORIGEM="/opt/qbittorrent/downloads/complete"
NC_DATA="/srv/nextcloud"
NC_USER="davi"
DESTINO="$NC_DATA/$NC_USER/files/Torrents"
NC_CONTAINER="nextcloud-app"
NC_UID=33   # www-data dentro do container (podman rootful, sem userns)
NC_GID=33

if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

# Nada a mover? (ignora os arquivos internos .parts do qBittorrent)
if [[ -z "$(find "$ORIGEM" -mindepth 1 -maxdepth 1 ! -name '.*.parts' -print -quit)" ]]; then
    echo "Nada para mover em $ORIGEM."
    exit 0
fi

echo ">> Criando $DESTINO (se necessário)"
install -d -o "$NC_UID" -g "$NC_GID" -m 750 "$DESTINO"

echo ">> Movendo arquivos"
rsync -a --remove-source-files --exclude='/.*.parts' --info=progress2 \
    "$ORIGEM"/ "$DESTINO"/
# Remove as pastas que ficaram vazias na origem (mantém a própria pasta complete)
find "$ORIGEM" -mindepth 1 -type d -empty -delete

echo ">> Ajustando dono e permissões"
chown -R "$NC_UID:$NC_GID" "$DESTINO"
find "$DESTINO" -type d -exec chmod 750 {} +
find "$DESTINO" -type f -exec chmod 640 {} +

echo ">> Ajustando contexto SELinux"
chcon -R --reference="$NC_DATA/$NC_USER/files" "$DESTINO"

echo ">> Atualizando o Nextcloud"
podman exec -u www-data "$NC_CONTAINER" \
    php occ files:scan --path="/$NC_USER/files/Torrents"

echo ">> Concluído."
