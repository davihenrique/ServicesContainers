#!/usr/bin/env bash
# Prepara o host Fedora (podman rootful) e sobe o qBittorrent.
# Rode de dentro da pasta do serviço (ex.: /opt/qbittorrent):  sudo bash setup.sh
# Pode ser executado de novo sem problemas (idempotente).
set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
QBT_UID=33   # PUID/PGID do compose.yml
QBT_GID=33

if [[ $EUID -ne 0 ]]; then
    exec sudo bash "$0" "$@"
fi
cd "$BASE"

echo ">> Pacotes"
for pkg in podman podman-compose rsync; do
    rpm -q "$pkg" &>/dev/null || dnf install -y "$pkg"
done

echo ">> Pastas (o podman, diferente do docker, não cria a origem de bind mounts)"
install -d -o "$QBT_UID" -g "$QBT_GID" config downloads downloads/incomplete downloads/complete
# Migra o layout antigo (./incomplete e ./complete na raiz), se existir
for d in incomplete complete; do
    if [[ -d "$d" ]]; then
        echo "   migrando ./$d -> ./downloads/$d"
        rsync -a --remove-source-files "$d"/ "downloads/$d"/
        find "$d" -depth -type d -empty -delete
    fi
done
chown -R "$QBT_UID:$QBT_GID" downloads

echo ">> custom-cont-init.d (a imagem linuxserver só executa scripts do root)"
chown -R root:root custom-cont-init.d
chmod 755 custom-cont-init.d custom-cont-init.d/*.sh

echo ">> mover-torrents.sh e units do systemd"
# install cria arquivos novos, então recebem o rótulo SELinux padrão do destino
# (bin_t / systemd_unit_file_t). Os caminhos são ajustados para onde o repo está.
sed "s|^ORIGEM=.*|ORIGEM=\"$BASE/downloads/complete\"|" mover-torrents.sh > /tmp/mover-torrents.sh
install -m 755 /tmp/mover-torrents.sh /usr/local/bin/mover-torrents.sh
rm -f /tmp/mover-torrents.sh
sed "s|^PathChanged=.*|PathChanged=$BASE/config/torrent-finished|" systemd/mover-torrents.path > /tmp/mover-torrents.path
install -m 644 /tmp/mover-torrents.path /etc/systemd/system/mover-torrents.path
rm -f /tmp/mover-torrents.path
install -m 644 systemd/mover-torrents.service /etc/systemd/system/mover-torrents.service
restorecon /usr/local/bin/mover-torrents.sh /etc/systemd/system/mover-torrents.{path,service}
systemctl daemon-reload
systemctl enable --now mover-torrents.path

echo ">> Reinício automático no boot (restart: always no podman depende deste serviço)"
systemctl enable podman-restart.service

if systemctl is-active --quiet firewalld; then
    echo ">> Firewall"
    firewall-cmd --permanent --add-port=8080/tcp --add-port=6881/tcp --add-port=6881/udp >/dev/null
    firewall-cmd --reload >/dev/null
fi

echo ">> Subindo o container"
podman-compose down || true
podman-compose up -d

echo ">> Concluído. Verifique:"
echo "   podman logs qbittorrent | grep config-qbittorrent"
echo "   journalctl -u mover-torrents -f"
